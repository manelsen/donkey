## native_tools.nim — execution of all native (non-MCP) tools.
##
## executeNativeTool returns NativeToolResult:
##   handled=false  → not a native tool; orchestrator falls through to ToolAgent
##   handled=true   → result.text is the tool output
##   newHistory.isSome → orchestrator must replace history (rewind)
##   checkpointNow  → orchestrator must push current history to state.checkpoints
##
## Tool categories:
##   Shell   : bash, read_file, edit_file, find, grep
##   Web     : fetch, web_search
##   Utility : calc, render_mermaid, inspect_image
##   Session : ask, todo_write, checkpoint, rewind
##   Agent   : task, submit_result, report_finding, cancel_job, await
##   Legacy  : schedule_reminder, current_time, web_fetch  (moved here from orchestrator)

import std/[algorithm, json, osproc, os, strutils, base64, tables, sequtils, times, options, uri]
import chronos
import chronos/asyncsync
import nimcrypto/sha2
import ../core/app_meta
import ../core/tooling/native_tool_dispatch
import ../core/pipeops
import ../core/log
import ../domain/message
import ../domain/more_tools
import ../domain/builtin_tools
import ../domain/calc
import ../domain/reminder
import ../ports/http as httpPort
import ../ports/provider
import ../ports/memory
import ../config/types as cfgTypes
import ./sandbox
import ./session_state
import ./session_manager

# ── Result type ───────────────────────────────────────────────────────────────

type
  NativeToolResult* = object
    handled*:       bool
    text*:          string
    resultKind*:    ToolResultKind
    newHistory*:    Option[ConversationHistory]  ## set by rewind
    checkpointNow*: bool                         ## set by checkpoint

  AskContext* = object
    question*: string

  BashContext* = object
    command*: string

  ReadFileContext* = object
    path*:      string
    startLine*: int
    maxLines*:  int

  HashlineAnchor* = object
    line*: int
    hash*: string

  EditFileOpKind* = enum
    efokReplace = "replace"
    efokAppend = "append"
    efokPrepend = "prepend"

  EditFileOp* = object
    kind*:  EditFileOpKind
    pos*:   Option[HashlineAnchor]
    stop*:  Option[HashlineAnchor]
    lines*: seq[string]

  EditFileContext* = object
    path*:  string
    edits*: seq[EditFileOp]

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

# ── Context ───────────────────────────────────────────────────────────────────

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
    paddockDir*:   string       ## agent workspace root; empty = unconstrained (tests only)
    sandboxMode*:  SandboxMode  ## bash isolation mode
    sandboxImage*: string       ## Docker image when sandboxMode = smDocker

  NativeToolCategoryHandler = proc(tc: ToolCallRequest;
                                   ctx: NativeCtx;
                                   state: SessionState;
                                   history: ConversationHistory;
                                   j: JsonNode;
                                  ): Future[NativeToolResult] {.nimcall, gcsafe, raises: [].}

# ── Paddock path helpers ───────────────────────────────────────────────────────

proc resolveInPaddock*(path, paddock: string): string =
  ## Returns an absolute path by resolving `path` relative to `paddock`,
  ## collapsing any `..` segments without following symlinks.
  let base = if isAbsolute(path): path else: paddock / path
  var parts: seq[string] = @[]
  for seg in base.split('/'):
    case seg
    of "", ".": discard
    of "..":
      if parts.len > 0: parts.setLen(parts.len - 1)
    else: parts.add(seg)
  "/" & parts.join("/")

proc inPaddock*(path, paddock: string): bool =
  ## True iff the resolved path is inside paddock (no symlink resolution).
  let norm    = resolveInPaddock(path, paddock)
  let padNorm = resolveInPaddock(paddock, paddock)
  norm == padNorm or norm.startsWith(padNorm & "/")

# ── HTML stripper (for fetch) ─────────────────────────────────────────────────

