## native_tools.nim — thin dispatch layer for all native (non-MCP) tools.
##
## Tool implementations live under app/tools/:
##   fs_tools       — paddock resolution, bash
##   text_tools      — hashline anchors, HTML stripping, todo_write
##   search_tools    — find, grep (with log.warn on errors)
##   web_tools       — fetch, Brave web_search
##   utility_tools   — calc, render_mermaid, inspect_image
##   task_tools      — task/job spawning, skill management
##
## executeNativeTool returns NativeToolResult:
##   handled=false  -> not a native tool; orchestrator falls through to ToolAgent
##   handled=true   -> result.text is the tool output
##   newHistory.isSome -> orchestrator must replace history (rewind)
##   checkpointNow  -> orchestrator must push current history to state.checkpoints

# ── Re-export all extracted tool modules (public API stability) ───────────────

import ./tools/fs_tools
import ./tools/text_tools
import ./tools/search_tools
import ./tools/web_tools
import ./tools/archive_tools
import ./tools/data_tools
import ./tools/utility_tools
import ./tools/audio_tools
import ./tools/task_tools
import ./named_agents
import ./task_board
import ../domain/agents/named_agent_pure
import ./credential_runtime
import ./tools/code_tools
import ./tools/memory_ingest_io

export fs_tools        # resolveInPaddock, inPaddock, performBash
export text_tools      # HashlineAnchor, EditFileOpKind, EditFileOp, hashline
                       # helpers, stripHtml, applyTodoOps
export search_tools    # performFind, performFindWasm, performGrep, performGrepWasm
export web_tools       # FetchHardMax, FetchDefaultMax, performFetch, performWebSearch
export archive_tools   # performArchiveCreate, performArchiveExtract
export data_tools      # runJsonQuery, runTableQuery
export utility_tools   # performCalc, performRenderMermaid, performInspectImage,
                       # MermaidTempPrefix
export audio_tools     # performTranscribe, performSpeech
export task_tools      # performTask, nextJobId, buildTaskStartedText,
                       # spawnTaskJob, performManageSkills
export code_tools      # parseCodeRequest, runCodeRequestAsync, codeConfigFromEnv

# ── Dispatcher-only imports ──────────────────────────────────────────────────

import std/[json, options, tables, sequtils, strutils, times, os]
import checksums/sha1
import chronos
import chronos/asyncsync
import ../core/tooling/native_tool_dispatch
import ../core/pipeops
import ../core/log
import ../core/utf8
import ../ports/fs
import ../core/security/approval
import ../domain/message
import ../domain/more_tools
import ../domain/builtin_tools
import ../domain/memory/provenance_pure
import ../domain/memory/session_search_pure
import ../domain/memory/ingest_pure
import ../domain/subagent_pure
import ../domain/reminder
import ../ports/http as httpPort
import ../ports/provider
import ../ports/memory
import ../ports/reminders
import ../ports/schedules
import ./user_schedules
import ./conversation_search
import ../ports/process
import ../ports/attachment_store
import ../core/tooling/native_tool_args
export native_tool_args  # argument contexts and their pure parsers
import ../config/types as cfgTypes
import ../config/environment
from ./skill_runtime import skillRegistry
import ../infra/sandbox/wasm_tools
import ./sandbox
import ./session_state
import ./session_manager
import ./approval_runtime
import ./offloop_io
import ./tools/github_git_tools
import ./skill_tools
import ./provider_executor

const
  AskInterruptedText* = "Error: ask interrupted."
    ## Wake-up the ingress sends when a new API turn cancels the open ask. The
    ## tool loop stops the batch on this result instead of starting the next
    ## tool, so the old turn cannot block on a second question.

# ── Result type ───────────────────────────────────────────────────────────────

type
  NativeToolResult* = object
    handled*:       bool
    text*:          string
    resultKind*:    ToolResultKind
    newHistory*:    Option[ConversationHistory]
    checkpointNow*: bool
    outbound*:      Option[OutboundMessage]
      ## Set when the tool produced a message the channel must deliver
      ## (`executeNativeCategory` enqueues it once).

# ── Context types (parsing only — execution delegated to tool modules) ────────

type
  SpawnSubagentFn* = proc(request: SubagentRequest):
      Future[SubagentSpawnResult] {.gcsafe, raises: [].}
  AwaitSubagentFn* = proc(subagentId: string; stopGeneration: uint64;
                          userId: string; userInterrupt: uint64):
      Future[SubagentResult] {.gcsafe, raises: [].}
  ListSubagentsFn* = proc(): seq[SubagentInfo] {.gcsafe, raises: [].}
  CancelSubagentFn* = proc(subagentId: string):
      Future[bool] {.gcsafe, raises: [].}
  BeforeEffectFn* = proc(toolName: string) {.gcsafe, raises: [].}

  NativeCtx* = object
    uid*:          UserId
    channel*:      ChannelKind
    outbox*:       AsyncQueue[OutboundMessage]
    session*:      ptr SessionEntry
    memory*:       MemoryRuntimePort
    reminders*:    ReminderPort
    schedules*:    SchedulePort  ## where manage_schedules keeps the user's jobs
    fs*:           FsRuntimePort
    process*:      ProcessRuntimePort
    attachments*:  AttachmentStorePort  ## where generated files (speech) are kept
    completeFn*:   CompleteFn
    asyncCompleteFn*: AsyncCompleteFn
    http*:         httpPort.HttpRuntimePort
    braveApiKey*:  string
    env*:          Environment  ## the snapshot tool settings are read from
    webAllowlist*: seq[string]
    toolWebPolicy*: seq[cfgTypes.ToolWebPolicy]
    tools*:        seq[ToolDescription]
    approval*:     ApprovalService
    log*:          Logger
    paddockDir*:   string
    replyTo*:      string   ## inbound reply anchor, so a voice note stays in the forum topic
    sandboxMode*:  SandboxMode
    sandboxRuntimeCmd*: string
    sandboxImage*: string
    sandboxAllowHostFallback*: bool
    sandboxAllowNetwork*: bool
    sandboxReadOnlyRootfs*: bool
    ## Subagent policy. `restrictTools=false` is the normal parent session;
    ## a child sets it to true and only the listed names may execute.
    restrictTools*: bool
    allowedTools*: seq[string]
    subagentId*: string
    subagentDepth*: int
    stopGeneration*: uint64
    userInterrupt*: uint64   ## per-user /stop counter captured at turn start
    scopeSessionId*: string
    budget*: SubagentUsage
    budgetLimits*: SubagentLimits
    spawnSubagent*: SpawnSubagentFn
    awaitSubagent*: AwaitSubagentFn
    listSubagents*: ListSubagentsFn
    cancelSubagent*: CancelSubagentFn
    beforeEffect*: BeforeEffectFn
      ## Called before a tool with an effect runs (the turn journal's
      ## write-ahead, app/orchestrator); nil when nothing is journalled.

  NativeToolCategoryHandler = proc(tc: ToolCallRequest;
                                   ctx: NativeCtx;
                                   state: SessionState;
                                   history: ConversationHistory;
                                   j: JsonNode;
                                  ): Future[NativeToolResult] {.nimcall, gcsafe, raises: [].}

