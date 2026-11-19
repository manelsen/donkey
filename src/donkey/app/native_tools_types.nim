## native_tools_types.nim — the native tool contract.
##
## Holds every value the native tool layer exchanges: the result envelope, the
## execution context, per-tool parse contexts, and the result builders used by
## the dispatch module and its consumers. No execution lives here; the dispatch
## layer in `native_dispatch.nim` owns I/O.
##
## executeNativeTool returns NativeToolResult:
##   handled=false  -> not a native tool; orchestrator falls through to ToolAgent
##   handled=true   -> result.text is the tool output
##   newHistory.isSome -> orchestrator must replace history (rewind)
##   checkpointNow  -> orchestrator must push current history to state.checkpoints

import std/[json, options, strutils]
import chronos
import ../core/tooling/structured_tool_result
import ../core/log
import ../ports/fs
import ../ports/http as httpPort
import ../ports/memory
import ../ports/provider
import ../domain/message
import ../domain/subagent_pure
import ../config/types as cfgTypes
import ./approval_runtime
import ./provider_executor
import ./sandbox
import ./session_manager
import ./session_state
import ./tools/text_tools

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

  NativeCtx* = object
    uid*:          UserId
    channel*:      ChannelKind
    outbox*:       AsyncQueue[OutboundMessage]
    session*:      ptr SessionEntry
    memory*:       MemoryRuntimePort
    fs*:           FsRuntimePort
    completeFn*:   CompleteFn
    asyncCompleteFn*: AsyncCompleteFn
    http*:         httpPort.HttpRuntimePort
    braveApiKey*:  string
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

  AskContext* = object
    question*: string

  SessionSearchContext* = object
    query*:         string
    limit*:         int
    includeMemory*: bool

  MemoryIngestContext* = object
    path*:       string
    text*:       string
    chunkChars*: int
    maxChunks*:  int

  SpawnSubagentContext* = object
    request*: SubagentRequest
    wait*:    bool

  AwaitSubagentContext* = object
    subagentId*: string

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

  TranscribeContext* = object
    path*:     string
    language*: string
    prompt*:   string

  SpeechContext* = object
    text*:    string
    voice*:   string
    format*:  string
    asVoice*: bool
    caption*: string

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

  NativeToolCategoryHandler* = proc(tc: ToolCallRequest;
                                   ctx: NativeCtx;
                                   state: SessionState;
                                   history: ConversationHistory;
                                   j: JsonNode;
                                  ): Future[NativeToolResult] {.nimcall, gcsafe, raises: [].}

# ── Result helpers ────────────────────────────────────────────────────────────

proc handledText*(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOutput)

proc handledError*(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOperationalError)

proc handledSubagentResult*(subagentResult: SubagentResult): NativeToolResult
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

proc handledStructured*(value: StructuredToolResult): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: value.toJson(), resultKind: value.kind)

proc normalizedErrorMessage*(text: string): string =
  if text.startsWith("Error: "): text["Error: ".len .. ^1]
  else: text

func isOperationalErrorText(text: string): bool =
  text.startsWith("Error:") or
  text.startsWith("HTTP error ") or
  text.startsWith("Brave API error ")

proc handledOutcome*(text: string): NativeToolResult {.gcsafe, raises: [].} =
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

