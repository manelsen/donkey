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
import ./tools/task_tools

export fs_tools        # resolveInPaddock, inPaddock, performBash
export text_tools      # HashlineAnchor, EditFileOpKind, EditFileOp, hashline
                       # helpers, stripHtml, applyTodoOps
export search_tools    # performFind, performFindWasm, performGrep, performGrepWasm
export web_tools       # FetchHardMax, FetchDefaultMax, performFetch, performWebSearch
export archive_tools   # performArchiveCreate, performArchiveExtract
export data_tools      # runJsonQuery, runTableQuery
export utility_tools   # performCalc, performRenderMermaid, performInspectImage,
                       # MermaidTempPrefix
export task_tools      # performTask, nextJobId, buildTaskStartedText,
                       # spawnTaskJob, performManageSkills

# ── Dispatcher-only imports ──────────────────────────────────────────────────

import std/[json, options, tables, sequtils, strutils, times, os]
import chronos
import chronos/asyncsync
import ../core/tooling/native_tool_dispatch
import ../core/pipeops
import ../core/log
import ../domain/message
import ../domain/more_tools
import ../domain/builtin_tools
import ../domain/reminder
import ../ports/http as httpPort
import ../ports/provider
import ../ports/memory
import ../config/types as cfgTypes
import ../infra/sandbox/wasm_tools
import ./sandbox
import ./session_state
import ./session_manager

# ── Result type ───────────────────────────────────────────────────────────────

type
  NativeToolResult* = object
    handled*:       bool
    text*:          string
    resultKind*:    ToolResultKind
    newHistory*:    Option[ConversationHistory]
    checkpointNow*: bool

# ── Context types (parsing only — execution delegated to tool modules) ────────

type
  NativeCtx* = object
    uid*:          UserId
    channel*:      ChannelKind
    outbox*:       AsyncQueue[OutboundMessage]
    session*:      ptr SessionEntry
    memory*:       MemoryRuntimePort
    completeFn*:   CompleteFn
    http*:         httpPort.HttpRuntimePort
    braveApiKey*:  string
    webAllowlist*: seq[string]
    toolWebPolicy*: seq[cfgTypes.ToolWebPolicy]
    tools*:        seq[ToolDescription]
    log*:          Logger
    paddockDir*:   string
    sandboxMode*:  SandboxMode
    sandboxRuntimeCmd*: string
    sandboxImage*: string
    sandboxAllowHostFallback*: bool
    sandboxAllowNetwork*: bool
    sandboxReadOnlyRootfs*: bool

  AskContext* = object
    question*: string

  BashContext* = object
    command*: string

  ReadFileContext* = object
    path*:      string
    startLine*: int
    maxLines*:  int

  FindContext* = object
    path*:    string
    pattern*: string
    kind*:    string
    max*:     int

  GrepContext* = object
    pattern*:   string
    path*:      string
    recursive*: bool
    max*:       int

  SedContext* = object
    expression*: string
    path*:       string

  WcContext* = object
    path*:  string
    flags*: string

  HeadTailContext* = object
    path*:  string
    lines*: int

  SortContext* = object
    path*:  string
    flags*: string

  CpMvContext* = object
    source*: string
    dest*:   string

  FetchContext* = object
    url*:    string
    maxCh*:  int

  WebSearchContext* = object
    query*: string
    count*: int

  CalcContext* = object
    expression*: string

  MermaidContext* = object
    diagram*: string

  InspectImageContext* = object
    path*:   string
    prompt*: string

  TaskContext* = object
    prompt*:  string
    context*: string

  AwaitContext* = object
    ids*: seq[string]

  FindingContext* = object
    finding*: string

  ManageSkillsContext* = object
    action*:   string
    query*:    string
    slug*:     string
    name*:     string
    registry*: string

  EditFileContext* = object
    path*:  string
    edits*: seq[EditFileOp]

  NativeToolCategoryHandler = proc(tc: ToolCallRequest;
                                   ctx: NativeCtx;
                                   state: SessionState;
                                   history: ConversationHistory;
                                   j: JsonNode;
                                  ): Future[NativeToolResult] {.nimcall, gcsafe, raises: [].}

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
                      toolName = ""): Result[string, string] {.gcsafe, raises: [].} =
  if path.len == 0 or paddockDir.len == 0:
    if path.len > 0 and paddockDir.len == 0:
      logToolPathFailure(log, toolName, path, paddockDir, path, "empty_paddock")
    return ok(path)
  let resolvedPath = resolveInPaddock(path, paddockDir)
  if not inPaddock(resolvedPath, paddockDir):
    logToolPathFailure(log, toolName, path, paddockDir, resolvedPath, "outside_paddock")
    return err("Error: path outside paddock: " & path)
  ok(resolvedPath)

