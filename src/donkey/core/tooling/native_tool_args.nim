## Native tool arguments: the JSON a model sends, checked and turned into the
## context each tool runs with. Pure: no file system, no logging. Tools that
## take a path get it here as the model wrote it; `app/native_tools` resolves
## it inside the paddock (which needs the file system) before the tool runs.

import std/[json, options, sequtils, strutils]
import ../pipeops
import ../../domain/subagent_pure
import ../../domain/memory/session_search_pure
import ../../domain/memory/ingest_pure

type
  AskContext* = object
    question*: string

  SessionSearchContext* = object
    query*:         string   ## ranked terms
    phrase*:        string   ## exact phrase
    sessionId*:     string   ## read around a message of this session
    around*:        int64
    since*:         string
    until*:         string
    limit*:         int      ## 0 = the mode's default
    offset*:        int
    context*:       int      ## -1 = the mode's default
    countOnly*:     bool
    oldestFirst*:   bool
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

  ManageAgentsContext* = object
    action*:      string   ## list, create, update, delete, note
    name*:        string
    description*: string
    provider*:    string
    model*:       string
    text*:        string

  ManageSchedulesContext* = object
    action*:   string   ## list, create, delete, pause, resume
    name*:     string
    schedule*: string   ## cron, alias or `@every …`
    prompt*:   string   ## what the agent is asked at each firing
    timezone*: string   ## `UTC±HH:MM`; "" = UTC
    catchUp*:  string   ## skip | once; "" = skip

  AskAgentContext* = object
    name*:     string
    question*: string
    context*:  string

  ConveneAgentsContext* = object
    agents*:   seq[string]
    question*: string
    context*:  string
    rounds*:   int

  ManageSkillsContext* = object
    action*:   string
    query*:    string
    slug*:     string
    name*:     string
    registry*: string

  HashlineAnchor* = object
    line*: int
    hash*: string

  EditFileOpKind* = enum
    efokReplace = "replace"
    efokAppend  = "append"
    efokPrepend = "prepend"

  EditFileOp* = object
    kind*:  EditFileOpKind
    pos*:   Option[HashlineAnchor]
    stop*:  Option[HashlineAnchor]
    lines*: seq[string]

  EditFileContext* = object
    path*:  string
    edits*: seq[EditFileOp]

# ── field readers ─────────────────────────────────────────────────────────────

func requireStringField*(j: JsonNode; key: string): Result[string, string] =
  ## A non-empty string field, or the "'key' is required" error.
  let value = j.getOrDefault(key).getStr("")
  if value.len == 0:
    return err("Error: '" & key & "' is required.")
  ok(value)

func optionalIntField*(j: JsonNode; key: string): Result[int, string] =
  ## 0 when absent or null; an error when present with another type.
  let node = j.getOrDefault(key)
  if node == nil or node.kind == JNull:
    return ok(0)
  if node.kind != JInt:
    return err("'" & key & "' must be an integer")
  ok(node.getInt())

func optionalBoolField*(j: JsonNode; key: string; fallback: bool): Result[bool, string] =
  let node = j.getOrDefault(key)
  if node == nil or node.kind == JNull:
    return ok(fallback)
  if node.kind != JBool:
    return err("'" & key & "' must be a boolean")
  ok(node.getBool())

func optionalStringField*(j: JsonNode; key: string): Result[string, string] =
  let node = j.getOrDefault(key)
  if node == nil or node.kind == JNull:
    return ok("")
  if node.kind != JString:
    return err("'" & key & "' must be a string")
  ok(node.getStr(""))

func stringArrayField*(j: JsonNode; key: string): Result[seq[string], string] =
  ## Trimmed, non-empty and without repeats; an error for anything but an
  ## array of strings.
  let node = j.getOrDefault(key)
  if node == nil or node.kind == JNull:
    return ok(newSeq[string]())
  if node.kind != JArray:
    return err("'" & key & "' must be an array of strings")
  var values: seq[string]
  for item in node.items:
    if item.kind != JString:
      return err("'" & key & "' must contain only strings")
    let value = item.getStr("").strip()
    if value.len > 0 and value notin values:
      values.add(value)
  ok(values)

