## A TOML parser for the subset the configuration uses, read straight from a
## string: no std/streams and no global state, so it is gcsafe and callable
## from any thread.
##
## Supported: comments, `[a.b]` tables, `[[a]]` arrays of tables, bare,
## quoted and dotted keys, basic and literal strings (also multiline),
## integers (with `_`), floats, booleans, arrays (nested, multiline, trailing
## comma, comments inside) and inline tables. Dates and times are not; they
## are rejected like any other invalid value. Errors raise `TomlError` with
## the line number.
##
## The value API mirrors the part of parsetoml the code used (`kind`,
## `getStr`, `getInt`, `getBool`, `getFloat`, `getElems`, `hasKey`, `[]`,
## `tableVal`), so callers changed only their import.

import std/[strutils, tables, unicode]
export tables  ## callers iterate `tableVal.pairs`

type
  TomlError* = object of CatchableError

  TomlValueKind* {.pure.} = enum
    None, String, Int, Float, Bool, Array, Table

  TomlValueRef* = ref TomlValue
  TomlTableRef* = OrderedTableRef[string, TomlValueRef]

  TomlOrigin = enum
    ## How a table or array came to be, which decides what may extend it.
    toImplicit  ## parent created on the way to a header or dotted key
    toHeader    ## defined by a `[header]` or as a `[[header]]` element
    toDotted    ## defined by a dotted key (`a.b = 1`)
    toInline    ## an inline table `{...}`: closed once written
    toStatic    ## an array value `[...]`: closed once written
    toAot       ## an array of tables, extended by `[[header]]`

  TomlValue* = object
    origin: TomlOrigin
    case kind*: TomlValueKind
    of TomlValueKind.None: discard
    of TomlValueKind.String: stringVal*: string
    of TomlValueKind.Int: intVal*: int64
    of TomlValueKind.Float: floatVal*: float64
    of TomlValueKind.Bool: boolVal*: bool
    of TomlValueKind.Array: arrayVal*: seq[TomlValueRef]
    of TomlValueKind.Table: tableVal*: TomlTableRef

# ── values ────────────────────────────────────────────────────────────────────

func newTable(): TomlValueRef =
  TomlValueRef(kind: TomlValueKind.Table, tableVal: newOrderedTable[string, TomlValueRef]())

func getStr*(v: TomlValueRef; default = ""): string =
  if v != nil and v.kind == TomlValueKind.String: v.stringVal else: default

func getInt*(v: TomlValueRef; default = 0): int =
  if v != nil and v.kind == TomlValueKind.Int: int(v.intVal) else: default

func getFloat*(v: TomlValueRef; default = 0.0): float =
  if v == nil: default
  elif v.kind == TomlValueKind.Float: v.floatVal
  elif v.kind == TomlValueKind.Int: float(v.intVal)
  else: default

func getBool*(v: TomlValueRef; default = false): bool =
  if v != nil and v.kind == TomlValueKind.Bool: v.boolVal else: default

func getElems*(v: TomlValueRef): seq[TomlValueRef] =
  if v != nil and v.kind == TomlValueKind.Array: v.arrayVal else: @[]

func hasKey*(v: TomlValueRef; key: string): bool =
  v != nil and v.kind == TomlValueKind.Table and v.tableVal.hasKey(key)

func getOrDefault*(v: TomlValueRef; key: string): TomlValueRef =
  ## The value under `key`, or nil (every getter accepts nil).
  if v.hasKey(key): v.tableVal[key] else: nil

func `[]`*(v: TomlValueRef; key: string): TomlValueRef =
  ## Raises KeyError for a missing key or a value that is not a table.
  if v == nil or v.kind != TomlValueKind.Table:
    raise newException(KeyError, "not a table: " & key)
  v.tableVal[key]

func len*(v: TomlValueRef): int =
  if v == nil: 0
  elif v.kind == TomlValueKind.Table: v.tableVal.len
  elif v.kind == TomlValueKind.Array: v.arrayVal.len
  elif v.kind == TomlValueKind.String: v.stringVal.len
  else: 0

# ── lexer state ───────────────────────────────────────────────────────────────

type Parser = object
  src:  string
  pos:  int
  line: int

func fail(p: Parser; msg: string) {.noreturn.} =
  raise newException(TomlError, "toml line " & $p.line & ": " & msg)