proc stripHtml(html: string): string =
  result = newStringOfCap(html.len)
  var inTag    = false
  var inScript = false
  var i        = 0
  while i < html.len:
    if not inTag and not inScript and html[i] == '<':
      # Detect start of <script or <style
      let rest = html[i + 1 ..< min(i + 8, html.len)].toLowerAscii()
      if rest.startsWith("script") or rest.startsWith("style"):
        inScript = true
      inTag = true
    elif inTag and html[i] == '>':
      inTag = false
      # Detect end of </script> or </style>
      if inScript:
        let look = i.int - 8
        if look >= 0:
          let end8 = html[max(0, look) ..< i].toLowerAscii()
          if "/script" in end8 or "/style" in end8:
            inScript = false
      if not inScript:
        result.add(' ')
    elif not inTag and not inScript:
      # Decode common entities
      if html[i] == '&' and i + 3 < html.len:
        let chunk = html[i ..< min(i + 7, html.len)]
        if chunk.startsWith("&amp;"):
          result.add('&'); i += 5; continue
        elif chunk.startsWith("&lt;"):
          result.add('<'); i += 4; continue
        elif chunk.startsWith("&gt;"):
          result.add('>'); i += 4; continue
        elif chunk.startsWith("&quot;"):
          result.add('"'); i += 6; continue
        elif chunk.startsWith("&nbsp;"):
          result.add(' '); i += 6; continue
        else:
          result.add(html[i])
      else:
        result.add(html[i])
    inc i
  # Collapse excessive whitespace (replace control chars with space, deduplicate)
  var normalized = newStringOfCap(result.len)
  for c in result:
    if c in {'\n', '\r', '\t'}: normalized.add(' ')
    else: normalized.add(c)
  var prev2 = ' '
  var compacted = newStringOfCap(normalized.len)
  for c in normalized:
    if not (c == ' ' and prev2 == ' '):
      compacted.add(c)
    prev2 = c
  result = compacted.strip()

# ── bash ──────────────────────────────────────────────────────────────────────

proc performBash*(cmd: string; workingDir = ""): string {.gcsafe, raises: [].} =
  try:
    if workingDir.len > 0:
      createDir(workingDir)
    let (output, code) = execCmdEx(cmd,
                                   options = {poEvalCommand, poStdErrToStdOut},
                                   workingDir = workingDir)
    result = output
    if result.endsWith('\n'): result.setLen(result.len - 1)
    if code != 0:
      if result.len > 0: result.add('\n')
      result.add("[exit " & $code & "]")
    if result.len == 0:
      result = "[exit " & $code & "]"
  except CatchableError as e:
    result = "Error: " & e.msg

# ── hashline-backed read/edit ────────────────────────────────────────────────

proc sha256hex(data: string): string {.gcsafe, raises: [].} =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())

proc normalizeHashlineLine(line: string): string {.gcsafe, raises: [].} =
  line.replace("\r", "").strip()

proc computeLineHash*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  let normalized = normalizeHashlineLine(line)
  let seed =
    if normalized.anyIt(it.isAlphaNumeric): normalized
    else: normalized & ":" & $lineNum
  sha256hex(seed)[0 .. 5]

proc formatHashlineRef*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  $lineNum & "#" & computeLineHash(lineNum, line)

proc formatHashlineLine*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  formatHashlineRef(lineNum, line) & ":" & line

proc splitEditableLines(content: string): seq[string] {.gcsafe, raises: [].} =
  if content.len == 0: @[]
  else: content.splitLines()

proc displayLines(content: string): seq[string] {.gcsafe, raises: [].} =
  let lines = splitEditableLines(content)
  if lines.len == 0: @[""]
  else: lines

proc renderHashlineSlice*(content: string; startLine, maxLines: int): string {.gcsafe, raises: [].} =
  let lines = displayLines(content)
  if startLine > lines.len:
    return "(no lines)"
  let firstLine = max(1, startLine)
  let lastLine = min(lines.len, firstLine + max(1, maxLines) - 1)
  for idx in firstLine .. lastLine:
    result.add(formatHashlineLine(idx, lines[idx - 1]))
    if idx < lastLine:
      result.add('\n')

proc parseHashlineAnchor*(raw: string): Result[HashlineAnchor, string] {.gcsafe, raises: [].} =
  let parts = raw.split("#", maxsplit = 1)
  if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
    return err("Error: invalid anchor '" & raw & "'. Expected LINE#ID.")
  try:
    let line = parseInt(parts[0])
    if line < 1:
      return err("Error: invalid anchor '" & raw & "'. Line must be >= 1.")
    ok(HashlineAnchor(line: line, hash: parts[1].toLowerAscii()))
  except ValueError:
    err("Error: invalid anchor '" & raw & "'. Expected LINE#ID.")

proc validateHashlineAnchor*(anchor: HashlineAnchor;
                             lines: seq[string]): Result[bool, string] {.gcsafe, raises: [].} =
  if anchor.line < 1 or anchor.line > lines.len:
    return err("Error: line " & $anchor.line & " does not exist (file has " & $lines.len & " lines).")
  let actual = computeLineHash(anchor.line, lines[anchor.line - 1])
  if actual != anchor.hash:
    return err("Error: stale anchor " & $anchor.line & "#" & anchor.hash &
               ". Current line is " & formatHashlineLine(anchor.line, lines[anchor.line - 1]) & ".")
  ok(true)