# ── memory, subagents, session ────────────────────────────────────────────────

func parseSessionSearchContext*(j: JsonNode): Result[SessionSearchContext, string] =
  func str(key: string): string =
    let n = j.getOrDefault(key)
    if n != nil and n.kind == JString: n.getStr("").strip() else: ""
  func int64Of(key: string): int64 =
    let n = j.getOrDefault(key)
    if n != nil and n.kind == JInt: n.getBiggestInt().int64 else: 0
  func boolOf(key: string; fallback: bool): bool =
    let n = j.getOrDefault(key)
    if n != nil and n.kind == JBool: n.getBool() else: fallback
  let query = str("query")
  let phrase = str("phrase")
  let sessionId = str("session_id")
  if query.len == 0 and phrase.len == 0 and sessionId.len == 0:
    return err("'query' is required (or 'phrase' for an exact string, or " &
               "'session_id' to read a session)")
  for (name, value) in [("query", query), ("phrase", phrase)]:
    if value.len > SessionSearchMaxQueryChars:
      return err(name & " exceeds " & $SessionSearchMaxQueryChars & " characters")
  let order = str("order").toLowerAscii
  if order notin ["", "newest", "oldest"]:
    return err("order must be newest or oldest")
  ok(SessionSearchContext(query: query, phrase: phrase, sessionId: sessionId,
    around: int64Of("around"), since: str("since"), until: str("until"),
    limit: max(0, int(int64Of("limit"))), offset: max(0, int(int64Of("offset"))),
    context: (if j.getOrDefault("context") != nil and j["context"].kind == JInt:
                max(0, int(int64Of("context"))) else: -1), countOnly: boolOf("count", false),
    oldestFirst: order == "oldest", includeMemory: boolOf("include_memory", true)))

func parseMemoryIngestContext*(j: JsonNode): Result[MemoryIngestContext, string] =
  let path = j.getOrDefault("path").getStr("").strip()
  let text = j.getOrDefault("text").getStr("")
  if path.len > 0 and text.strip.len > 0:
    return err("use either 'path' or 'text', not both")
  if path.len == 0 and text.strip.len == 0:
    return err("'path' or 'text' is required")
  let chunkNode = j.getOrDefault("chunk_chars")
  let chunkChars =
    if chunkNode != nil and chunkNode.kind == JInt:
      clampChunkChars(chunkNode.getInt())
    else:
      DefaultIngestChunkChars
  let maxNode = j.getOrDefault("max_chunks")
  let maxChunks =
    if maxNode != nil and maxNode.kind == JInt:
      clampMaxChunks(maxNode.getInt())
    else:
      DefaultIngestMaxChunks
  ok(MemoryIngestContext(path: path, text: text,
                         chunkChars: chunkChars, maxChunks: maxChunks))

