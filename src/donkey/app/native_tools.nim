## native_tools.nim — execution of all native (non-MCP) tools.
##
## executeNativeTool returns NativeToolResult:
##   handled=false  → not a native tool; orchestrator falls through to ToolAgent
##   handled=true   → result.text is the tool output
##   newHistory.isSome → orchestrator must replace history (rewind)
##   checkpointNow  → orchestrator must push current history to state.checkpoints
##
## Tool categories:
##   Shell   : bash, hashline, find, grep
##   Web     : fetch, web_search
##   Utility : calc, render_mermaid, inspect_image
##   Session : ask, todo_write, checkpoint, rewind
##   Agent   : task, submit_result, report_finding, cancel_job, await
##   Legacy  : schedule_reminder, current_time, web_fetch  (moved here from orchestrator)

import std/[json, osproc, os, strutils, base64, tables, sequtils, times, options, uri]
import chronos
import chronos/asyncsync
import nimcrypto/sha2
import ../core/pipeops
import ../core/log
import ../domain/message
import ../domain/agent_message
import ../domain/more_tools
import ../domain/builtin_tools
import ../domain/calc
import ../domain/reminder
import ../adapters/http/std_http
import ../ports/http as httpPort
import ../ports/provider
import ../config/types as cfgTypes
import ./sandbox
import ./session_state

# ── Result type ───────────────────────────────────────────────────────────────

type
  NativeToolResult* = object
    handled*:       bool
    text*:          string
    newHistory*:    Option[ConversationHistory]  ## set by rewind
    checkpointNow*: bool                         ## set by checkpoint

# ── Context ───────────────────────────────────────────────────────────────────

type
  NativeCtx* = object
    uid*:          UserId
    channel*:      ChannelKind
    outbox*:       AsyncQueue[OutboundMessage]
    inbox*:        AsyncQueue[AgentMessage]
    completeFn*:   CompleteFn
    braveApiKey*:  string
    tools*:        seq[ToolDescription]
    log*:          Logger
    paddockDir*:   string       ## agent workspace root; empty = unconstrained (tests only)
    sandboxMode*:  SandboxMode  ## bash isolation mode
    sandboxImage*: string       ## Docker image when sandboxMode = smDocker

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

# ── hashline ──────────────────────────────────────────────────────────────────

proc sha256hex(data: string): string {.gcsafe, raises: [].} =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())

proc performHashline*(input: string = ""; file: string = "";
                      line: int = 0): string {.gcsafe, raises: [].} =
  if file.len > 0:
    try:
      let content = readFile(file)
      if line > 0:
        let lines = content.splitLines()
        if line > lines.len:
          return "Error: file has " & $lines.len & " lines, requested " & $line
        return sha256hex(lines[line - 1])
      return sha256hex(content)
    except CatchableError as e:
      return "Error: " & e.msg
  elif input.len > 0:
    return sha256hex(input)
  else:
    return "Error: provide 'input' or 'file'"

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

proc performFetch*(url: string; maxCh: int): string {.gcsafe, raises: [].} =
  try:
    if isPrivateUrl(url):
      return "Error: private/internal addresses not allowed."
    let http = newStdHttpAdapter()
    var resp: Result[HttpResponse, string]
    {.cast(gcsafe).}: resp = http.get(url, @[])
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
                       apiKey: string): string {.gcsafe, raises: [].} =
  if apiKey.len == 0:
    return "Error: BRAVE_API_KEY not configured. Set the environment variable."
  try:
    let url     = BraveSearchUrl & "?q=" & encodeUrl(query) & "&count=" & $min(count, 20)
    let headers = @[
      ("X-Subscription-Token", apiKey),
      ("Accept",               "application/json"),
    ]
    let http = newStdHttpAdapter()
    var resp: Result[HttpResponse, string]
    {.cast(gcsafe).}:
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
  let inF   = "/tmp/donkey_mermaid_" & ts & ".mmd"
  let outF  = "/tmp/donkey_mermaid_" & ts & ".svg"
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

# ── Main dispatcher ───────────────────────────────────────────────────────────