proc applyEditFileOps*(lines: seq[string];
                       edits: seq[EditFileOp]): Result[seq[string], string] {.gcsafe, raises: [].} =
  var updated = lines
  for edit in edits:
    if edit.pos.isSome:
      let posResult = validateHashlineAnchor(edit.pos.get(), updated)
      if posResult.isErr:
        return err(posResult.error)
    if edit.stop.isSome:
      let stopResult = validateHashlineAnchor(edit.stop.get(), updated)
      if stopResult.isErr:
        return err(stopResult.error)

  proc sortLine(edit: EditFileOp; lineCount: int): int =
    case edit.kind
    of efokReplace:
      if edit.stop.isSome: edit.stop.get().line else: edit.pos.get().line
    of efokAppend:
      if edit.pos.isSome: edit.pos.get().line else: lineCount + 1
    of efokPrepend:
      if edit.pos.isSome: edit.pos.get().line else: 0

  var sortedEdits = edits
  sortedEdits.sort(proc(a, b: EditFileOp): int =
    cmp(sortLine(b, updated.len), sortLine(a, updated.len))
  )

  for edit in sortedEdits:
    case edit.kind
    of efokReplace:
      let startLine = edit.pos.get().line
      let stopLine =
        if edit.stop.isSome: edit.stop.get().line
        else: startLine
      if stopLine < startLine:
        return err("Error: replace range end precedes start.")
      updated.delete(startLine - 1 .. stopLine - 1)
      updated.insert(edit.lines, startLine - 1)
    of efokAppend:
      if edit.pos.isSome:
        updated.insert(edit.lines, edit.pos.get().line)
      else:
        updated.add(edit.lines)
    of efokPrepend:
      if edit.pos.isSome:
        updated.insert(edit.lines, edit.pos.get().line - 1)
      else:
        updated.insert(edit.lines, 0)

  ok(updated)

# ── find ──────────────────────────────────────────────────────────────────────

proc walkFind(path, pattern, kind: string; max: int;
              results: var seq[string]) {.gcsafe, raises: [].} =
  if results.len >= max: return
  try:
    for entry in walkDir(path):
      let name = splitPath(entry.path).tail
      case entry.kind
      of pcFile:
        if kind != "dir" and globMatch(pattern, name):
          results.add(entry.path)
          if results.len >= max: return
      of pcDir:
        if kind != "file" and globMatch(pattern, name):
          results.add(entry.path & "/")
          if results.len >= max: return
        walkFind(entry.path, pattern, kind, max, results)
      of pcLinkToFile, pcLinkToDir:
        discard  ## skip symlinks — prevents escaping the paddock
  except CatchableError: discard

proc performFind*(path, pattern, kind: string; max: int): string {.gcsafe, raises: [].} =
  var results: seq[string] = @[]
  walkFind(path, pattern, kind, max, results)
  if results.len == 0: return "(no matches)"
  results.join("\n")

# ── grep ──────────────────────────────────────────────────────────────────────
## Note: grep uses literal substring search (case-sensitive).
## For full regex, use bash("grep -rn 'pattern' /path") instead.

proc grepFile(path, pattern: string; max: int;
              results: var seq[string]) {.gcsafe, raises: [].} =
  try:
    var lineNum = 0
    for line in lines(path):
      inc lineNum
      if line.find(pattern) >= 0:
        results.add(path & ":" & $lineNum & ":" & line)
        if results.len >= max: return
  except CatchableError: discard

proc grepDir(path, pattern: string; recursive: bool;
             max: int; results: var seq[string]) {.gcsafe, raises: [].} =
  try:
    for entry in walkDir(path):
      if results.len >= max: return
      case entry.kind
      of pcFile:
        grepFile(entry.path, pattern, max, results)
      of pcDir:
        if recursive:
          grepDir(entry.path, pattern, recursive, max, results)
      of pcLinkToFile, pcLinkToDir:
        discard  ## skip symlinks — prevents escaping the paddock
  except CatchableError: discard

proc performGrep*(pattern, path: string; recursive: bool;
                  max: int): string {.gcsafe, raises: [].} =
  if pattern.len == 0: return "Error: empty pattern"
  var results: seq[string] = @[]
  if fileExists(path):
    grepFile(path, pattern, max, results)
  elif dirExists(path):
    grepDir(path, pattern, recursive, max, results)
  else:
    return "Error: path not found: " & path
  if results.len == 0: return "(no matches)"
  results.join("\n")

# ── fetch ─────────────────────────────────────────────────────────────────────

const FetchHardMax* = 20_000
const FetchDefaultMax* = 5_000