proc sessionStopRequested*(ctx: NativeCtx): bool {.gcsafe, raises: [].} =
  ## True when the process is shutting down or a `/stop` arrived after this
  ## turn started, even if the actor is still inside a long tool batch or
  ## approval wait. Comparing counters keeps a newer turn from inheriting an
  ## older stop.
  if isSessionStopRequested(ctx.stopGeneration):
    return true
  isUserStoppedSince($ctx.uid, ctx.userInterrupt)

# ── Context parsers ───────────────────────────────────────────────────────────

proc logToolPathFailure(log: Logger;
                        toolName, rawPath, paddockDir, resolvedPath, reason: string) {.gcsafe, raises: [].} =
  if log.sink == nil:
    return
  log.warn("native tool path rejected" &
           " tool=" & toolName &
           " raw=" & rawPath &
           " paddock=" & (if paddockDir.len > 0: paddockDir else: "<empty>") &
           " resolved=" & (if resolvedPath.len > 0: resolvedPath else: "<empty>") &
           " reason=" & reason)

proc resolvedToolPath(path, paddockDir: string;
                      log: Logger = Logger();
                      toolName = "";
                      fs: FsRuntimePort = unavailableFs()): Result[string, string] {.gcsafe, raises: [].} =
  if path.len == 0 or paddockDir.len == 0:
    if path.len > 0 and paddockDir.len == 0:
      logToolPathFailure(log, toolName, path, paddockDir, path, "empty_paddock")
    return ok(path)
  let resolvedPath = resolveInPaddock(path, paddockDir)
  if not inPaddock(resolvedPath, paddockDir):
    logToolPathFailure(log, toolName, path, paddockDir, resolvedPath, "outside_paddock")
    return err("Error: path outside paddock: " & path)
  let realPaddock = fs.canonicalNearestExisting(paddockDir).valueOr:
    return err("Error: cannot resolve paddock path: " & error)
  let realTarget = fs.canonicalNearestExisting(resolvedPath).valueOr:
    return err("Error: cannot resolve path safely: " & error)
  if realTarget != realPaddock and
     not realTarget.startsWith(realPaddock & $DirSep):
    logToolPathFailure(log, toolName, path, paddockDir, realTarget, "outside_paddock_symlink")
    return err("Error: path outside paddock (symlink): " & path)
  ok(resolvedPath)

# Arguments are parsed by `core/tooling/native_tool_args` (pure); tools that
# take a path resolve it inside the paddock here, where the file system is.

proc resolvedPathOf[T](parsed: Result[T, string]; paddockDir: string;
                       log: Logger; toolName: string;
                       fs: FsRuntimePort): Result[T, string] {.gcsafe, raises: [].} =
  ## `parsed` with its `path` resolved inside the paddock.
  var ctx = ?parsed
  ctx.path = ?resolvedToolPath(ctx.path, paddockDir, log, toolName, fs)
  ok(ctx)

proc parseReadFileContext*(j: JsonNode; paddockDir: string;
                           log: Logger = Logger(); toolName = ReadFileToolName;
                           fs: FsRuntimePort = unavailableFs()):
                           Result[ReadFileContext, string] {.gcsafe, raises: [].} =
  parseReadFileArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseFindContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger(); toolName = FindToolName;
                       fs: FsRuntimePort = unavailableFs()):
                       Result[FindContext, string] {.gcsafe, raises: [].} =
  parseFindArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseGrepContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger(); toolName = GrepToolName;
                       fs: FsRuntimePort = unavailableFs()):
                       Result[GrepContext, string] {.gcsafe, raises: [].} =
  parseGrepArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseSedContext*(j: JsonNode; paddockDir: string;
                      log: Logger = Logger(); toolName = SedToolName;
                      fs: FsRuntimePort = unavailableFs()):
                      Result[SedContext, string] {.gcsafe, raises: [].} =
  parseSedArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parsePathOnly*(j: JsonNode; paddockDir: string;
                    log: Logger = Logger(); toolName = "";
                    fs: FsRuntimePort = unavailableFs()):
                    Result[string, string] {.gcsafe, raises: [].} =
  resolvedToolPath(?j.requireStringField("path"), paddockDir, log, toolName, fs)

proc parseWcContext*(j: JsonNode; paddockDir: string;
                     log: Logger = Logger(); toolName = WcToolName;
                     fs: FsRuntimePort = unavailableFs()):
                     Result[WcContext, string] {.gcsafe, raises: [].} =
  parseWcArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseHeadTailContext*(j: JsonNode; paddockDir: string;
                           log: Logger = Logger(); toolName = "";
                           fs: FsRuntimePort = unavailableFs()):
                           Result[HeadTailContext, string] {.gcsafe, raises: [].} =
  parseHeadTailArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseSortContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger(); toolName = SortToolName;
                       fs: FsRuntimePort = unavailableFs()):
                       Result[SortContext, string] {.gcsafe, raises: [].} =
  parseSortArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseCpMvContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger(); toolName = "";
                       fs: FsRuntimePort = unavailableFs()):
                       Result[CpMvContext, string] {.gcsafe, raises: [].} =
  var ctx = ?parseCpMvArgs(j)
  ctx.source = ?resolvedToolPath(ctx.source, paddockDir, log, toolName, fs)
  ctx.dest = ?resolvedToolPath(ctx.dest, paddockDir, log, toolName, fs)
  ok(ctx)

proc parseInspectImageContext*(j: JsonNode; paddockDir: string;
                               log: Logger = Logger(); toolName = InspectImageToolName;
                               fs: FsRuntimePort = unavailableFs()):
                               Result[InspectImageContext, string] {.gcsafe, raises: [].} =
  parseInspectImageArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

proc parseTranscribeContext*(j: JsonNode; paddockDir: string;
                             log: Logger = Logger();
                             fs: FsRuntimePort = unavailableFs()):
                             Result[TranscribeContext, string] {.gcsafe, raises: [].} =
  parseTranscribeArgs(j).resolvedPathOf(paddockDir, log, TranscribeAudioToolName, fs)

proc parseEditFileContext*(j: JsonNode; paddockDir: string;
                           log: Logger = Logger(); toolName = EditFileToolName;
                           fs: FsRuntimePort = unavailableFs()):
                           Result[EditFileContext, string] {.gcsafe, raises: [].} =
  parseEditFileArgs(j).resolvedPathOf(paddockDir, log, toolName, fs)

# ── Result helpers ────────────────────────────────────────────────────────────

proc handledText(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOutput)

proc handledError(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOperationalError)

proc handledSubagentResult(subagentResult: SubagentResult): NativeToolResult
                                                       {.gcsafe, raises: [].} =
  ## The JSON contract is stable even on failure; only the result kind marks
  ## the operational error for the parent loop.
  NativeToolResult(
    handled: true,
    text: $subagentResult.toJson(),
    resultKind: if subagentResult.status in {ssFailed, ssTimedOut, ssCancelled}:
                  trkOperationalError
                else:
                  trkOutput,
  )