func atEnd(p: Parser): bool = p.pos >= p.src.len
func peek(p: Parser; ahead = 0): char =
  if p.pos + ahead < p.src.len: p.src[p.pos + ahead] else: '\0'

func advance(p: var Parser) =
  if p.src[p.pos] == '\n': inc p.line
  inc p.pos

func skipSpaces(p: var Parser) =
  while not p.atEnd and p.peek in {' ', '\t'}: p.advance()

func skipComment(p: var Parser) =
  if p.peek == '#':
    while not p.atEnd and p.peek != '\n': p.advance()

func skipBlank(p: var Parser) =
  ## Spaces, newlines and comments (inside arrays and between statements).
  while not p.atEnd:
    if p.peek in {' ', '\t', '\r', '\n'}: p.advance()
    elif p.peek == '#': p.skipComment()
    else: break

func expectLineEnd(p: var Parser) =
  p.skipSpaces()
  p.skipComment()
  if p.peek == '\r': p.advance()
  if not p.atEnd:
    if p.peek != '\n': p.fail("unexpected '" & $p.peek & "' after value")
    p.advance()

# ── strings ───────────────────────────────────────────────────────────────────

func startsAt(p: Parser; s: string): bool = p.src.continuesWith(s, p.pos)

func parseEscape(p: var Parser; into: var string) =
  p.advance()  # the backslash
  if p.atEnd: p.fail("unterminated escape")
  let c = p.peek
  p.advance()
  case c
  of 'b': into.add '\b'
  of 't': into.add '\t'
  of 'n': into.add '\n'
  of 'f': into.add '\f'
  of 'r': into.add '\r'
  of '"': into.add '"'
  of '\\': into.add '\\'
  of 'u', 'U':
    let width = if c == 'u': 4 else: 8
    if p.pos + width > p.src.len: p.fail("short unicode escape")
    let hex = p.src[p.pos ..< p.pos + width]
    var code: int
    try: code = parseHexInt(hex)
    except ValueError: p.fail("bad unicode escape \\" & c & hex)
    for _ in 0 ..< width: p.advance()
    into.add $Rune(code)
  else:
    p.fail("unknown escape \\" & c)

func parseBasicString(p: var Parser): string =
  if p.startsAt("\"\"\""):
    for _ in 0 ..< 3: p.advance()
    if p.peek == '\n': p.advance()
    elif p.startsAt("\r\n"): p.advance(); p.advance()
    while true:
      if p.atEnd: p.fail("unterminated multiline string")
      if p.startsAt("\"\"\""):
        ## Up to two quotes right before the delimiter are content.
        var run = 0
        while run < 5 and p.peek(run) == '"': inc run
        for _ in 0 ..< run - 3: result.add '"'
        for _ in 0 ..< run: p.advance()
        return
      if p.peek == '\\':
        if p.peek(1) in {'\n', '\r', ' ', '\t'}:
          ## Line-ending backslash: only whitespace may follow it on the
          ## line; then the newline and the next line's indentation go.
          p.advance()
          while not p.atEnd and p.peek in {' ', '\t'}: p.advance()
          if not (p.peek == '\n' or p.startsAt("\r\n")):
            p.fail("a line-ending backslash must end the line")
          while not p.atEnd and p.peek in {' ', '\t', '\r', '\n'}: p.advance()
        else:
          p.parseEscape(result)
      else:
        result.add p.peek
        p.advance()
  p.advance()  # opening quote
  while true:
    if p.atEnd or p.peek == '\n': p.fail("unterminated string")
    if p.peek == '"':
      p.advance()
      return
    if p.peek == '\\': p.parseEscape(result)
    else:
      result.add p.peek
      p.advance()

func parseLiteralString(p: var Parser): string =
  if p.startsAt("'''"):
    for _ in 0 ..< 3: p.advance()
    if p.peek == '\n': p.advance()
    elif p.startsAt("\r\n"): p.advance(); p.advance()
    while true:
      if p.atEnd: p.fail("unterminated multiline literal string")
      if p.startsAt("'''"):
        var run = 0
        while run < 5 and p.peek(run) == '\'': inc run
        for _ in 0 ..< run - 3: result.add '\''
        for _ in 0 ..< run: p.advance()
        return
      result.add p.peek
      p.advance()
  p.advance()
  while true:
    if p.atEnd or p.peek == '\n': p.fail("unterminated literal string")
    if p.peek == '\'':
      p.advance()
      return
    result.add p.peek
    p.advance()

