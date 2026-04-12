## text_tools.nim — hashline anchors, HTML stripping, and todo management.
##
## Hashline anchors provide stable, formatter-resilient line addressing for
## the edit_file tool.  stripHtml is used by the fetch tool.
## applyTodoOps manages the session todo list.

import std/[algorithm, json, strutils, options, sequtils]
import nimcrypto/sha2
import results
import ../session_state

# ── Hashline types ────────────────────────────────────────────────────────────

type
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

# ── SHA-256 helper ───────────────────────────────────────────────────────────

proc sha256hex(data: string): string {.gcsafe, raises: [].} =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())

# ── Hashline line processing ─────────────────────────────────────────────────

proc normalizeHashlineLine(line: string): string {.gcsafe, raises: [].} =
  line.replace("\r", "").strip()

proc computeLineHash*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  let normalized = normalizeHashlineLine(line)
  let seed =
    if normalized.anyIt(it.isAlphaNumeric): normalized
    else: normalized & ":" & $lineNum
  sha256hex(seed)[0 .. 3]

proc formatHashlineRef*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  $lineNum & "#" & computeLineHash(lineNum, line)

proc formatHashlineLine*(lineNum: int; line: string): string {.gcsafe, raises: [].} =
  formatHashlineRef(lineNum, line) & ":" & line

proc splitEditableLines*(content: string): seq[string] {.gcsafe, raises: [].} =
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

# ── HTML stripper (for fetch) ─────────────────────────────────────────────────

proc stripHtml*(html: string): string =
  result = newStringOfCap(html.len)
  var inTag    = false
  var inScript = false
  var i        = 0
  while i < html.len:
    if not inTag and not inScript and html[i] == '<':
      let rest = html[i + 1 ..< min(i + 8, html.len)].toLowerAscii()
      if rest.startsWith("script") or rest.startsWith("style"):
        inScript = true
      inTag = true
    elif inTag and html[i] == '>':
      inTag = false
      if inScript:
        let look = i.int - 8
        if look >= 0:
          let end8 = html[max(0, look) ..< i].toLowerAscii()
          if "/script" in end8 or "/style" in end8:
            inScript = false
      if not inScript:
        result.add(' ')
    elif not inTag and not inScript:
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