proc handledStructured(value: StructuredToolResult): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: value.toJson(), resultKind: value.kind)

proc normalizedErrorMessage(text: string): string =
  if text.startsWith("Error: "): text["Error: ".len .. ^1]
  else: text

func isOperationalErrorText(text: string): bool =
  text.startsWith("Error:") or
  text.startsWith("HTTP error ") or
  text.startsWith("Brave API error ")

proc handledOutcome(text: string): NativeToolResult {.gcsafe, raises: [].} =
  if isOperationalErrorText(text):
    handledError(text)
  else:
    handledText(text)

proc webToolResult(o: WebToolOutput): NativeToolResult {.gcsafe, raises: [].} =
  if o.structured: NativeToolResult(handled: true, text: o.text, resultKind: o.kind)
  else: handledOutcome(o.text)

proc runSpeech(job: SpeechJob; ctx: NativeCtx): Future[SpeechOutput] {.async.} =
  ## Off the loop through the installed runner, like the web tools; in
  ## place, through ctx's ports, when nothing is installed (tests).
  var job = job
  job.transportAllowlist = ctx.webAllowlist
  job.proxy = ctx.env.get("DONKEY_WEB_PROXY").strip()
  let io = offLoopIo()
  if io.speechTool != nil:
    return await io.speechTool(job)
  return runSpeechJob(job, ctx.fs, ctx.attachments, ctx.http)

proc runWeb(job: WebToolJob; ctx: NativeCtx): Future[WebToolOutput] {.async.} =
  ## Off the loop through the installed runner (app/offloop_io), with a
  ## transport like the session's; in place, through ctx.http, when nothing
  ## is installed (tests).
  var job = job
  job.transportAllowlist = ctx.webAllowlist
  job.proxy = ctx.env.get("DONKEY_WEB_PROXY").strip()
  let io = offLoopIo()
  if io.webTool != nil:
    return await io.webTool(job)
  return runWebToolJob(job, ctx.http)

proc buildCheckpointResult*(state: SessionState): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(
    handled: true,
    text: "Checkpoint " & $state.checkpoints.len & " saved.",
    resultKind: trkOutput,
    checkpointNow: true,
  )

proc buildSubmitResult*(j: JsonNode): NativeToolResult {.gcsafe, raises: [].} =
  handledText(j.getOrDefault("result").getStr(""))

proc buildRewindResult*(state: SessionState; idx: int): Result[NativeToolResult, string] {.gcsafe, raises: [].} =
  if idx < 0 or idx >= state.checkpoints.len:
    return err("Error: checkpoint index " & $idx & " out of range (0.." &
               $(state.checkpoints.len - 1) & ").")
  let restored = state.checkpoints[idx]
  ok(NativeToolResult(
    handled: true,
    text: "Rewound to checkpoint " & $idx & ".",
    resultKind: trkOutput,
    newHistory: some(restored),
  ))

# ── Job management helpers ────────────────────────────────────────────────────

proc cancelJob(state: SessionState; jobId: string): NativeToolResult =
  if jobId notin state.jobs:
    return handledError("Error: job '" & jobId & "' not found.")
  let job = state.jobs[jobId]
  if not job.done and not job.future.isNil:
    job.future.cancelSoon()
    state.jobs[jobId] = JobState(future: nil, done: true, result: "(cancelled)")
  handledText("Job " & jobId & " cancelled.")

proc awaitJobs(state: SessionState; ctx: AwaitContext): Future[NativeToolResult] {.async.} =
  var lines: seq[string] = @[]
  for id in ctx.ids:
    if id notin state.jobs:
      lines.add(id & ": not found")
      continue
    var job = state.jobs[id]
    if job.done:
      lines.add(id & ": " & job.result)
    else:
      try:
        let r = await job.future
        state.jobs[id] = JobState(future: nil, done: true, result: r)
        lines.add(id & ": " & r)
      except CancelledError:
        state.jobs[id] = JobState(future: nil, done: true, result: "(cancelled)")
        lines.add(id & ": cancelled")
      except CatchableError as e:
        state.jobs[id] = JobState(future: nil, done: true, result: "error - " & e.msg)
        lines.add(id & ": error - " & e.msg)
  handledOutcome(lines.join("\n"))

proc recordFinding(ctx: NativeCtx; findingCtx: FindingContext): NativeToolResult =
  ctx.log.info("[finding] " & findingCtx.finding)
  handledText("Finding recorded: " & findingCtx.finding)

# ── Category dispatch ─────────────────────────────────────────────────────────

proc toolWebRules(ctx: NativeCtx; toolName: string): seq[cfgTypes.WebAccessRule] =
  let cfg = cfgTypes.DonkeyConfig(
    webAllowlist: ctx.webAllowlist,
    toolWebPolicy: ctx.toolWebPolicy,
  )
  cfg.effectiveToolWebRules(toolName)

proc executeLegacyNativeTool(tc: ToolCallRequest;
                             ctx: NativeCtx;
                             state: SessionState;
                             history: ConversationHistory;
                             j: JsonNode;
                            ): Future[NativeToolResult] {.async.} =
  discard state; discard history
  case tc.name
  of ReminderToolName:
    let whenStr = j.getOrDefault("when").getStr("")
    let remMsg  = j.getOrDefault("message").getStr("")
    if whenStr.len == 0 or remMsg.len == 0:
      return handledError("Error: 'when' and 'message' are required.")
    if ctx.reminders.schedule == nil:
      return handledError("Error: reminders are not available.")
    let ts = reminder.parseWhen(whenStr, getTime().toUnix())
    let scheduled = ctx.reminders.schedule(ctx.uid, $ctx.channel, ts, remMsg)
    if scheduled.isErr:
      return handledError("Error: " & scheduled.error)
    return handledText("Reminder scheduled.")
  of CurrentTimeToolName:
    return now().utc() |> currentTimeResult |> handledText
  of WebFetchToolName:
    let url   = j.getOrDefault("url").getStr("")
    let maxCh = j.getOrDefault("max_chars").getInt(DefaultMaxChars)
    if url.len == 0: return handledError("Error: 'url' is required.")
    let rules = toolWebRules(ctx, WebFetchToolName)
    if not isAllowedPublicUrl(url, rules, ctx.webAllowlist):
      return handledError(buildUrlAccessError(url, rules, ctx.webAllowlist, WebFetchToolName))
    return webToolResult(await runWeb(WebToolJob(kind: wtkFetch, url: url, maxCh: maxCh,
      rules: rules, allowlist: ctx.webAllowlist, label: WebFetchToolName), ctx))
  else:
    return NativeToolResult(handled: false)

proc runWasmApplet*(applet: string; args: seq[string]; path: string): string {.gcsafe, raises: [].} =
  let adapter = newWasmToolAdapter()
  let parent = path.parentDir
  let r = adapter.runApplet(applet, args, if parent.len > 0: parent else: "/")
  if not r.success:
    return "Error: " & r.output
  r.output.strip()

proc performSedWasm*(expression, path: string): string {.gcsafe, raises: [].} =
  runWasmApplet("sed", @[expression, path], if path.parentDir.len > 0: path.parentDir else: "/")