# ── keys ──────────────────────────────────────────────────────────────────────

const BareKeyChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}

func parseKeyPart(p: var Parser): string =
  p.skipSpaces()
  case p.peek
  of '"': result = p.parseBasicString()
  of '\'': result = p.parseLiteralString()
  else:
    while not p.atEnd and p.peek in BareKeyChars:
      result.add p.peek
      p.advance()
    if result.len == 0: p.fail("expected a key")
  p.skipSpaces()

func parseKey(p: var Parser): seq[string] =
  ## A possibly dotted key: `a`, `"quoted key"`, `a.b."c"`.
  result.add p.parseKeyPart()
  while p.peek == '.':
    p.advance()
    result.add p.parseKeyPart()

# ── values ────────────────────────────────────────────────────────────────────

func parseValue(p: var Parser): TomlValueRef

func parseNumberOrBool(p: var Parser): TomlValueRef =
  var word = ""
  while not p.atEnd and p.peek notin {' ', '\t', '\r', '\n', ',', ']', '}', '#'}:
    word.add p.peek
    p.advance()
  case word
  of "true": return TomlValueRef(kind: TomlValueKind.Bool, boolVal: true)
  of "false": return TomlValueRef(kind: TomlValueKind.Bool, boolVal: false)
  of "": p.fail("expected a value")
  else: discard
  ## Each `_` must sit between two digits of the number's base.
  let body = if word.len > 0 and word[0] in {'+', '-'}: word[1 .. ^1] else: word
  let allowed =
    if body.startsWith("0x"): HexDigits
    elif body.startsWith("0o") or body.startsWith("0b"): Digits
    else: Digits
  for i, c in word:
    if c == '_' and (i == 0 or i == word.high or
                     word[i - 1] notin allowed or word[i + 1] notin allowed):
      p.fail("misplaced '_' in '" & word & "'")
  let digits = word.replace("_", "")
  if digits.len == 0 or digits[^1] == '.' or (digits.len > 0 and digits[0] == '.'):
    p.fail("invalid value '" & word & "'")
  try:
    if digits.startsWith("0x"):
      return TomlValueRef(kind: TomlValueKind.Int, intVal: fromHex[int64](digits[2 .. ^1]))
    if digits.startsWith("0o"):
      return TomlValueRef(kind: TomlValueKind.Int, intVal: fromOct[int64](digits[2 .. ^1]))
    if digits.startsWith("0b"):
      return TomlValueRef(kind: TomlValueKind.Int, intVal: fromBin[int64](digits[2 .. ^1]))
    if digits.contains({'.', 'e', 'E'}) or digits in ["inf", "+inf", "-inf", "nan", "+nan", "-nan"]:
      return TomlValueRef(kind: TomlValueKind.Float, floatVal: parseFloat(digits))
    return TomlValueRef(kind: TomlValueKind.Int, intVal: parseBiggestInt(digits))
  except ValueError:
    p.fail("invalid value '" & word & "'")

func parseArray(p: var Parser): TomlValueRef =
  result = TomlValueRef(kind: TomlValueKind.Array, origin: toStatic)
  p.advance()  # [
  while true:
    p.skipBlank()
    if p.atEnd: p.fail("unterminated array")
    if p.peek == ']':
      p.advance()
      return
    result.arrayVal.add p.parseValue()
    p.skipBlank()
    if p.peek == ',':
      p.advance()
    elif p.peek != ']':
      p.fail("expected ',' or ']' in array")

func setPath(p: Parser; table: TomlValueRef; path: seq[string];
             value: TomlValueRef)

func closeInline(v: TomlValueRef) =
  ## Marks an inline table and every table built inside it as closed.
  if v.kind == TomlValueKind.Table:
    v.origin = toInline
    for child in v.tableVal.values: closeInline(child)

func parseInlineTable(p: var Parser): TomlValueRef =
  result = newTable()
  p.advance()  # {
  p.skipSpaces()
  if p.peek == '}':
    p.advance()
    closeInline(result)
    return
  while true:
    let key = p.parseKey()
    if p.peek != '=': p.fail("expected '=' in inline table")
    p.advance()
    p.skipSpaces()
    p.setPath(result, key, p.parseValue())
    p.skipSpaces()
    if p.peek == ',':
      p.advance()
    elif p.peek == '}':
      p.advance()
      closeInline(result)
      return
    else:
      p.fail("expected ',' or '}' in inline table")