func parseSpawnSubagentContext*(j: JsonNode): Result[SpawnSubagentContext, string] =
  let task = j.getOrDefault("task").getStr("").strip()
  if task.len == 0:
    return err("'task' is required")
  let context = ?optionalStringField(j, "context")
  let tools = ?stringArrayField(j, "tools")
  let maxToolCalls = ?optionalIntField(j, "max_tool_calls")
  let maxTokens = ?optionalIntField(j, "max_tokens")
  let maxDurationSec = ?optionalIntField(j, "max_duration_sec")
  let wait = ?optionalBoolField(j, "wait", true)
  let maxDurationSecClamped =
    if maxDurationSec <= 0:
      0
    else:
      min(maxDurationSec, int(SubagentMaxDurationMs div 1000'i64))
  let limits = clampSubagentLimits(SubagentLimits(
    maxToolCalls: maxToolCalls,
    maxTokens: maxTokens,
    maxDurationMs: int64(maxDurationSecClamped) * 1000'i64,
  ))
  ok(SpawnSubagentContext(
    request: SubagentRequest(
      task: task,
      context: context,
      tools: tools,
      limits: limits,
    ),
    wait: wait,
  ))

func parseAwaitSubagentContext*(j: JsonNode): Result[AwaitSubagentContext, string] =
  let subagentId = j.getOrDefault("subagent_id").getStr("").strip()
  if subagentId.len == 0:
    return err("'subagent_id' is required")
  ok(AwaitSubagentContext(subagentId: subagentId))

func parseAskContext*(j: JsonNode): Result[AskContext, string] =
  ok(AskContext(question: ?j.requireStringField("question")))

func parseBashContext*(j: JsonNode): Result[BashContext, string] =
  ok(BashContext(command: ?j.requireStringField("command")))

# ── file tools (raw paths) ────────────────────────────────────────────────────

func parseReadFileArgs*(j: JsonNode): Result[ReadFileContext, string] =
  ok(ReadFileContext(
    path: ?j.requireStringField("path"),
    startLine: max(1, j.getOrDefault("start_line").getInt(1)),
    maxLines: max(1, j.getOrDefault("max_lines").getInt(200)),
  ))

func parseFindArgs*(j: JsonNode): Result[FindContext, string] =
  ok(FindContext(
    path: ?j.requireStringField("path"),
    pattern: j.getOrDefault("pattern").getStr("*"),
    kind: j.getOrDefault("type").getStr("file"),
    max: j.getOrDefault("max").getInt(50),
  ))

func parseGrepArgs*(j: JsonNode): Result[GrepContext, string] =
  let pattern = ?j.requireStringField("pattern")
  ok(GrepContext(
    pattern: pattern,
    path: ?j.requireStringField("path"),
    recursive: j.getOrDefault("recursive").getBool(true),
    max: j.getOrDefault("max").getInt(50),
  ))

func parseSedArgs*(j: JsonNode): Result[SedContext, string] =
  let expression = ?j.requireStringField("expression")
  ok(SedContext(expression: expression, path: ?j.requireStringField("path")))

func parseWcArgs*(j: JsonNode): Result[WcContext, string] =
  ok(WcContext(path: ?j.requireStringField("path"),
               flags: j.getOrDefault("flags").getStr("")))

func parseHeadTailArgs*(j: JsonNode): Result[HeadTailContext, string] =
  ok(HeadTailContext(path: ?j.requireStringField("path"),
                     lines: j.getOrDefault("lines").getInt(10)))

func parseSortArgs*(j: JsonNode): Result[SortContext, string] =
  ok(SortContext(path: ?j.requireStringField("path"),
                 flags: j.getOrDefault("flags").getStr("")))

func parseCpMvArgs*(j: JsonNode): Result[CpMvContext, string] =
  let source = ?j.requireStringField("source")
  ok(CpMvContext(source: source, dest: ?j.requireStringField("dest")))

func parseInspectImageArgs*(j: JsonNode): Result[InspectImageContext, string] =
  ok(InspectImageContext(path: ?j.requireStringField("path"),
                         prompt: j.getOrDefault("prompt").getStr("")))

func parseTranscribeArgs*(j: JsonNode): Result[TranscribeContext, string] =
  ok(TranscribeContext(
    path: ?j.requireStringField("path"),
    language: j.getOrDefault("language").getStr("").strip,
    prompt: j.getOrDefault("prompt").getStr("").strip))

func parseHashlineAnchor*(raw: string): Result[HashlineAnchor, string] =
  ## `LINE#HASH`, optionally followed by `:text` (ignored).
  let trimmed = raw.strip()
  let anchorOnly =
    if ":" in trimmed: trimmed.split(":", maxsplit = 1)[0].strip()
    else: trimmed
  let parts = anchorOnly.split("#", maxsplit = 1)
  if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
    return err("Error: invalid anchor '" & raw & "'. Expected LINE#ID.")
  let line =
    try: parseInt(parts[0])
    except ValueError:
      return err("Error: invalid anchor '" & raw & "'. Expected LINE#ID.")
  if line < 1:
    return err("Error: invalid anchor '" & raw & "'. Line must be >= 1.")
  ok(HashlineAnchor(line: line, hash: parts[1].toLowerAscii()))

func firstStringOf(item: JsonNode; keys: openArray[string]): string =
  ## The first non-empty string among `keys` (the field and its aliases).
  for key in keys:
    let value = item.getOrDefault(key).getStr("")
    if value.len > 0:
      return value
  ""

func parseEditFileArgs*(j: JsonNode): Result[EditFileContext, string] =
  let path = ?j.requireStringField("path")
  let editsNode = j.getOrDefault("edits")
  if editsNode == nil or editsNode.kind != JArray:
    return err("Error: 'edits' must be an array.")
  var edits: seq[EditFileOp] = @[]
  for item in editsNode:
    let opName = item.getOrDefault("op").getStr("")
    let opKind =
      case opName
      of "replace": efokReplace
      of "append": efokAppend
      of "prepend": efokPrepend
      else: return err("Error: unsupported edit op '" & opName & "'.")
    var pos = none(HashlineAnchor)
    var stop = none(HashlineAnchor)
    let posRaw = item.firstStringOf(["pos", "anchor", "start"])
    if posRaw.len > 0:
      pos = some(?parseHashlineAnchor(posRaw))
    let stopRaw = item.firstStringOf(["end", "stop", "to"])
    if stopRaw.len > 0:
      stop = some(?parseHashlineAnchor(stopRaw))
    if opKind == efokReplace and pos.isNone:
      return err("Error: replace edits require 'pos'.")
    var lines: seq[string] = @[]
    let linesNode = item.getOrDefault("lines")
    if linesNode != nil and linesNode.kind == JArray:
      for li in linesNode:
        if li.kind == JString: lines.add(li.getStr())
        else: return err("Error: 'lines' must be an array of strings.")
    edits.add(EditFileOp(kind: opKind, pos: pos, stop: stop, lines: lines))
  ok(EditFileContext(path: path, edits: edits))

# ── web, media, utility ───────────────────────────────────────────────────────

func parseFetchContext*(j: JsonNode; defaultMax: int): Result[FetchContext, string] =
  ok(FetchContext(url: ?j.requireStringField("url"),
                  maxCh: j.getOrDefault("max_chars").getInt(defaultMax)))

func parseWebSearchContext*(j: JsonNode): Result[WebSearchContext, string] =
  ok(WebSearchContext(query: ?j.requireStringField("query"),
                      count: j.getOrDefault("count").getInt(5)))

func parseCalcContext*(j: JsonNode): Result[CalcContext, string] =
  ok(CalcContext(expression: ?j.requireStringField("expression")))

func parseMermaidContext*(j: JsonNode): Result[MermaidContext, string] =
  ok(MermaidContext(diagram: ?j.requireStringField("diagram")))

func parseSpeechContext*(j: JsonNode): Result[SpeechContext, string] =
  let text = ?j.requireStringField("text")
  let asVoice = ?optionalBoolField(j, "as_voice", false)
  let caption = ?optionalStringField(j, "caption")
  ok(SpeechContext(
    text: text,
    voice: j.getOrDefault("voice").getStr("").strip,
    format: j.getOrDefault("format").getStr("").strip,
    asVoice: asVoice,
    caption: caption))

func parseTaskContext*(j: JsonNode): Result[TaskContext, string] =
  ok(TaskContext(prompt: ?j.requireStringField("prompt"),
                 context: j.getOrDefault("context").getStr("")))

func parseAwaitContext*(j: JsonNode): Result[AwaitContext, string] =
  let ids = j.getOrDefault("job_ids")
  if ids == nil or ids.kind != JArray:
    return err("Error: 'job_ids' must be an array.")
  ok(AwaitContext(ids: ids.mapIt(it.getStr())))

func parseFindingContext*(j: JsonNode): Result[FindingContext, string] =
  ok(FindingContext(finding: ?j.requireStringField("finding")))

func parseManageAgentsContext*(j: JsonNode): Result[ManageAgentsContext, string] =
  let action = j.getOrDefault("action").getStr("list").strip.toLowerAscii()
  case action
  of "", "list":
    ok(ManageAgentsContext(action: "list"))
  of "create":
    ok(ManageAgentsContext(action: action, name: ?j.requireStringField("name"),
      description: ?j.requireStringField("description"),
      provider: ?j.optionalStringField("provider"),
      model: ?j.optionalStringField("model")))
  of "update":
    ok(ManageAgentsContext(action: action, name: ?j.requireStringField("name"),
      description: ?j.optionalStringField("description"),
      provider: ?j.optionalStringField("provider"),
      model: ?j.optionalStringField("model")))
  of "delete":
    ok(ManageAgentsContext(action: action, name: ?j.requireStringField("name")))
  of "note":
    ok(ManageAgentsContext(action: action, name: ?j.requireStringField("name"),
      text: ?j.requireStringField("text")))
  else:
    err("Error: unknown action '" & action & "' (list, create, update, delete, note)")

func parseManageSchedulesContext*(j: JsonNode): Result[ManageSchedulesContext, string] =
  let action = j.getOrDefault("action").getStr("list").strip.toLowerAscii()
  case action
  of "", "list":
    ok(ManageSchedulesContext(action: "list"))
  of "create":
    ok(ManageSchedulesContext(action: action, name: ?j.requireStringField("name"),
      schedule: ?j.requireStringField("schedule"),
      prompt: ?j.requireStringField("prompt"),
      timezone: ?j.optionalStringField("timezone"),
      catchUp: ?j.optionalStringField("catch_up")))
  of "delete", "pause", "resume":
    ok(ManageSchedulesContext(action: action, name: ?j.requireStringField("name")))
  else:
    err("Error: unknown action '" & action & "' (list, create, delete, pause, resume)")

func parseAskAgentContext*(j: JsonNode): Result[AskAgentContext, string] =
  ok(AskAgentContext(name: ?j.requireStringField("name"),
                     question: ?j.requireStringField("question"),
                     context: ?j.optionalStringField("context")))

func parseConveneAgentsContext*(j: JsonNode): Result[ConveneAgentsContext, string] =
  let rounds = ?j.optionalIntField("rounds")
  ok(ConveneAgentsContext(agents: ?j.stringArrayField("agents"),
                          question: ?j.requireStringField("question"),
                          context: ?j.optionalStringField("context"),
                          rounds: if rounds <= 0: 2 else: rounds))

func parseManageSkillsContext*(j: JsonNode): Result[ManageSkillsContext, string] =
  let action = j.getOrDefault("action").getStr("help").strip.toLowerAscii()
  let registry = j.getOrDefault("registry").getStr("")
  case action
  of "", "help", "list":
    ok(ManageSkillsContext(action: if action.len == 0: "help" else: action))
  of "search":
    ok(ManageSkillsContext(action: action, query: ?j.requireStringField("query"),
                           registry: registry))
  of "install", "enable", "read":
    ok(ManageSkillsContext(action: action, slug: ?j.requireStringField("slug"),
                           registry: registry))
  of "disable", "remove":
    ok(ManageSkillsContext(action: "disable", name: ?j.requireStringField("name"),
                           registry: registry))
  else:
    err("Error: unsupported manage_skills action '" & action & "'.")

func buildManageSkillsValue*(ctx: ManageSkillsContext): string =
  ## The `/skill` command text the context stands for.
  case ctx.action
  of "help", "list": ctx.action
  of "search": "search " & ctx.query
  of "install", "enable": ctx.action & " " & ctx.slug
  of "disable": "disable " & ctx.name
  of "read": "read " & ctx.slug
  else: ctx.action

func parseTodoOps*(j: JsonNode): Result[JsonNode, string] =
  let ops = j.getOrDefault("ops")
  if ops == nil or ops.kind != JArray:
    return err("Error: 'ops' must be an array.")
  ok(ops)

func parseRewindIndex*(j: JsonNode; checkpointCount: int): Result[int, string] =
  ## The checkpoint to rewind to; the last one when `index` is absent.
  if checkpointCount == 0:
    return err("Error: no checkpoints saved.")
  let idx = j.getOrDefault("index").getInt(checkpointCount - 1)
  if idx < 0 or idx >= checkpointCount:
    return err("Error: checkpoint index " & $idx & " out of range (0.." &
               $(checkpointCount - 1) & ").")
  ok(idx)