proc executeShellNativeTool(tc: ToolCallRequest;
                            ctx: NativeCtx;
                            state: SessionState;
                            history: ConversationHistory;
                            j: JsonNode;
                           ): Future[NativeToolResult] {.async.} =
  discard state; discard history
  case tc.name
  of BashToolName:
    let bashCtx = parseBashContext(j).valueOr:
      return handledError(error)
    return handledOutcome(sandboxBash(ctx.process, ctx.fs, bashCtx.command, ctx.paddockDir,
                        ctx.sandboxMode, ctx.sandboxImage, ctx.sandboxRuntimeCmd,
                        ctx.sandboxAllowHostFallback, ctx.sandboxAllowNetwork,
                        ctx.sandboxReadOnlyRootfs))
  of ReadFileToolName:
    let readCtx = parseReadFileContext(j, ctx.paddockDir, ctx.log, ReadFileToolName, ctx.fs).valueOr:
      return handledError(error)
    let text = ctx.fs.readFile(readCtx.path).valueOr:
      return handledError("Error: " & error)
    return handledText(renderHashlineSlice(text, readCtx.startLine, readCtx.maxLines))
  of EditFileToolName:
    let editCtx = parseEditFileContext(j, ctx.paddockDir, ctx.log, EditFileToolName, ctx.fs).valueOr:
      return handledError(error)
    let original = ctx.fs.readFile(editCtx.path).valueOr:
      return handledError("Error: " & error)
    let applyResult = applyEditFileOps(splitEditableLines(original), editCtx.edits).valueOr:
      return handledError(error)
    let updated = applyResult.join("\n")
    ctx.fs.writeFile(editCtx.path, updated).isOkOr:
      return handledError("Error: " & error)
    return handledText(renderHashlineSlice(updated, 1, updated.splitLines().len))
  of FindToolName:
    let findCtx = parseFindContext(j, ctx.paddockDir, ctx.log, FindToolName, ctx.fs).valueOr:
      return handledError(error)
    let r = if ctx.sandboxMode == smWasm:
      performFindWasm(findCtx.path, findCtx.pattern, findCtx.kind, findCtx.max)
    else:
      performFind(ctx.fs, findCtx.path, findCtx.pattern, findCtx.kind, findCtx.max)
    return handledOutcome(r)
  of GrepToolName:
    let grepCtx = parseGrepContext(j, ctx.paddockDir, ctx.log, GrepToolName, ctx.fs).valueOr:
      return handledError(error)
    let r = if ctx.sandboxMode == smWasm:
      performGrepWasm(grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max)
    else:
      performGrep(ctx.fs, grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max)
    return handledOutcome(r)
  of SedToolName:
    let sedCtx = parseSedContext(j, ctx.paddockDir, ctx.log, SedToolName, ctx.fs).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("sed", @[sedCtx.expression, sedCtx.path],
      if sedCtx.path.parentDir.len > 0: sedCtx.path.parentDir else: "/"))
  of WcToolName:
    let wcCtx = parseWcContext(j, ctx.paddockDir, ctx.log, WcToolName, ctx.fs).valueOr:
      return handledError(error)
    var args: seq[string] = @[]
    if wcCtx.flags.len > 0:
      args.add(wcCtx.flags)
    args.add(wcCtx.path)
    return handledOutcome(runWasmApplet("wc", args, wcCtx.path))
  of HeadToolName:
    let headCtx = parseHeadTailContext(j, ctx.paddockDir, ctx.log, HeadToolName, ctx.fs).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("head", @["-n", $headCtx.lines, headCtx.path], headCtx.path))
  of TailToolName:
    let tailCtx = parseHeadTailContext(j, ctx.paddockDir, ctx.log, TailToolName, ctx.fs).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("tail", @["-n", $tailCtx.lines, tailCtx.path], tailCtx.path))
  of SortToolName:
    let sortCtx = parseSortContext(j, ctx.paddockDir, ctx.log, SortToolName, ctx.fs).valueOr:
      return handledError(error)
    var args: seq[string] = @[]
    if sortCtx.flags.len > 0:
      args.add(sortCtx.flags)
    args.add(sortCtx.path)
    return handledOutcome(runWasmApplet("sort", args, sortCtx.path))
  of CpToolName:
    let cpCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, CpToolName, ctx.fs).valueOr:
      return handledError(error)
    let parent = cpCtx.source.parentDir
    return handledOutcome(runWasmApplet("cp", @[cpCtx.source, cpCtx.dest],
      if parent.len > 0: parent else: "/"))
  of MvToolName:
    let mvCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, MvToolName, ctx.fs).valueOr:
      return handledError(error)
    let parent = mvCtx.source.parentDir
    return handledOutcome(runWasmApplet("mv", @[mvCtx.source, mvCtx.dest],
      if parent.len > 0: parent else: "/"))
  of RmToolName:
    let rmCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, RmToolName, ctx.fs).valueOr:
      return handledError(error)
    let parent = rmCtx.parentDir
    return handledOutcome(runWasmApplet("rm", @[rmCtx], if parent.len > 0: parent else: "/"))
  of MkdirToolName:
    let mkdirCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, MkdirToolName, ctx.fs).valueOr:
      return handledError(error)
    let parent = mkdirCtx.parentDir
    return handledOutcome(runWasmApplet("mkdir", @[mkdirCtx], if parent.len > 0: parent else: "/"))
  else:
    return NativeToolResult(handled: false)

proc executeWebNativeTool(tc: ToolCallRequest;
                          ctx: NativeCtx;
                          state: SessionState;
                          history: ConversationHistory;
                          j: JsonNode;
                         ): Future[NativeToolResult] {.async.} =
  discard state; discard history
  case tc.name
  of FetchToolName:
    let fetchCtx = parseFetchContext(j, FetchDefaultMax).valueOr:
      return handledError(error)
    let rules = toolWebRules(ctx, FetchToolName)
    return webToolResult(await runWeb(WebToolJob(kind: wtkFetch, url: fetchCtx.url,
      maxCh: fetchCtx.maxCh, rules: rules, allowlist: ctx.webAllowlist,
      label: FetchToolName), ctx))
  of WebSearchToolName:
    let searchCtx = parseWebSearchContext(j).valueOr:
      return handledError(error)
    let rules = toolWebRules(ctx, WebSearchToolName)
    return webToolResult(await runWeb(WebToolJob(kind: wtkSearch, query: searchCtx.query,
      count: searchCtx.count, apiKey: ctx.braveApiKey, rules: rules,
      allowlist: ctx.webAllowlist), ctx))
  of GithubToolName:
    ## Off the loop, through the installed runner (app/offloop_io).
    let read = await performGithub(j, githubToken(), offLoopIo())
    if read.isErr: return handledError(read.error)
    return handledText(read.get)
  else:
    return NativeToolResult(handled: false)