proc executeNativeTool*(tc:      ToolCallRequest;
                        ctx:     NativeCtx;
                        state:   SessionState;
                        history: ConversationHistory;
                       ): Future[NativeToolResult] {.async.} =
  template handled(txt: string): NativeToolResult =
    NativeToolResult(handled: true, text: txt)

  let j = try: parseJson(tc.inputJson)
          except: newJObject()

  case tc.name

  # ── Legacy tools (moved from orchestrator) ──────────────────────────────────

  of ReminderToolName:
    let whenStr = j.getOrDefault("when").getStr("")
    let remMsg  = j.getOrDefault("message").getStr("")
    if whenStr.len == 0 or remMsg.len == 0:
      return handled("Error: 'when' and 'message' are required.")
    let ts = parseWhen(whenStr)
    # memory is not in NativeCtx — orchestrator handles this one directly
    return NativeToolResult(handled: false)  # fall through to orchestrator legacy path

  of CurrentTimeToolName:
    return handled(currentTimeResult())

  of WebFetchToolName:
    let url   = j.getOrDefault("url").getStr("")
    let maxCh = j.getOrDefault("max_chars").getInt(DefaultMaxChars)
    if url.len == 0: return handled("Error: 'url' is required.")
    if isPrivateUrl(url): return handled("Error: private addresses not allowed.")
    var fetched = ""
    {.cast(gcsafe).}: fetched = performFetch(url, maxCh)
    return handled(fetched)

  # ── Shell tools ─────────────────────────────────────────────────────────────

  of BashToolName:
    let cmd = j.getOrDefault("command").getStr("")
    if cmd.len == 0: return handled("Error: 'command' is required.")
    var r = ""
    {.cast(gcsafe).}: r = sandboxBash(cmd, ctx.paddockDir,
                                       ctx.sandboxMode, ctx.sandboxImage)
    return handled(r)

  of HashlineToolName:
    let input = j.getOrDefault("input").getStr("")
    let file  = j.getOrDefault("file").getStr("")
    let line  = j.getOrDefault("line").getInt(0)
    if file.len > 0 and ctx.paddockDir.len > 0 and not inPaddock(file, ctx.paddockDir):
      return handled("Error: path outside paddock: " & file)
    var r = ""
    {.cast(gcsafe).}: r = performHashline(input, file, line)
    return handled(r)

  of FindToolName:
    let path    = j.getOrDefault("path").getStr("")
    let pattern = j.getOrDefault("pattern").getStr("*")
    let kind    = j.getOrDefault("type").getStr("file")
    let max     = j.getOrDefault("max").getInt(50)
    if path.len == 0: return handled("Error: 'path' is required.")
    let resolvedPath =
      if ctx.paddockDir.len > 0:
        let rp = resolveInPaddock(path, ctx.paddockDir)
        if not inPaddock(rp, ctx.paddockDir):
          return handled("Error: path outside paddock: " & path)
        rp
      else:
        path
    var r = ""
    {.cast(gcsafe).}: r = performFind(resolvedPath, pattern, kind, max)
    return handled(r)

  of GrepToolName:
    let pattern   = j.getOrDefault("pattern").getStr("")
    let path      = j.getOrDefault("path").getStr("")
    let recursive = j.getOrDefault("recursive").getBool(true)
    let max       = j.getOrDefault("max").getInt(50)
    if pattern.len == 0: return handled("Error: 'pattern' is required.")
    if path.len == 0: return handled("Error: 'path' is required.")
    let resolvedPath =
      if ctx.paddockDir.len > 0:
        let rp = resolveInPaddock(path, ctx.paddockDir)
        if not inPaddock(rp, ctx.paddockDir):
          return handled("Error: path outside paddock: " & path)
        rp
      else:
        path
    var r = ""
    {.cast(gcsafe).}: r = performGrep(pattern, resolvedPath, recursive, max)
    return handled(r)

  # ── Web tools ───────────────────────────────────────────────────────────────

  of FetchToolName:
    let url   = j.getOrDefault("url").getStr("")
    let maxCh = j.getOrDefault("max_chars").getInt(FetchDefaultMax)
    if url.len == 0: return handled("Error: 'url' is required.")
    var r = ""
    {.cast(gcsafe).}: r = performFetch(url, maxCh)
    return handled(r)

  of WebSearchToolName:
    let query = j.getOrDefault("query").getStr("")
    let count = j.getOrDefault("count").getInt(5)
    if query.len == 0: return handled("Error: 'query' is required.")
    var r = ""
    {.cast(gcsafe).}: r = performWebSearch(query, count, ctx.braveApiKey)
    return handled(r)

  # ── Utility tools ────────────────────────────────────────────────────────────

  of CalcToolName:
    let expr = j.getOrDefault("expression").getStr("")
    if expr.len == 0: return handled("Error: 'expression' is required.")
    var calcResult = ""
    try: calcResult = evalCalc(expr)
    except Exception as e: calcResult = "Error: " & e.msg
    return handled(calcResult)

  of RenderMermaidToolName:
    let diagram = j.getOrDefault("diagram").getStr("")
    if diagram.len == 0: return handled("Error: 'diagram' is required.")
    var r = ""
    {.cast(gcsafe).}: r = performRenderMermaid(diagram)
    return handled(r)

  of InspectImageToolName:
    let path   = j.getOrDefault("path").getStr("")
    let prompt = j.getOrDefault("prompt").getStr("")
    if path.len == 0: return handled("Error: 'path' is required.")
    var r = ""
    {.cast(gcsafe).}: r = performInspectImage(path, prompt, ctx.completeFn)
    return handled(r)

  # ── Session tools ────────────────────────────────────────────────────────────

  of AskToolName:
    let question = j.getOrDefault("question").getStr("")
    if question.len == 0: return handled("Error: 'question' is required.")
    await ctx.outbox.put(OutboundMessage(
      userId:  ctx.uid,
      channel: ctx.channel,
      text:    question,
    ))
    let reply = await ctx.inbox.get()
    return handled(reply.payload)

  of TodoWriteToolName:
    let ops = j.getOrDefault("ops")
    if ops.kind != JArray: return handled("Error: 'ops' must be an array.")
    var r = ""
    {.cast(gcsafe).}: r = applyTodoOps(state, ops)
    return handled(r)

  of CheckpointToolName:
    return NativeToolResult(handled: true,
                            text:    "Checkpoint " & $state.checkpoints.len & " saved.",
                            checkpointNow: true)

  of RewindToolName:
    if state.checkpoints.len == 0:
      return handled("Error: no checkpoints saved.")
    let idx = j.getOrDefault("index").getInt(state.checkpoints.len - 1)
    if idx < 0 or idx >= state.checkpoints.len:
      return handled("Error: checkpoint index " & $idx & " out of range (0.." &
                     $(state.checkpoints.len - 1) & ").")
    let restored = state.checkpoints[idx]
    return NativeToolResult(handled: true,
                            text:    "Rewound to checkpoint " & $idx & ".",
                            newHistory: some(restored))

  # ── Agent coordination tools ─────────────────────────────────────────────────

  of TaskToolName:
    let prompt  = j.getOrDefault("prompt").getStr("")
    let context = j.getOrDefault("context").getStr("")
    if prompt.len == 0: return handled("Error: 'prompt' is required.")
    var r = ""
    {.cast(gcsafe).}: r = performTask(prompt, context, ctx.completeFn)
    return handled(r)

  of SubmitResultToolName:
    return handled(j.getOrDefault("result").getStr(""))

  of ReportFindingToolName:
    let finding = j.getOrDefault("finding").getStr("")
    ctx.log.info("[finding] " & finding)
    return handled("Finding recorded: " & finding)

  of CancelJobToolName:
    let jobId = j.getOrDefault("job_id").getStr("")
    if jobId notin state.jobs:
      return handled("Error: job '" & jobId & "' not found.")
    let job = state.jobs[jobId]
    if not job.done and not job.future.isNil:
      job.future.cancelSoon()
      state.jobs[jobId] = JobState(done: true, result: "(cancelled)")
    return handled("Job " & jobId & " cancelled.")

  of AwaitToolName:
    let ids = j.getOrDefault("job_ids")
    if ids.kind != JArray: return handled("Error: 'job_ids' must be an array.")
    var lines: seq[string] = @[]
    for idNode in ids:
      let id = idNode.getStr()
      if id notin state.jobs:
        lines.add(id & ": not found")
        continue
      var job = state.jobs[id]
      if job.done:
        lines.add(id & ": " & job.result)
      else:
        try:
          let r = await job.future
          state.jobs[id] = JobState(done: true, result: r)
          lines.add(id & ": " & r)
        except CancelledError:
          lines.add(id & ": cancelled")
        except CatchableError as e:
          lines.add(id & ": error — " & e.msg)
    return handled(lines.join("\n"))

  else:
    return NativeToolResult(handled: false)