func parseValue(p: var Parser): TomlValueRef =
  p.skipSpaces()
  case p.peek
  of '"': TomlValueRef(kind: TomlValueKind.String, stringVal: p.parseBasicString())
  of '\'': TomlValueRef(kind: TomlValueKind.String, stringVal: p.parseLiteralString())
  of '[': p.parseArray()
  of '{': p.parseInlineTable()
  else: p.parseNumberOrBool()

# ── tables ────────────────────────────────────────────────────────────────────

func childTable(p: Parser; table: TomlValueRef; key: string;
                origin = toImplicit): TomlValueRef =
  ## The table under `key`, created (with `origin`) when missing. Into an
  ## array of tables it descends into the last element, as TOML headers do.
  ## Inline tables and static arrays are closed.
  if not table.tableVal.hasKey(key):
    let child = newTable()
    child.origin = origin
    table.tableVal[key] = child
    return child
  let existing = table.tableVal[key]
  case existing.kind
  of TomlValueKind.Table:
    if existing.origin == toInline:
      p.fail("inline table '" & key & "' cannot be extended")
    existing
  of TomlValueKind.Array:
    if existing.origin != toAot or existing.arrayVal.len == 0:
      p.fail("'" & key & "' is not an array of tables")
    existing.arrayVal[^1]
  else:
    p.fail("'" & key & "' is already a value")

func setPath(p: Parser; table: TomlValueRef; path: seq[string];
             value: TomlValueRef) =
  ## A dotted key defines its intermediate tables; it may extend tables it
  ## defined itself, never one defined by a header.
  var target = table
  for i, part in path[0 ..< path.len - 1]:
    let known = target.tableVal.hasKey(part)
    target = p.childTable(target, part, toDotted)
    if known and target.origin == toHeader:
      p.fail("table '" & path[0 .. i].join(".") & "' is already defined")
    if target.origin == toImplicit:
      target.origin = toDotted  ## a dotted key defines what it passes through
  let last = path[^1]
  if target.tableVal.hasKey(last):
    p.fail("duplicate key '" & path.join(".") & "'")
  target.tableVal[last] = value

func parseToml*(text: string): TomlValueRef =
  ## Parses a TOML document; raises TomlError on invalid input.
  var p = Parser(src: text, line: 1)
  result = newTable()
  var current = result
  while true:
    p.skipBlank()
    if p.atEnd: break
    if p.startsAt("[["):
      p.advance(); p.advance()
      let path = p.parseKey()
      if not p.startsAt("]]"): p.fail("expected ']]'")
      p.advance(); p.advance()
      var parent = result
      for part in path[0 ..< path.len - 1]:
        parent = p.childTable(parent, part)
      let last = path[^1]
      if not parent.tableVal.hasKey(last):
        parent.tableVal[last] = TomlValueRef(kind: TomlValueKind.Array, origin: toAot)
      let arr = parent.tableVal[last]
      if arr.kind != TomlValueKind.Array or arr.origin != toAot:
        p.fail("'" & last & "' is not an array of tables")
      current = newTable()
      current.origin = toHeader
      arr.arrayVal.add current
      p.expectLineEnd()
    elif p.peek == '[':
      p.advance()
      let path = p.parseKey()
      if p.peek != ']': p.fail("expected ']'")
      p.advance()
      current = result
      for part in path:
        current = p.childTable(current, part)
      if current.origin in {toHeader, toDotted}:
        p.fail("table '" & path.join(".") & "' is already defined")
      current.origin = toHeader
      p.expectLineEnd()
    else:
      let key = p.parseKey()
      if p.peek != '=': p.fail("expected '=' after key")
      p.advance()
      p.skipSpaces()
      if p.atEnd or p.peek in {'\n', '\r', '#'}: p.fail("missing value")
      p.setPath(current, key, p.parseValue())
      p.expectLineEnd()

proc parseTomlFile*(path: string): TomlValueRef =
  ## Reads and parses a file; raises IOError or TomlError.
  parseToml(readFile(path))