proc executeStructuredNativeTool(tc: ToolCallRequest;
                                 ctx: NativeCtx;
                                 state: SessionState;
                                 history: ConversationHistory;
                                 j: JsonNode;
                                ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  case tc.name
  of FsListToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsListToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsList(ctx.fs, 
      pathCtx,
      ctx.paddockDir,
      recursive = j.getOrDefault("recursive").getBool(false),
      pattern = j.getOrDefault("pattern").getStr("*"),
      includeHidden = j.getOrDefault("include_hidden").getBool(false),
    ))
  of FsReadToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsReadToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsRead(ctx.fs, 
      pathCtx,
      ctx.paddockDir,
      j.getOrDefault("format").getStr("text"),
    ))
  of FsWriteToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsWriteToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    if not j.hasKey("content"):
      return handledStructured(usageErrorToolResult("content is required"))
    return handledStructured(performFsWrite(ctx.fs, 
      pathCtx,
      ctx.paddockDir,
      j.getOrDefault("mode").getStr("replace"),
      j["content"],
      j.getOrDefault("format").getStr("text"),
    ))
  of FsMkdirToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsMkdirToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsMkdir(ctx.fs, pathCtx, ctx.paddockDir, j.getOrDefault("parents").getBool(false)))
  of FsCopyToolName:
    let cpCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, FsCopyToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsCopy(ctx.fs, cpCtx.source, cpCtx.dest, ctx.paddockDir, j.getOrDefault("recursive").getBool(false)))
  of FsMoveToolName:
    let mvCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, FsMoveToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsMove(ctx.fs, mvCtx.source, mvCtx.dest, ctx.paddockDir))
  of FsRemoveToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsRemoveToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsRemove(ctx.fs, pathCtx, ctx.paddockDir, j.getOrDefault("recursive").getBool(false)))
  of TextSearchToolName:
    let grepCtx = parseGrepContext(j, ctx.paddockDir, ctx.log, TextSearchToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performGrepStructured(ctx.fs, grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max, ctx.paddockDir))
  of TextReadToolName:
    let readCtx = parseReadFileContext(j, ctx.paddockDir, ctx.log, TextReadToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(readStructuredTextSlice(ctx.fs, readCtx.path, readCtx.startLine, readCtx.maxLines, ctx.paddockDir))
  of TextReplaceToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, TextReplaceToolName, ctx.fs).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    let findText = j.getOrDefault("find").getStr("")
    let replaceText = j.getOrDefault("replace").getStr("")
    let count = j.getOrDefault("count").getInt(0)
    return handledStructured(replaceStructuredText(ctx.fs, pathCtx, findText, replaceText, count, ctx.paddockDir))
  of JsonQueryToolName:
    return handledStructured(runJsonQuery(j))
  of TableQueryToolName:
    return handledStructured(runTableQuery(j))
  of HttpFetchToolName:
    let fetchCtx = parseFetchContext(j, FetchDefaultMax).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    let rules = toolWebRules(ctx, HttpFetchToolName)
    return webToolResult(await runWeb(WebToolJob(kind: wtkFetchStructured,
      url: fetchCtx.url, expect: j.getOrDefault("expect").getStr("text"),
      maxCh: fetchCtx.maxCh, rules: rules, allowlist: ctx.webAllowlist,
      label: HttpFetchToolName), ctx))
  of GitInspectToolName:
    let gitCtx = parseGitInspectContext(j).valueOr:
      return handledError(error)
    let repoDir = parsePathOnly(j, ctx.paddockDir, ctx.log, GitInspectToolName, ctx.fs).valueOr:
      return handledError(error)
    let shown = await performGitInspect(gitCtx, repoDir, offLoopIo())
    if shown.isErr: return handledError(shown.error)
    return handledText(shown.get)
  of ArchiveExtractToolName:
    let archivePath = j.getOrDefault("archive_path").getStr("")
    let destination = j.getOrDefault("destination").getStr("")
    return handledStructured(performArchiveExtract(ctx.process, ctx.fs, archivePath, destination, ctx.paddockDir))
  of ArchiveCreateToolName:
    let archivePath = j.getOrDefault("archive_path").getStr("")
    let inputsNode = j.getOrDefault("inputs")
    if inputsNode.kind != JArray:
      return handledStructured(usageErrorToolResult("inputs must be an array of strings"))
    var inputs: seq[string] = @[]
    for item in inputsNode:
      if item.kind != JString:
        return handledStructured(usageErrorToolResult("inputs must be an array of strings"))
      inputs.add(item.getStr())
    return handledStructured(performArchiveCreate(ctx.process, ctx.fs, archivePath, inputs, ctx.paddockDir))
  else:
    return NativeToolResult(handled: false)