proc requireStringField(j: JsonNode; key: string): Result[string, string] {.gcsafe, raises: [].} =
  let value = j.getOrDefault(key).getStr("")
  if value.len == 0:
    return err("Error: '" & key & "' is required.")
  ok(value)

proc parseAskContext*(j: JsonNode): Result[AskContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("question") >>=
    proc(question: string): Result[AskContext, string] =
      ok(AskContext(question: question))

proc parseBashContext*(j: JsonNode): Result[BashContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("command") >>=
    proc(command: string): Result[BashContext, string] =
      ok(BashContext(command: command))

proc parseReadFileContext*(j: JsonNode;
                           paddockDir: string;
                           log: Logger = Logger();
                           toolName = ReadFileToolName): Result[ReadFileContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(p: string): Result[ReadFileContext, string] =
      resolvedToolPath(p, paddockDir, log, toolName) >>=
        proc(rp: string): Result[ReadFileContext, string] =
          ok(ReadFileContext(
            path: rp,
            startLine: max(1, j.getOrDefault("start_line").getInt(1)),
            maxLines: max(1, j.getOrDefault("max_lines").getInt(200)),
          ))

proc parseFindContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger();
                       toolName = FindToolName): Result[FindContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(p: string): Result[FindContext, string] =
      resolvedToolPath(p, paddockDir, log, toolName) >>=
        proc(rp: string): Result[FindContext, string] =
          ok(FindContext(
            path: rp,
            pattern: j.getOrDefault("pattern").getStr("*"),
            kind: j.getOrDefault("type").getStr("file"),
            max: j.getOrDefault("max").getInt(50),
          ))

proc parseGrepContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger();
                       toolName = GrepToolName): Result[GrepContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("pattern") >>=
    proc(pat: string): Result[GrepContext, string] =
      j.requireStringField("path") >>=
        proc(p: string): Result[GrepContext, string] =
          resolvedToolPath(p, paddockDir, log, toolName) >>=
            proc(rp: string): Result[GrepContext, string] =
              ok(GrepContext(
                pattern: pat,
                path: rp,
                recursive: j.getOrDefault("recursive").getBool(true),
                max: j.getOrDefault("max").getInt(50),
              ))

proc parseSedContext*(j: JsonNode; paddockDir: string;
                      log: Logger = Logger();
                      toolName = SedToolName): Result[SedContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("expression") >>=
    proc(expr: string): Result[SedContext, string] =
      j.requireStringField("path") >>=
        proc(p: string): Result[SedContext, string] =
          resolvedToolPath(p, paddockDir, log, toolName) >>=
            proc(rp: string): Result[SedContext, string] =
              ok(SedContext(expression: expr, path: rp))

proc parsePathOnly*(j: JsonNode; paddockDir: string;
                    log: Logger = Logger();
                    toolName = ""): Result[string, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(p: string): Result[string, string] = resolvedToolPath(p, paddockDir, log, toolName)

proc parseWcContext*(j: JsonNode; paddockDir: string;
                     log: Logger = Logger();
                     toolName = WcToolName): Result[WcContext, string] {.gcsafe, raises: [].} =
  parsePathOnly(j, paddockDir, log, toolName) >>=
    proc(p: string): Result[WcContext, string] =
      ok(WcContext(path: p, flags: j.getOrDefault("flags").getStr("")))

proc parseHeadTailContext*(j: JsonNode; paddockDir: string;
                           log: Logger = Logger();
                           toolName = ""): Result[HeadTailContext, string] {.gcsafe, raises: [].} =
  parsePathOnly(j, paddockDir, log, toolName) >>=
    proc(p: string): Result[HeadTailContext, string] =
      ok(HeadTailContext(path: p, lines: j.getOrDefault("lines").getInt(10)))

proc parseSortContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger();
                       toolName = SortToolName): Result[SortContext, string] {.gcsafe, raises: [].} =
  parsePathOnly(j, paddockDir, log, toolName) >>=
    proc(p: string): Result[SortContext, string] =
      ok(SortContext(path: p, flags: j.getOrDefault("flags").getStr("")))

proc parseCpMvContext*(j: JsonNode; paddockDir: string;
                       log: Logger = Logger();
                       toolName = ""): Result[CpMvContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("source") >>=
    proc(s: string): Result[CpMvContext, string] =
      j.requireStringField("dest") >>=
        proc(d: string): Result[CpMvContext, string] =
          let rs = resolvedToolPath(s, paddockDir, log, toolName)
          if rs.isErr: return err(rs.error)
          let rd = resolvedToolPath(d, paddockDir, log, toolName)
          if rd.isErr: return err(rd.error)
          ok(CpMvContext(source: rs.value, dest: rd.value))

proc parseFetchContext*(j: JsonNode; defaultMax: int): Result[FetchContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("url") >>=
    proc(u: string): Result[FetchContext, string] =
      ok(FetchContext(url: u, maxCh: j.getOrDefault("max_chars").getInt(defaultMax)))

proc parseWebSearchContext*(j: JsonNode): Result[WebSearchContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("query") >>=
    proc(q: string): Result[WebSearchContext, string] =
      ok(WebSearchContext(query: q, count: j.getOrDefault("count").getInt(5)))

proc parseCalcContext*(j: JsonNode): Result[CalcContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("expression") >>=
    proc(e: string): Result[CalcContext, string] =
      ok(CalcContext(expression: e))

proc parseMermaidContext*(j: JsonNode): Result[MermaidContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("diagram") >>=
    proc(d: string): Result[MermaidContext, string] =
      ok(MermaidContext(diagram: d))

proc parseInspectImageContext*(j: JsonNode): Result[InspectImageContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(p: string): Result[InspectImageContext, string] =
      ok(InspectImageContext(path: p, prompt: j.getOrDefault("prompt").getStr("")))

proc parseTaskContext*(j: JsonNode): Result[TaskContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("prompt") >>=
    proc(p: string): Result[TaskContext, string] =
      ok(TaskContext(prompt: p, context: j.getOrDefault("context").getStr("")))

proc parseAwaitContext*(j: JsonNode): Result[AwaitContext, string] {.gcsafe, raises: [].} =
  let ids = j.getOrDefault("job_ids")
  if ids.kind != JArray:
    return err("Error: 'job_ids' must be an array.")
  ok(AwaitContext(ids: ids.mapIt(it.getStr())))

proc parseFindingContext*(j: JsonNode): Result[FindingContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("finding") >>=
    proc(f: string): Result[FindingContext, string] =
      ok(FindingContext(finding: f))

proc parseManageSkillsContext*(j: JsonNode): Result[ManageSkillsContext, string] {.gcsafe, raises: [].} =
  let action = j.getOrDefault("action").getStr("help").strip.toLowerAscii()
  case action
  of "", "help", "list":
    ok(ManageSkillsContext(action: if action.len == 0: "help" else: action))
  of "search":
    j.requireStringField("query") >>=
      proc(q: string): Result[ManageSkillsContext, string] =
        ok(ManageSkillsContext(action: action, query: q,
                               registry: j.getOrDefault("registry").getStr("")))
  of "install", "enable":
    j.requireStringField("slug") >>=
      proc(s: string): Result[ManageSkillsContext, string] =
        ok(ManageSkillsContext(action: action, slug: s,
                               registry: j.getOrDefault("registry").getStr("")))
  of "disable", "remove":
    j.requireStringField("name") >>=
      proc(n: string): Result[ManageSkillsContext, string] =
        ok(ManageSkillsContext(action: "disable", name: n,
                               registry: j.getOrDefault("registry").getStr("")))
  of "read":
    j.requireStringField("slug") >>=
      proc(s: string): Result[ManageSkillsContext, string] =
        ok(ManageSkillsContext(action: action, slug: s,
                               registry: j.getOrDefault("registry").getStr("")))
  else:
    err("Error: unsupported manage_skills action '" & action & "'.")

func buildManageSkillsValue(ctx: ManageSkillsContext): string =
  case ctx.action
  of "help", "list": ctx.action
  of "search": "search " & ctx.query
  of "install", "enable": ctx.action & " " & ctx.slug
  of "disable": "disable " & ctx.name
  of "read": "read " & ctx.slug
  else: ctx.action

proc parseTodoOps*(j: JsonNode): Result[JsonNode, string] {.gcsafe, raises: [].} =
  let ops = j.getOrDefault("ops")
  if ops.kind != JArray:
    return err("Error: 'ops' must be an array.")
  ok(ops)

proc parseEditFileContext*(j: JsonNode;
                           paddockDir: string;
                           log: Logger = Logger();
                           toolName = EditFileToolName): Result[EditFileContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(p: string): Result[EditFileContext, string] =
      resolvedToolPath(p, paddockDir, log, toolName) >>=
        proc(rp: string): Result[EditFileContext, string] =
          let editsNode = j.getOrDefault("edits")
          if editsNode.kind != JArray:
            return err("Error: 'edits' must be an array.")
          var edits: seq[EditFileOp] = @[]
          for item in editsNode:
            let opKind = case item.getOrDefault("op").getStr("")
              of "replace": efokReplace
              of "append": efokAppend
              of "prepend": efokPrepend
              else: return err("Error: unsupported edit op '" & item.getOrDefault("op").getStr("") & "'.")
            var pos = none(HashlineAnchor)
            var stop = none(HashlineAnchor)
            let posRaw =
              block:
                let primary = item.getOrDefault("pos").getStr("")
                if primary.len > 0: primary
                else:
                  let alias = item.getOrDefault("anchor").getStr("")
                  if alias.len > 0: alias
                  else: item.getOrDefault("start").getStr("")
            if posRaw.len > 0:
              let pa = parseHashlineAnchor(posRaw)
              if pa.isErr: return err(pa.error)
              pos = some(pa.value)
            let stopRaw =
              block:
                let primary = item.getOrDefault("end").getStr("")
                if primary.len > 0: primary
                else:
                  let alias = item.getOrDefault("stop").getStr("")
                  if alias.len > 0: alias
                  else: item.getOrDefault("to").getStr("")
            if stopRaw.len > 0:
              let sa = parseHashlineAnchor(stopRaw)
              if sa.isErr: return err(sa.error)
              stop = some(sa.value)
            if opKind == efokReplace and pos.isNone:
              return err("Error: replace edits require 'pos'.")
            var lines: seq[string] = @[]
            let linesNode = item.getOrDefault("lines")
            if linesNode.kind == JArray:
              for li in linesNode:
                if li.kind == JString: lines.add(li.getStr())
                else: return err("Error: 'lines' must be an array of strings.")
            edits.add(EditFileOp(kind: opKind, pos: pos, stop: stop, lines: lines))
          ok(EditFileContext(path: rp, edits: edits))

# ── Result helpers ────────────────────────────────────────────────────────────

proc handledText(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOutput)

proc handledError(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOperationalError)

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

proc buildCheckpointResult*(state: SessionState): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(
    handled: true,
    text: "Checkpoint " & $state.checkpoints.len & " saved.",
    resultKind: trkOutput,
    checkpointNow: true,
  )

proc buildSubmitResult*(j: JsonNode): NativeToolResult {.gcsafe, raises: [].} =
  handledText(j.getOrDefault("result").getStr(""))

proc parseRewindIndex*(j: JsonNode; checkpointCount: int): Result[int, string] {.gcsafe, raises: [].} =
  if checkpointCount == 0:
    return err("Error: no checkpoints saved.")
  let idx = j.getOrDefault("index").getInt(checkpointCount - 1)
  if idx < 0 or idx >= checkpointCount:
    return err("Error: checkpoint index " & $idx & " out of range (0.." &
               $(checkpointCount - 1) & ").")
  ok(idx)

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
    let ts = reminder.parseWhen(whenStr, getTime().toUnix())
    try:
      discard ctx.memory.scheduleReminder(ctx.uid, $ctx.channel, ts, remMsg)
    except Exception as e:
      return handledError("Error: " & e.msg)
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
    let fetched = performFetch(ctx.http, url, maxCh, rules, ctx.webAllowlist, WebFetchToolName)
    return handledOutcome(fetched)
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
    return handledOutcome(sandboxBash(bashCtx.command, ctx.paddockDir,
                        ctx.sandboxMode, ctx.sandboxImage, ctx.sandboxRuntimeCmd,
                        ctx.sandboxAllowHostFallback, ctx.sandboxAllowNetwork,
                        ctx.sandboxReadOnlyRootfs))
  of ReadFileToolName:
    let readCtx = parseReadFileContext(j, ctx.paddockDir, ctx.log, ReadFileToolName).valueOr:
      return handledError(error)
    try:
      return handledText(renderHashlineSlice(readFile(readCtx.path), readCtx.startLine, readCtx.maxLines))
    except CatchableError as e:
      return handledError("Error: " & e.msg)
  of EditFileToolName:
    let editCtx = parseEditFileContext(j, ctx.paddockDir, ctx.log, EditFileToolName).valueOr:
      return handledError(error)
    try:
      let original = readFile(editCtx.path)
      let applyResult = applyEditFileOps(splitEditableLines(original), editCtx.edits).valueOr:
        return handledError(error)
      let updated = applyResult.join("\n")
      writeFile(editCtx.path, updated)
      return handledText(renderHashlineSlice(updated, 1, updated.splitLines().len))
    except CatchableError as e:
      return handledError("Error: " & e.msg)
  of FindToolName:
    let findCtx = parseFindContext(j, ctx.paddockDir, ctx.log, FindToolName).valueOr:
      return handledError(error)
    let r = if ctx.sandboxMode == smWasm:
      performFindWasm(findCtx.path, findCtx.pattern, findCtx.kind, findCtx.max)
    else:
      performFind(findCtx.path, findCtx.pattern, findCtx.kind, findCtx.max)
    return handledOutcome(r)
  of GrepToolName:
    let grepCtx = parseGrepContext(j, ctx.paddockDir, ctx.log, GrepToolName).valueOr:
      return handledError(error)
    let r = if ctx.sandboxMode == smWasm:
      performGrepWasm(grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max)
    else:
      performGrep(grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max)
    return handledOutcome(r)
  of SedToolName:
    let sedCtx = parseSedContext(j, ctx.paddockDir, ctx.log, SedToolName).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("sed", @[sedCtx.expression, sedCtx.path],
      if sedCtx.path.parentDir.len > 0: sedCtx.path.parentDir else: "/"))
  of WcToolName:
    let wcCtx = parseWcContext(j, ctx.paddockDir, ctx.log, WcToolName).valueOr:
      return handledError(error)
    var args: seq[string] = @[]
    if wcCtx.flags.len > 0:
      args.add(wcCtx.flags)
    args.add(wcCtx.path)
    return handledOutcome(runWasmApplet("wc", args, wcCtx.path))
  of HeadToolName:
    let headCtx = parseHeadTailContext(j, ctx.paddockDir, ctx.log, HeadToolName).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("head", @["-n", $headCtx.lines, headCtx.path], headCtx.path))
  of TailToolName:
    let tailCtx = parseHeadTailContext(j, ctx.paddockDir, ctx.log, TailToolName).valueOr:
      return handledError(error)
    return handledOutcome(runWasmApplet("tail", @["-n", $tailCtx.lines, tailCtx.path], tailCtx.path))
  of SortToolName:
    let sortCtx = parseSortContext(j, ctx.paddockDir, ctx.log, SortToolName).valueOr:
      return handledError(error)
    var args: seq[string] = @[]
    if sortCtx.flags.len > 0:
      args.add(sortCtx.flags)
    args.add(sortCtx.path)
    return handledOutcome(runWasmApplet("sort", args, sortCtx.path))
  of CpToolName:
    let cpCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, CpToolName).valueOr:
      return handledError(error)
    let parent = cpCtx.source.parentDir
    return handledOutcome(runWasmApplet("cp", @[cpCtx.source, cpCtx.dest],
      if parent.len > 0: parent else: "/"))
  of MvToolName:
    let mvCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, MvToolName).valueOr:
      return handledError(error)
    let parent = mvCtx.source.parentDir
    return handledOutcome(runWasmApplet("mv", @[mvCtx.source, mvCtx.dest],
      if parent.len > 0: parent else: "/"))
  of RmToolName:
    let rmCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, RmToolName).valueOr:
      return handledError(error)
    let parent = rmCtx.parentDir
    return handledOutcome(runWasmApplet("rm", @[rmCtx], if parent.len > 0: parent else: "/"))
  of MkdirToolName:
    let mkdirCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, MkdirToolName).valueOr:
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
    return handledOutcome(performFetch(ctx.http, fetchCtx.url, fetchCtx.maxCh, rules, ctx.webAllowlist, FetchToolName))
  of WebSearchToolName:
    let searchCtx = parseWebSearchContext(j).valueOr:
      return handledError(error)
    let rules = toolWebRules(ctx, WebSearchToolName)
    return handledOutcome(performWebSearch(searchCtx.query, searchCtx.count, ctx.braveApiKey, ctx.http, rules, ctx.webAllowlist))
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
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsListToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsList(
      pathCtx,
      ctx.paddockDir,
      recursive = j.getOrDefault("recursive").getBool(false),
      pattern = j.getOrDefault("pattern").getStr("*"),
      includeHidden = j.getOrDefault("include_hidden").getBool(false),
    ))
  of FsReadToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsReadToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsRead(
      pathCtx,
      ctx.paddockDir,
      j.getOrDefault("format").getStr("text"),
    ))
  of FsWriteToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsWriteToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    if not j.hasKey("content"):
      return handledStructured(usageErrorToolResult("content is required"))
    return handledStructured(performFsWrite(
      pathCtx,
      ctx.paddockDir,
      j.getOrDefault("mode").getStr("replace"),
      j["content"],
      j.getOrDefault("format").getStr("text"),
    ))
  of FsMkdirToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsMkdirToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsMkdir(pathCtx, ctx.paddockDir, j.getOrDefault("parents").getBool(false)))
  of FsCopyToolName:
    let cpCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, FsCopyToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsCopy(cpCtx.source, cpCtx.dest, ctx.paddockDir, j.getOrDefault("recursive").getBool(false)))
  of FsMoveToolName:
    let mvCtx = parseCpMvContext(j, ctx.paddockDir, ctx.log, FsMoveToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsMove(mvCtx.source, mvCtx.dest, ctx.paddockDir))
  of FsRemoveToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, FsRemoveToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performFsRemove(pathCtx, ctx.paddockDir, j.getOrDefault("recursive").getBool(false)))
  of TextSearchToolName:
    let grepCtx = parseGrepContext(j, ctx.paddockDir, ctx.log, TextSearchToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(performGrepStructured(grepCtx.pattern, grepCtx.path, grepCtx.recursive, grepCtx.max))
  of TextReadToolName:
    let readCtx = parseReadFileContext(j, ctx.paddockDir, ctx.log, TextReadToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    return handledStructured(readStructuredTextSlice(readCtx.path, readCtx.startLine, readCtx.maxLines))
  of TextReplaceToolName:
    let pathCtx = parsePathOnly(j, ctx.paddockDir, ctx.log, TextReplaceToolName).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    let findText = j.getOrDefault("find").getStr("")
    let replaceText = j.getOrDefault("replace").getStr("")
    let count = j.getOrDefault("count").getInt(0)
    return handledStructured(replaceStructuredText(pathCtx, findText, replaceText, count))
  of JsonQueryToolName:
    return handledStructured(runJsonQuery(j))
  of TableQueryToolName:
    return handledStructured(runTableQuery(j))
  of HttpFetchToolName:
    let fetchCtx = parseFetchContext(j, FetchDefaultMax).valueOr:
      return handledStructured(usageErrorToolResult(normalizedErrorMessage(error)))
    let rules = toolWebRules(ctx, HttpFetchToolName)
    return handledStructured(performFetchStructured(
      ctx.http, fetchCtx.url,
      expect = j.getOrDefault("expect").getStr("text"),
      maxCh = fetchCtx.maxCh,
      allowRules = rules,
      fallbackAllowlist = ctx.webAllowlist,
      policyLabel = HttpFetchToolName,
    ))
  of ArchiveExtractToolName:
    let archivePath = j.getOrDefault("archive_path").getStr("")
    let destination = j.getOrDefault("destination").getStr("")
    return handledStructured(performArchiveExtract(archivePath, destination, ctx.paddockDir))
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
    return handledStructured(performArchiveCreate(archivePath, inputs, ctx.paddockDir))
  else:
    return NativeToolResult(handled: false)

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
    return handledOutcome(performRenderMermaid(mermaidCtx.diagram))
  of InspectImageToolName:
    let inspectCtx = parseInspectImageContext(j).valueOr:
      return handledError(error)
    return handledOutcome(performInspectImage(inspectCtx.path, inspectCtx.prompt, ctx.completeFn))
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
      return handledError("Error: ask interrupted.")
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
  of ManageSkillsToolName:
    let skillCtx = parseManageSkillsContext(j).valueOr:
      return handledError(error)
    let reply = performManageSkills(
      ctx.memory, ctx.uid, buildManageSkillsValue(skillCtx),
      registry = skillCtx.registry,
    ).valueOr:
      return handledError(error)
    return handledText(reply)
  else:
    return NativeToolResult(handled: false)

proc executeAgentNativeTool(tc: ToolCallRequest;
                            ctx: NativeCtx;
                            state: SessionState;
                            history: ConversationHistory;
                            j: JsonNode;
                           ): Future[NativeToolResult] {.async.} =
  case tc.name
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
  else:
    return NativeToolResult(handled: false)

func categoryHandler(kind: NativeToolCategoryKind): NativeToolCategoryHandler =
  case kind
  of ntckLegacy: executeLegacyNativeTool
  of ntckShell: executeShellNativeTool
  of ntckStructured: executeStructuredNativeTool
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
    return categoryResult
  NativeToolResult(handled: false)

proc executeNativeTool*(tc:      ToolCallRequest;
                        ctx:     NativeCtx;
                        state:   SessionState;
                        history: ConversationHistory;
                       ): Future[NativeToolResult] {.async.} =
  let j = try: parseJson(tc.inputJson)
          except: newJObject()
  for category in nativeToolCategoryOrder():
    let categoryResult = await executeNativeCategory(tc, ctx, state, history, j, category)
    if categoryResult.handled:
      return categoryResult
  return NativeToolResult(handled: false)