proc performFetch*(http: httpPort.HttpRuntimePort;
                   url: string;
                   maxCh: int;
                   allowRules: seq[cfgTypes.WebAccessRule] = @[];
                   fallbackAllowlist: seq[string] = @[];
                   policyLabel = "web access"): string {.gcsafe, raises: [].} =
  try:
    if not isAllowedPublicUrl(url, allowRules, fallbackAllowlist):
      return buildUrlAccessError(url, allowRules, fallbackAllowlist, policyLabel)
    let resp = http.get(url, @[])
    if resp.isErr: return "Error: " & resp.error
    let r = resp.value
    if r.status < 200 or r.status >= 300:
      return "HTTP error " & $r.status
    let cap  = min(maxCh, FetchHardMax)
    var body = r.body.strip()
    if body.startsWith("{") or body.startsWith("["):
      try:
        let jj = parseJson(body)
        body = jj.pretty()
      except: discard
    elif body.startsWith("<"):
      body = stripHtml(body)
    truncateBody(body, cap)
  except Exception as e:
    "Error: " & e.msg

# ── web_search (Brave) ────────────────────────────────────────────────────────

const BraveSearchUrl = "https://api.search.brave.com/res/v1/web/search"

proc performWebSearch*(query: string; count: int;
                       apiKey: string;
                       http: httpPort.HttpRuntimePort;
                       allowRules: seq[cfgTypes.WebAccessRule] = @[];
                       fallbackAllowlist: seq[string] = @[]): string {.gcsafe, raises: [].} =
  if apiKey.len == 0:
    return "Error: BRAVE_API_KEY not configured. Set the environment variable."
  try:
    let url     = BraveSearchUrl & "?q=" & encodeUrl(query) & "&count=" & $min(count, 20)
    if not isAllowedPublicUrl(url, allowRules, fallbackAllowlist):
      return buildUrlAccessError(url, allowRules, fallbackAllowlist, "web_search")
    let headers = @[
      ("X-Subscription-Token", apiKey),
      ("Accept",               "application/json"),
    ]
    var resp: Result[HttpResponse, string]
    try: resp = http.get(url, headers)
    except Exception as e: return "Error: " & e.msg
    if resp.isErr: return "Error: " & resp.error
    if resp.value.status != 200:
      return "Brave API error " & $resp.value.status
    let j = parseJson(resp.value.body)
    let webResults = j.getOrDefault("web").getOrDefault("results")
    if webResults.kind != JArray or webResults.len == 0:
      return "(no results)"
    var lines: seq[string] = @[]
    for item in webResults:
      let title = item.getOrDefault("title").getStr("(no title)")
      let url2  = item.getOrDefault("url").getStr("")
      let desc  = item.getOrDefault("description").getStr("")
      lines.add(title & "\n" & url2 & "\n" & desc)
    lines.join("\n\n")
  except CatchableError as e:
    "Error: " & e.msg

# ── render_mermaid ────────────────────────────────────────────────────────────

proc performRenderMermaid*(diagram: string): string {.gcsafe, raises: [].} =
  let ts    = $getTime().toUnix()
  let inF   = "/tmp/" & MermaidTempPrefix & ts & ".mmd"
  let outF  = "/tmp/" & MermaidTempPrefix & ts & ".svg"
  try:
    writeFile(inF, diagram)
    let (_, code) = execCmdEx("mmdc -i " & inF & " -o " & outF,
                               options = {poEvalCommand})
    if code == 0 and fileExists(outF):
      return "Diagram rendered: " & outF
    else:
      return "```mermaid\n" & diagram & "\n```\n" &
             "(install mmdc via `npm i -g @mermaid-js/mermaid-cli` for SVG output)"
  except CatchableError:
    return "```mermaid\n" & diagram & "\n```"
  finally:
    try: removeFile(inF) except: discard

# ── inspect_image ─────────────────────────────────────────────────────────────

proc mimeFromExt(path: string): string =
  let ext = splitFile(path).ext.toLowerAscii()
  case ext
  of ".jpg", ".jpeg": "image/jpeg"
  of ".png":          "image/png"
  of ".gif":          "image/gif"
  of ".webp":         "image/webp"
  else:               "image/jpeg"