proc executeCodeNativeTool(tc: ToolCallRequest;
                           ctx: NativeCtx;
                           state: SessionState;
                           history: ConversationHistory;
                           j: JsonNode;
                          ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  if tc.name != ExecuteCodeToolName:
    return NativeToolResult(handled: false)
  let cfg = codeConfigFromEnv(ctx.env, ctx.sandboxMode,
                              ctx.sandboxRuntimeCmd).valueOr:
    return handledError(error)
  let req = parseCodeRequest(j, ctx.paddockDir, cfg.maxSourceBytes,
                             cfg.timeoutSec, ctx.fs).valueOr:
    return handledError(error)
  let executed = await runCodeRequestAsync(req, cfg, ctx.paddockDir, ctx.uid,
                                           ctx.channel, ctx.log)
  if executed.isErr:
    return handledError(executed.error)
  handledText(executed.get().text)

proc executeUtilityNativeTool(tc: ToolCallRequest;
                              ctx: NativeCtx;
                              state: SessionState;
                              history: ConversationHistory;
                              j: JsonNode;
                             ): Future[NativeToolResult] {.async.} =
  discard state; discard history
  case tc.name
  of CalcToolName:
    let calcCtx = parseCalcContext(j).valueOr:
      return handledError(error)
    return handledOutcome(performCalc(calcCtx.expression))
  of RenderMermaidToolName:
    let mermaidCtx = parseMermaidContext(j).valueOr:
      return handledError(error)
    return handledOutcome(performRenderMermaid(ctx.process, ctx.fs, mermaidCtx.diagram))
  of InspectImageToolName:
    let inspectCtx = parseInspectImageContext(j, ctx.paddockDir, ctx.log, InspectImageToolName, ctx.fs).valueOr:
      return handledError(error)
    return handledOutcome(performInspectImage(ctx.fs, inspectCtx.path, inspectCtx.prompt, ctx.completeFn))
  of TranscribeAudioToolName:
    let ctxAudio = parseTranscribeContext(j, ctx.paddockDir, ctx.log,
                                          ctx.fs).valueOr:
      return handledError(error)
    let heard = await runSpeech(SpeechJob(kind: sjTranscribe, path: ctxAudio.path,
      language: ctxAudio.language, prompt: ctxAudio.prompt,
      settings: speechSettings(ctx.env)), ctx)
    return handledOutcome(heard.text)
  of TextToSpeechToolName:
    let speechCtx = parseSpeechContext(j).valueOr:
      return handledError(error)
    let speech = speechSettings(ctx.env)
    if speechCtx.asVoice:
      let prepared = await runSpeech(SpeechJob(kind: sjVoiceReply, text: speechCtx.text,
        caption: speechCtx.caption, paddockDir: ctx.paddockDir, channel: ctx.channel,
        uid: ctx.uid, replyTo: ctx.replyTo, settings: speech), ctx)
      if not prepared.ok:
        return handledError(prepared.error)
      return NativeToolResult(
        handled: true,
        text: "Voice reply ready.",
        resultKind: trkOutput,
        outbound: some(prepared.outbound))
    let saved = await runSpeech(SpeechJob(kind: sjSave, text: speechCtx.text,
      paddockDir: ctx.paddockDir, voice: speechCtx.voice, format: speechCtx.format,
      settings: speech), ctx)
    if not saved.ok:
      return handledError(saved.error)
    return handledOutcome("Audio saved: " & saved.saved)
  else:
    return NativeToolResult(handled: false)

proc executeSessionNativeTool(tc: ToolCallRequest;
                              ctx: NativeCtx;
                              state: SessionState;
                              history: ConversationHistory;
                              j: JsonNode;
                             ): Future[NativeToolResult] {.async.} =
  discard history
  case tc.name
  of AskToolName:
    let askCtx = parseAskContext(j).valueOr:
      return handledError(error)
    if ctx.session.isNil:
      return handledError("Error: ask channel unavailable.")
    ctx.session[].awaitingAsk = true
    await ctx.outbox.put(OutboundMessage(
      userId:  ctx.uid,
      channel: ctx.channel,
      text:    askCtx.question,
    ))
    let reply = await ctx.session[].askInbox.get()
    ctx.session[].awaitingAsk = false
    if reply == "__DONKEY_ASK_CANCELLED__":
      return handledError(AskInterruptedText)
    return handledText(reply)
  of TodoWriteToolName:
    let ops = parseTodoOps(j).valueOr:
      return handledError(error)
    return handledOutcome(applyTodoOps(state, ops))
  of CheckpointToolName:
    return buildCheckpointResult(state)
  of RewindToolName:
    let rewindResult =
      parseRewindIndex(j, state.checkpoints.len) >>=
      proc(idx: int): Result[NativeToolResult, string] =
        buildRewindResult(state, idx)
    return rewindResult.valueOr:
      handledError(error)
  of SessionSearchToolName:
    ## The main agent searches its own session too (compaction removed part
    ## of it from the context); a subagent never sees its parent's.
    let searchCtx = parseSessionSearchContext(j).valueOr:
      return handledError(error)
    let found = await searchConversations(ctx.fs, ctx.paddockDir,
      ConversationSearchRequest(
        query: searchCtx.query, phrase: searchCtx.phrase,
        sessionId: searchCtx.sessionId, around: searchCtx.around,
        since: searchCtx.since, until: searchCtx.until, limit: searchCtx.limit,
        offset: searchCtx.offset, context: searchCtx.context,
        countOnly: searchCtx.countOnly, oldestFirst: searchCtx.oldestFirst,
        excludeSessionId: (if ctx.subagentId.len > 0: ctx.scopeSessionId else: "")),
      int64(epochTime() * 1000))
    if found.isErr:
      return handledError("Error: " & found.error)
    var text = found.get()
    ## Ranked terms also look in long-term memory (MEMORY.md or the graph).
    if searchCtx.query.len > 0 and searchCtx.phrase.len == 0 and
       searchCtx.sessionId.len == 0 and searchCtx.includeMemory and
       ctx.memory.searchSessions != nil:
      let memoryHits = ctx.memory.searchSessions(
        ctx.uid, searchCtx.query, SessionSearchDefaultLimit, true)
      if memoryHits.isOk:
        var lines: seq[string]
        for hit in memoryHits.get():
          if hit.kind == shkMemory:
            lines.add("- " & hit.snippet.replace("\n", " "))
        if lines.len > 0:
          text.add("\n\nFrom long-term memory:\n" & lines.join("\n"))
    return handledText(text)
  of MemoryIngestToolName:
    let ingestCtx = parseMemoryIngestContext(j).valueOr:
      return handledError(error)
    let ingestOrigin = MemoryOrigin(source: msIngest,
                                    sessionId: ctx.scopeSessionId)
    let stats =
      if ingestCtx.path.len > 0:
        ingestMemoryFile(ctx.memory, ctx.uid, ctx.paddockDir, ingestCtx.path,
                         ingestCtx.chunkChars, ingestCtx.maxChunks, ctx.fs,
                         ingestOrigin)
      else:
        ingestMemoryText(ctx.memory, ctx.uid, ingestCtx.text, "text",
                         ingestCtx.chunkChars, ingestCtx.maxChunks, ingestOrigin)
    if stats.isErr:
      return handledError("Error: " & stats.error)
    let ingested = stats.get()
    return handledText($(%*{
      "ok": true,
      "chunks": ingested.chunks,
      "bytes": ingested.bytes,
      "truncated": ingested.truncated,
      "source": ingested.source,
    }))
  of ManageSchedulesToolName:
    let schedCtx = parseManageSchedulesContext(j).valueOr:
      return handledError(error)
    let reply = performManageSchedules(ctx.schedules, $ctx.uid, $ctx.channel,
                                       schedCtx, int64(epochTime() * 1000)).valueOr:
      return handledError(error)
    return handledText(reply)
  of SkillManageToolName:
    let skillCtx = parseSkillManage(j).valueOr:
      return handledError(error)
    let reply = performSkillManage(ctx.fs, ctx.paddockDir, skillCtx,
                                   int64(epochTime() * 1000)).valueOr:
      return handledError("Error: " & error)
    return handledText(reply)
  of SkillViewToolName:
    let shown = performSkillView(ctx.fs, ctx.paddockDir, j{"name"}.getStr,
                                 int64(epochTime() * 1000)).valueOr:
      return handledError("Error: " & error)
    return handledText(shown)
  of ManageTasksToolName:
    let tasksCtx = parseManageTasksContext(j).valueOr:
      return handledError(error)
    let reply = performManageTasks(ctx.fs, ctx.paddockDir, tasksCtx,
                                   int64(epochTime() * 1000),
                                   TaskAgenda(schedules: ctx.schedules, userId: $ctx.uid,
                                              channel: $ctx.channel)).valueOr:
      return handledError(error)
    return handledText(reply)
  of ManageAgentsToolName:
    let agentCtx = parseManageAgentsContext(j).valueOr:
      return handledError(error)
    let reply = performManageAgents(ctx.fs, ctx.paddockDir, agentCtx).valueOr:
      return handledError(error)
    return handledText(reply)
  of ManageSkillsToolName:
    let skillCtx = parseManageSkillsContext(j).valueOr:
      return handledError(error)
    let reply = performManageSkills(
      ctx.fs, ctx.memory, ctx.uid, buildManageSkillsValue(skillCtx),
      registry = (if skillCtx.registry.len > 0: skillCtx.registry
                  else: skillRegistry(ctx.env)),
    ).valueOr:
      return handledError(error)
    return handledText(reply)
  else:
    return NativeToolResult(handled: false)

func consultedAgentCtx*(ctx: NativeCtx; agentName: string): NativeCtx =
  ## The context a consulted agent's tools run in: only the read-only tools
  ## of `ConsultedAgentToolNames`, on top of the subagent hard denials, so it
  ## can never call another agent, write or run code. The web tools keep the
  ## user's web policy (`toolWebPolicy`, the allowlist), checked as they run.
  result = ctx
  result.restrictTools = true
  result.allowedTools = @ConsultedAgentToolNames
  result.subagentId = "@" & agentName

proc executeNativeTool*(tc:      ToolCallRequest;
                        ctx:     NativeCtx;
                        state:   SessionState;
                        history: ConversationHistory;
                       ): Future[NativeToolResult] {.async.}
  ## Forward: a consulted agent's tools run through it, and it dispatches the
  ## agent tools.

proc consultTools(ctx: NativeCtx; state: SessionState; history: ConversationHistory;
                  agentName: string): ConsultTools =
  ## `history` is the calling turn's: session_search also reads what was
  ## compacted out of the current session.
  let consulted = consultedAgentCtx(ctx, agentName)
  ConsultTools(
    tools: consultedAgentToolDescriptions(webSearch = webSearchKey().len > 0),
    run: proc(call: ToolCallRequest): Future[ConsultToolResult] {.async.} =
      let done = await executeNativeTool(call, consulted, state, history)
      if not done.handled:
        return ConsultToolResult(text: "Error: tool '" & call.name & "' is not available.",
                                 kind: trkOperationalError)
      return ConsultToolResult(text: done.text, kind: done.resultKind))

proc agentCompleteFn(ctx: NativeCtx): AsyncCompleteFn =
  ## The async completion (the provider call runs on a worker, not on the
  ## loop); the sync one wrapped when a context has no async one.
  if ctx.asyncCompleteFn != nil: return ctx.asyncCompleteFn
  if ctx.completeFn == nil: return nil
  let syncFn = ctx.completeFn
  result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
    ## (Not named `complete`: the async macro's own `complete` would be shadowed.)
    let resp = syncFn(req)
    return resp

proc executeAgentNativeTool(tc: ToolCallRequest;
                            ctx: NativeCtx;
                            state: SessionState;
                            history: ConversationHistory;
                            j: JsonNode;
                           ): Future[NativeToolResult] {.async.} =
  case tc.name
  of AskAgentToolName:
    let askCtx = parseAskAgentContext(j).valueOr:
      return handledError(error)
    let answer = await askNamedAgent(ctx.fs, ctx.paddockDir, agentCompleteFn(ctx),
                                     askCtx.name, askCtx.question, askCtx.context,
                                     consult = consultTools(ctx, state, history, askCtx.name))
    if answer.isErr:
      return handledError(answer.error)
    return handledText(answer.get)
  of ConveneAgentsToolName:
    let roomCtx = parseConveneAgentsContext(j).valueOr:
      return handledError(error)
    let transcript = await conveneNamedAgents(ctx.fs, ctx.paddockDir, agentCompleteFn(ctx),
      roomCtx.agents, roomCtx.question, roomCtx.context, roomCtx.rounds,
      consult = consultTools(ctx, state, history, "room"))
    if transcript.isErr:
      return handledError(transcript.error)
    return handledText(transcript.get)
  of TaskToolName:
    let taskCtx = parseTaskContext(j).valueOr:
      return handledError(error)
    discard history
    let jobId = spawnTaskJob(state, taskCtx.prompt, taskCtx.context, ctx.completeFn)
    return handledText(buildTaskStartedText(jobId))
  of SubmitResultToolName:
    return buildSubmitResult(j)
  of ReportFindingToolName:
    let findingCtx = parseFindingContext(j).valueOr:
      return handledError(error)
    return recordFinding(ctx, findingCtx)
  of CancelJobToolName:
    return cancelJob(state, j.getOrDefault("job_id").getStr(""))
  of AwaitToolName:
    let awaitCtx = parseAwaitContext(j).valueOr:
      return handledError(error)
    return await awaitJobs(state, awaitCtx)
  of SpawnSubagentToolName:
    if sessionStopRequested(ctx):
      return handledError("Error: session is stopping.")
    if ctx.subagentDepth >= 1:
      return handledError("Error: subagents cannot spawn subagents (maximum depth is 1).")
    if ctx.spawnSubagent == nil:
      return handledError("Error: subagent runtime is unavailable.")
    let spawnCtx = parseSpawnSubagentContext(j).valueOr:
      return handledError(error)
    let spawned = await ctx.spawnSubagent(spawnCtx.request)
    if spawned.error.len > 0:
      return handledError("Error: " & spawned.error)
    if spawnCtx.wait:
      if ctx.awaitSubagent == nil:
        return handledError("Error: subagent runtime cannot await results.")
      let subagentResult = await ctx.awaitSubagent(
        spawned.subagentId, ctx.stopGeneration, $ctx.uid, ctx.userInterrupt)
      return handledSubagentResult(subagentResult)
    return handledText($spawned.toJson())
  of AwaitSubagentToolName:
    if ctx.awaitSubagent == nil:
      return handledError("Error: subagent runtime is unavailable.")
    let awaitCtx = parseAwaitSubagentContext(j).valueOr:
      return handledError(error)
    let subagentResult = await ctx.awaitSubagent(
      awaitCtx.subagentId, ctx.stopGeneration, $ctx.uid, ctx.userInterrupt)
    return handledSubagentResult(subagentResult)
  of ListSubagentsToolName:
    if ctx.listSubagents == nil:
      return handledError("Error: subagent runtime is unavailable.")
    var arr = newJArray()
    let nowMs = epochMs()
    for info in ctx.listSubagents():
      arr.add(info.toJson(nowMs))
    return handledText($(%*{"subagents": arr}))
  of CancelSubagentToolName:
    if ctx.cancelSubagent == nil:
      return handledError("Error: subagent runtime is unavailable.")
    let cancelCtx = parseAwaitSubagentContext(j).valueOr:
      return handledError(error)
    let cancelled = await ctx.cancelSubagent(cancelCtx.subagentId)
    return handledText($(%*{
      "subagent_id": cancelCtx.subagentId,
      "cancelled": cancelled,
    }))
  else:
    return NativeToolResult(handled: false)

func categoryHandler(kind: NativeToolCategoryKind): NativeToolCategoryHandler =
  case kind
  of ntckLegacy: executeLegacyNativeTool
  of ntckShell: executeShellNativeTool
  of ntckStructured: executeStructuredNativeTool
  of ntckCode: executeCodeNativeTool
  of ntckWeb: executeWebNativeTool
  of ntckUtility: executeUtilityNativeTool
  of ntckSession: executeSessionNativeTool
  of ntckAgent: executeAgentNativeTool

proc executeNativeCategory(tc: ToolCallRequest;
                           ctx: NativeCtx;
                           state: SessionState;
                           history: ConversationHistory;
                           j: JsonNode;
                           category: NativeToolCategoryKind;
                          ): Future[NativeToolResult] {.async.} =
  let handler = categoryHandler(category)
  let categoryResult = await handler(tc, ctx, state, history, j)
  if categoryResult.handled:
    if categoryResult.outbound.isSome and not ctx.outbox.isNil:
      await ctx.outbox.put(categoryResult.outbound.get())
    return categoryResult
  NativeToolResult(handled: false)

func escapedApprovalPreview(text: string; maxChars: int): string =
  clipUtf8(text, maxChars)
    .replace("\r\n", "\\n")
    .replace("\n", "\\n")
    .replace("\r", "\\r")

func effectiveWriteContent(j: JsonNode): tuple[content: string, format: string] =
  let format = j.getOrDefault("format").getStr("text")
  let node = if j.hasKey("content"): j["content"] else: newJNull()
  let rendered = contentToString(node, format)
  ((if rendered.ok: rendered.text else: $node), format)

func structuredWriteSummary(j: JsonNode): string =
  let path = j.getOrDefault("path").getStr("")
  let mode = j.getOrDefault("mode").getStr("replace")
  let effective = effectiveWriteContent(j)
  let digest = ($secureHash(effective.content)).toLowerAscii()
  "path=" & path & " mode=" & mode & " format=" & effective.format &
    " bytes=" & $effective.content.len & " sha1=" & digest &
    "\npreview:\n" & escapedApprovalPreview(effective.content, 800)

func structuredReplaceSummary(j: JsonNode): string =
  let path = j.getOrDefault("path").getStr("")
  let find = j.getOrDefault("find").getStr("")
  let replace = j.getOrDefault("replace").getStr("")
  let digest = ($secureHash(find & "\0" & replace)).toLowerAscii()
  "path=" & path & " find_bytes=" & $find.len & " replace_bytes=" & $replace.len &
    " sha1=" & digest & "\npreview:\n" & escapedApprovalPreview(replace, 800)

func largeWritesSummaryMode(env: Environment): bool =
  env.stripped("DONKEY_APPROVAL_LARGE_WRITES").toLowerAscii() == "summary"

func approvalSummary(env: Environment; toolName: string; j: JsonNode): string =
  ## The approval must reflect the complete action. Oversized requests are
  ## rejected instead of showing a truncated command/edit. A file-write
  ## summary is available as an explicit opt-in for large fs_write/text_replace
  ## payloads; bash/execute_code remain full-display-only.
  const MaxApprovalSummaryChars = 1500
  if largeWritesSummaryMode(env):
    let serializedLen = ($j).len
    if toolName == FsWriteToolName and serializedLen > MaxApprovalSummaryChars:
      return structuredWriteSummary(j)
    if toolName == TextReplaceToolName and serializedLen > MaxApprovalSummaryChars:
      return structuredReplaceSummary(j)
  if toolName == ExecuteCodeToolName:
    let languageNode = j.getOrDefault("language")
    let language =
      if languageNode != nil and languageNode.kind == JString:
        languageNode.getStr("")
      else:
        ""
    let timeoutNode = j.getOrDefault("timeout_sec")
    let timeoutSec =
      if timeoutNode != nil and timeoutNode.kind == JInt:
        clampCodeTimeoutSec(timeoutNode.getInt())
      else:
        parseCodeTimeoutSec(env.get("DONKEY_CODE_TIMEOUT_SEC"))
    result = "language=" & language & " timeout=" & $timeoutSec & "s\n"
    let languageOpt = parseCodeLanguage(language)
    let isWasm = languageOpt.isSome and languageOpt.get() == clWasm
    let codeNode = j.getOrDefault("code")
    let code =
      if codeNode != nil and codeNode.kind == JString: codeNode.getStr("")
      else: ""
    if isWasm or code.len == 0:
      let pathNode = j.getOrDefault("wasm_path")
      result.add("wasm_path=" &
        (if pathNode != nil and pathNode.kind == JString: pathNode.getStr("")
         else: ""))
    else:
      result.add(code)
  elif toolName == BashToolName:
    result = j.getOrDefault("command").getStr("")
    if result.len == 0:
      result = $j
  else:
    result = $j
  result = result.replace("\r\n", "\\n")
                 .replace("\n", "\\n")
                 .replace("\r", "\\r")
                 .strip
  if result.len == 0:
    result = "(sem detalhes)"
  if result.len > MaxApprovalSummaryChars:
    result = ""

proc executeNativeTool*(tc:      ToolCallRequest;
                        ctx:     NativeCtx;
                        state:   SessionState;
                        history: ConversationHistory;
                       ): Future[NativeToolResult] {.async.} =
  var ctx = ctx
  ctx.fs = ctx.fs.orUnavailable  ## a context built without a file system fails, not crashes
  ctx.process = ctx.process.orUnavailable
  ctx.attachments = ctx.attachments.orUnavailable
  let j = try: parseJson(tc.inputJson)
          except CatchableError: newJObject()
  if sessionStopRequested(ctx):
    return NativeToolResult(
      handled: true,
      text: "Error: session is stopping.",
      resultKind: trkOperationalError)
  if ctx.restrictTools and
     (tc.name notin ctx.allowedTools or tc.name in SubagentHardDeniedTools):
    return NativeToolResult(
      handled: true,
      text: "Error: tool '" & tc.name & "' is not allowed for subagent '" &
            (if ctx.subagentId.len > 0: ctx.subagentId else: "?") & "'.",
      resultKind: trkOperationalError)
  if ctx.budget != nil:
    let budgetDecision = checkBudget(ctx.budget, ctx.budgetLimits, nowMs())
    if budgetDecision != bdOk:
      ctx.budget.budgetError = budgetDecisionText(budgetDecision)
      return NativeToolResult(
        handled: true,
        text: "Error: " & ctx.budget.budgetError & ".",
        resultKind: trkOperationalError)
    ctx.budget.recordToolCall(epochMs())
  let categories = classifyNativeTool(tc.name)
  if categories.len > 0 and requiresApproval(ctx.approval, tc.name):
    var summary = approvalSummary(ctx.env, tc.name, j)
    if summary.len > 0 and ctx.subagentId.len > 0:
      summary = "[subagent " & ctx.subagentId & "] " & summary
    if summary.len == 0:
      return NativeToolResult(
        handled: true,
        text: "Error: tool '" & tc.name &
              "' is too large to display for approval; split the action.",
        resultKind: trkOperationalError)
    let decision = await requestAndWait(
      ctx.approval, ctx.uid, ctx.channel, ctx.outbox, tc.name,
      summary, ctx.log,
      shouldStop = proc(): bool {.gcsafe, raises: [].} = sessionStopRequested(ctx))
    case decision
    of adApproved:
      discard
    of adDenied:
      return NativeToolResult(
        handled: true,
        text: "Error: tool '" & tc.name & "' was denied by the user.",
        resultKind: trkOperationalError)
    of adTimeout:
      return NativeToolResult(
        handled: true,
        text: "Error: approval for tool '" & tc.name & "' timed out.",
        resultKind: trkOperationalError)
  for category in categories:
    let categoryResult = await executeNativeCategory(tc, ctx, state, history, j, category)
    if categoryResult.handled:
      return categoryResult
  return NativeToolResult(handled: false)