proc performInspectImage*(path, prompt: string;
                          completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    if not fileExists(path):
      return "Error: file not found: " & path
    let bytes    = readFile(path)
    let b64      = encode(bytes)
    let mime     = mimeFromExt(path)
    let dataUrl  = "data:" & mime & ";base64," & b64
    let question = if prompt.len > 0: prompt else: "Describe this image in detail."
    var h = newHistory()
    h.addUserWithImage(question, dataUrl)
    let req = buildPrompt("You are a vision assistant.", h, "")
    let resp = completeFn(req)
    if resp.isErr: return "Error: " & resp.error
    resp.value.text
  except Exception as e:
    "Error: " & e.msg

# ── todo_write ────────────────────────────────────────────────────────────────

proc applyTodoOps*(state: SessionState; ops: JsonNode): string {.gcsafe, raises: [].} =
  try:
    for op in ops:
      let opName = op.getOrDefault("op").getStr("")
      case opName
      of "create":
        let title = op.getOrDefault("title").getStr("(untitled)")
        let phase = op.getOrDefault("phase").getStr("backlog")
        let notes = op.getOrDefault("notes").getStr("")
        let id    = "todo-" & $state.todos.len
        let ph    = case phase
                    of "in_progress": phInProgress
                    of "completed":   phCompleted
                    else:             phBacklog
        state.todos.add(TodoItem(id: id, title: title, phase: ph, notes: notes))
      of "update":
        let id    = op.getOrDefault("id").getStr("")
        for i in 0 ..< state.todos.len:
          if state.todos[i].id == id:
            if op.hasKey("title"): state.todos[i].title = op["title"].getStr()
            if op.hasKey("notes"): state.todos[i].notes = op["notes"].getStr()
            if op.hasKey("phase"):
              state.todos[i].phase = case op["phase"].getStr()
                of "in_progress": phInProgress
                of "completed":   phCompleted
                else:             phBacklog
            break
      of "delete":
        let id = op.getOrDefault("id").getStr("")
        state.todos.keepItIf(it.id != id)
      else: discard
    # Format current list
    if state.todos.len == 0: return "(empty todo list)"
    var lines: seq[string] = @[]
    for t in state.todos:
      let mark = case t.phase
                 of phBacklog:    "[ ]"
                 of phInProgress: "[~]"
                 of phCompleted:  "[x]"
      var line = mark & " [" & t.id & "] " & t.title
      if t.notes.len > 0: line &= " — " & t.notes
      lines.add(line)
    lines.join("\n")
  except CatchableError as e:
    "Error: " & e.msg

# ── task / jobs ───────────────────────────────────────────────────────────────

proc performTask*(prompt, context: string;
                  completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  try:
    var h = newHistory()
    if context.len > 0: h.addUser("Context:\n" & context)
    h.addUser(prompt)
    let req  = buildPrompt("You are a focused AI assistant completing a specific subtask." &
                           " Be concise and direct.", h, "")
    let resp = completeFn(req)
    if resp.isErr: return "Task error: " & resp.error
    resp.value.text
  except Exception as e:
    "Task error: " & e.msg

proc nextJobId*(state: SessionState): string {.gcsafe, raises: [].} =
  let id = "job-" & $state.jobCounter
  inc state.jobCounter
  id

proc buildTaskStartedText*(jobId: string): string {.gcsafe, raises: [].} =
  "job_id=" & jobId & "\nstatus=running"

proc spawnTaskJob*(state: SessionState;
                   prompt, context: string;
                   completeFn: CompleteFn): string {.gcsafe, raises: [].} =
  proc runTaskJob(jobFuture: Future[string];
                  prompt, context: string;
                  completeFn: CompleteFn): Future[void] {.async, gcsafe.} =
    await sleepAsync(chronos.milliseconds(1))
    if not jobFuture.finished():
      jobFuture.complete(performTask(prompt, context, completeFn))

  let jobId = state.nextJobId()
  let jobFuture = newFuture[string]()
  state.jobs[jobId] = JobState(future: jobFuture, done: false, result: "")
  asyncSpawn runTaskJob(jobFuture, prompt, context, completeFn)
  jobId

# ── Main dispatcher ───────────────────────────────────────────────────────────

proc handledText(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOutput)

proc handledError(text: string): NativeToolResult {.gcsafe, raises: [].} =
  NativeToolResult(handled: true, text: text, resultKind: trkOperationalError)

func isOperationalErrorText(text: string): bool =
  text.startsWith("Error:") or
  text.startsWith("HTTP error ") or
  text.startsWith("Brave API error ")

proc handledOutcome(text: string): NativeToolResult {.gcsafe, raises: [].} =
  if isOperationalErrorText(text):
    handledError(text)
  else:
    handledText(text)

func toolWebRules(ctx: NativeCtx; toolName: string): seq[cfgTypes.WebAccessRule] =
  let cfg = cfgTypes.DonkeyConfig(
    webAllowlist: ctx.webAllowlist,
    toolWebPolicy: ctx.toolWebPolicy,
  )
  cfg.effectiveToolWebRules(toolName)

proc resolveToolPath(path, paddockDir: string): Result[string, string] {.gcsafe, raises: [].}

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
                           paddockDir: string): Result[ReadFileContext, string] {.gcsafe, raises: [].} =
  let pathResult = j.requireStringField("path")
  if pathResult.isErr:
    return err(pathResult.error)
  let resolvedPathResult = resolveToolPath(pathResult.value, paddockDir)
  if resolvedPathResult.isErr:
    return err(resolvedPathResult.error)
  ok(ReadFileContext(
    path: resolvedPathResult.value,
    startLine: max(1, j.getOrDefault("start_line").getInt(1)),
    maxLines: max(1, j.getOrDefault("max_lines").getInt(200)),
  ))

proc parseEditLines(node: JsonNode): Result[seq[string], string] {.gcsafe, raises: [].} =
  if node.isNil or node.kind == JNull:
    return ok(newSeq[string]())
  if node.kind != JArray:
    return err("Error: 'lines' must be an array of strings.")
  var lines: seq[string] = @[]
  for item in node:
    if item.kind != JString:
      return err("Error: 'lines' must be an array of strings.")
    lines.add(item.getStr())
  ok(lines)

proc parseEditKind(raw: string): Result[EditFileOpKind, string] {.gcsafe, raises: [].} =
  case raw
  of "replace": ok(efokReplace)
  of "append": ok(efokAppend)
  of "prepend": ok(efokPrepend)
  else: err("Error: unsupported edit op '" & raw & "'.")

proc parseOptionalAnchor(node: JsonNode; key: string): Result[Option[HashlineAnchor], string] {.gcsafe, raises: [].} =
  if not node.hasKey(key):
    return ok(none(HashlineAnchor))
  let raw = node.getOrDefault(key).getStr("")
  if raw.len == 0:
    return ok(none(HashlineAnchor))
  parseHashlineAnchor(raw) >>=
    proc(anchor: HashlineAnchor): Result[Option[HashlineAnchor], string] =
      ok(some(anchor))

proc parseEditFileOp(node: JsonNode): Result[EditFileOp, string] {.gcsafe, raises: [].} =
  let opKindResult = parseEditKind(node.getOrDefault("op").getStr(""))
  if opKindResult.isErr:
    return err(opKindResult.error)
  let posResult = parseOptionalAnchor(node, "pos")
  if posResult.isErr:
    return err(posResult.error)
  let stopResult = parseOptionalAnchor(node, "end")
  if stopResult.isErr:
    return err(stopResult.error)
  let linesResult = parseEditLines(node.getOrDefault("lines"))
  if linesResult.isErr:
    return err(linesResult.error)
  if opKindResult.value == efokReplace and posResult.value.isNone:
    return err("Error: replace edits require 'pos'.")
  if stopResult.value.isSome and posResult.value.isNone:
    return err("Error: 'end' requires 'pos'.")
  ok(EditFileOp(
    kind: opKindResult.value,
    pos: posResult.value,
    stop: stopResult.value,
    lines: linesResult.value,
  ))

proc parseEditFileContext*(j: JsonNode;
                           paddockDir: string): Result[EditFileContext, string] {.gcsafe, raises: [].} =
  let pathResult = j.requireStringField("path")
  if pathResult.isErr:
    return err(pathResult.error)
  let resolvedPathResult = resolveToolPath(pathResult.value, paddockDir)
  if resolvedPathResult.isErr:
    return err(resolvedPathResult.error)
  let editsNode = j.getOrDefault("edits")
  if editsNode.kind != JArray:
    return err("Error: 'edits' must be an array.")
  var edits: seq[EditFileOp] = @[]
  for item in editsNode:
    let editResult = parseEditFileOp(item)
    if editResult.isErr:
      return err(editResult.error)
    edits.add(editResult.value)
  ok(EditFileContext(path: resolvedPathResult.value, edits: edits))

proc parseFindContext*(j: JsonNode; paddockDir: string): Result[FindContext, string] {.gcsafe, raises: [].} =
  let pathResult = j.requireStringField("path")
  if pathResult.isErr:
    return err(pathResult.error)
  let resolvedPathResult = resolveToolPath(pathResult.value, paddockDir)
  if resolvedPathResult.isErr:
    return err(resolvedPathResult.error)
  ok(FindContext(
    path: resolvedPathResult.value,
    pattern: j.getOrDefault("pattern").getStr("*"),
    kind: j.getOrDefault("type").getStr("file"),
    max: j.getOrDefault("max").getInt(50),
  ))

proc parseGrepContext*(j: JsonNode; paddockDir: string): Result[GrepContext, string] {.gcsafe, raises: [].} =
  let patternResult = j.requireStringField("pattern")
  if patternResult.isErr:
    return err(patternResult.error)
  let pathResult = j.requireStringField("path")
  if pathResult.isErr:
    return err(pathResult.error)
  let resolvedPathResult = resolveToolPath(pathResult.value, paddockDir)
  if resolvedPathResult.isErr:
    return err(resolvedPathResult.error)
  ok(GrepContext(
    pattern: patternResult.value,
    path: resolvedPathResult.value,
    recursive: j.getOrDefault("recursive").getBool(true),
    max: j.getOrDefault("max").getInt(50),
  ))

proc parseFetchContext*(j: JsonNode; defaultMax: int): Result[FetchContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("url") >>=
    proc(url: string): Result[FetchContext, string] =
      ok(FetchContext(url: url, maxCh: j.getOrDefault("max_chars").getInt(defaultMax)))

proc parseWebSearchContext*(j: JsonNode): Result[WebSearchContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("query") >>=
    proc(query: string): Result[WebSearchContext, string] =
      ok(WebSearchContext(query: query, count: j.getOrDefault("count").getInt(5)))

proc parseCalcContext*(j: JsonNode): Result[CalcContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("expression") >>=
    proc(expression: string): Result[CalcContext, string] =
      ok(CalcContext(expression: expression))

proc parseMermaidContext*(j: JsonNode): Result[MermaidContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("diagram") >>=
    proc(diagram: string): Result[MermaidContext, string] =
      ok(MermaidContext(diagram: diagram))

proc parseInspectImageContext*(j: JsonNode): Result[InspectImageContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("path") >>=
    proc(path: string): Result[InspectImageContext, string] =
      ok(InspectImageContext(
        path: path,
        prompt: j.getOrDefault("prompt").getStr(""),
      ))

proc parseTaskContext*(j: JsonNode): Result[TaskContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("prompt") >>=
    proc(prompt: string): Result[TaskContext, string] =
      ok(TaskContext(
        prompt: prompt,
        context: j.getOrDefault("context").getStr(""),
      ))

proc parseAwaitContext*(j: JsonNode): Result[AwaitContext, string] {.gcsafe, raises: [].} =
  let ids = j.getOrDefault("job_ids")
  if ids.kind != JArray:
    return err("Error: 'job_ids' must be an array.")
  ok(AwaitContext(ids: ids.mapIt(it.getStr())))

proc parseFindingContext*(j: JsonNode): Result[FindingContext, string] {.gcsafe, raises: [].} =
  j.requireStringField("finding") >>=
    proc(finding: string): Result[FindingContext, string] =
      ok(FindingContext(finding: finding))

proc parseTodoOps*(j: JsonNode): Result[JsonNode, string] {.gcsafe, raises: [].} =
  let ops = j.getOrDefault("ops")
  if ops.kind != JArray:
    return err("Error: 'ops' must be an array.")
  ok(ops)

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

proc resolveToolPath(path, paddockDir: string): Result[string, string] {.gcsafe, raises: [].} =
  if path.len == 0 or paddockDir.len == 0:
    return ok(path)
  let resolvedPath = resolveInPaddock(path, paddockDir)
  if not inPaddock(resolvedPath, paddockDir):
    return err("Error: path outside paddock: " & path)
  ok(resolvedPath)

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
        state.jobs[id] = JobState(future: nil, done: true, result: "error — " & e.msg)
        lines.add(id & ": error — " & e.msg)
  handledOutcome(lines.join("\n"))

proc recordFinding(ctx: NativeCtx; findingCtx: FindingContext): NativeToolResult =
  ctx.log.info("[finding] " & findingCtx.finding)
  handledText("Finding recorded: " & findingCtx.finding)

proc executeLegacyNativeTool(tc: ToolCallRequest;
                             ctx: NativeCtx;
                             state: SessionState;
                             history: ConversationHistory;
                             j: JsonNode;
                            ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  case tc.name
  of ReminderToolName:
    let whenStr = j.getOrDefault("when").getStr("")
    let remMsg  = j.getOrDefault("message").getStr("")
    if whenStr.len == 0 or remMsg.len == 0:
      return handledError("Error: 'when' and 'message' are required.")
    let ts = parseWhen(whenStr, getTime().toUnix())
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
    let fetched = performFetch(
      ctx.http, url, maxCh, rules, ctx.webAllowlist, WebFetchToolName)
    return handledOutcome(fetched)

  else:
    return NativeToolResult(handled: false)

proc executeShellNativeTool(tc: ToolCallRequest;
                            ctx: NativeCtx;
                            state: SessionState;
                            history: ConversationHistory;
                            j: JsonNode;
                           ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  case tc.name
  of BashToolName:
    let bashCtx = parseBashContext(j).valueOr:
      return handledError(error)
    let r = sandboxBash(bashCtx.command, ctx.paddockDir,
                        ctx.sandboxMode, ctx.sandboxImage)
    return handledOutcome(r)

  of ReadFileToolName:
    let readCtx = parseReadFileContext(j, ctx.paddockDir).valueOr:
      return handledError(error)
    try:
      return handledText(renderHashlineSlice(
        readFile(readCtx.path),
        readCtx.startLine,
        readCtx.maxLines,
      ))
    except CatchableError as e:
      return handledError("Error: " & e.msg)

  of EditFileToolName:
    let editCtx = parseEditFileContext(j, ctx.paddockDir).valueOr:
      return handledError(error)
    try:
      let original = readFile(editCtx.path)
      let applyResult = applyEditFileOps(splitEditableLines(original), editCtx.edits).valueOr:
        return handledError(error)
      writeFile(editCtx.path, applyResult.join("\n"))
      return handledText("Edited " & editCtx.path &
                         " successfully. Re-read the file before additional edits.")
    except CatchableError as e:
      return handledError("Error: " & e.msg)

  of FindToolName:
    let findCtx = parseFindContext(j, ctx.paddockDir).valueOr:
      return handledError(error)
    let r = performFind(
      findCtx.path,
      findCtx.pattern,
      findCtx.kind,
      findCtx.max,
    )
    return handledOutcome(r)

  of GrepToolName:
    let grepCtx = parseGrepContext(j, ctx.paddockDir).valueOr:
      return handledError(error)
    let r = performGrep(
      grepCtx.pattern,
      grepCtx.path,
      grepCtx.recursive,
      grepCtx.max,
    )
    return handledOutcome(r)

  else:
    return NativeToolResult(handled: false)

proc executeWebNativeTool(tc: ToolCallRequest;
                          ctx: NativeCtx;
                          state: SessionState;
                          history: ConversationHistory;
                          j: JsonNode;
                         ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  case tc.name
  of FetchToolName:
    let fetchCtx = parseFetchContext(j, FetchDefaultMax).valueOr:
      return handledError(error)
    let rules = toolWebRules(ctx, FetchToolName)
    let r = performFetch(
      ctx.http, fetchCtx.url, fetchCtx.maxCh, rules, ctx.webAllowlist, FetchToolName)
    return handledOutcome(r)

  of WebSearchToolName:
    let searchCtx = parseWebSearchContext(j).valueOr:
      return handledError(error)
    let rules = toolWebRules(ctx, WebSearchToolName)
    let r = performWebSearch(
      searchCtx.query, searchCtx.count, ctx.braveApiKey, ctx.http, rules, ctx.webAllowlist)
    return handledOutcome(r)

  else:
    return NativeToolResult(handled: false)

proc executeUtilityNativeTool(tc: ToolCallRequest;
                              ctx: NativeCtx;
                              state: SessionState;
                              history: ConversationHistory;
                              j: JsonNode;
                             ): Future[NativeToolResult] {.async.} =
  discard state
  discard history
  case tc.name
  of CalcToolName:
    let calcCtx = parseCalcContext(j).valueOr:
      return handledError(error)
    var calcResult = ""
    try: calcResult = evalCalc(calcCtx.expression)
    except Exception as e: calcResult = "Error: " & e.msg
    return handledOutcome(calcResult)

  of RenderMermaidToolName:
    let mermaidCtx = parseMermaidContext(j).valueOr:
      return handledError(error)
    let r = performRenderMermaid(mermaidCtx.diagram)
    return handledOutcome(r)

  of InspectImageToolName:
    let inspectCtx = parseInspectImageContext(j).valueOr:
      return handledError(error)
    let r = performInspectImage(inspectCtx.path, inspectCtx.prompt, ctx.completeFn)
    return handledOutcome(r)

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
    let r = applyTodoOps(state, ops)
    return handledOutcome(r)

  of CheckpointToolName:
    return buildCheckpointResult(state)

  of RewindToolName:
    let rewindResult =
      parseRewindIndex(j, state.checkpoints.len) >>=
      proc(idx: int): Result[NativeToolResult, string] =
        buildRewindResult(state, idx)
    return rewindResult.valueOr:
      handledError(error)

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
  let categoryResult = await category.categoryHandler()(tc, ctx, state, history, j)
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
