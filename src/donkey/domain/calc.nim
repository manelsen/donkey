## calc.nim — pure arithmetic expression evaluator + glob matcher.
##
## evalCalc: +, -, *, /, %, ** (power), parentheses, unary ±.
## Literals: decimal (3.14, 42), hex (0xFF), binary (0b1010), octal (0o777).
## Returns result string or "Error: message".
##
## globMatch: simple * / ? glob. Used by the find tool.

import std/[math, strutils]
import ../core/pipeops

type
  ParseState = tuple[value: float, pos: int]

func skipWs(s: string; pos: int): int =
  result = pos
  while result < s.len and s[result] in {' ', '\t', '\r', '\n'}:
    inc result

func peek(s: string; pos: int): char =
  if pos < s.len: s[pos] else: '\0'

func parseBinaryDigits(s: string; pos: int): Result[ParseState, string] =
  var i = pos
  var value = 0
  var digits = 0
  while i < s.len and s[i] in {'0', '1'}:
    value = value * 2 + (ord(s[i]) - ord('0'))
    inc i
    inc digits
  if digits == 0:
    return err("invalid binary literal")
  ok((float(value), i))

func parseOctalDigits(s: string; pos: int): Result[ParseState, string] =
  var i = pos
  var value = 0
  var digits = 0
  while i < s.len and s[i] in {'0'..'7'}:
    value = value * 8 + (ord(s[i]) - ord('0'))
    inc i
    inc digits
  if digits == 0:
    return err("invalid octal literal")
  ok((float(value), i))

func parseHexDigits(s: string; pos: int): Result[ParseState, string] =
  var i = pos
  while i < s.len and s[i] in {'0'..'9', 'a'..'f', 'A'..'F'}:
    inc i
  if i == pos:
    return err("invalid hex literal")
  try:
    ok((float(parseHexInt(s[pos ..< i])), i))
  except ValueError:
    err("invalid hex literal")

func parseDecimalNumber(s: string; pos: int): Result[ParseState, string] =
  let start = pos
  var i = pos
  while i < s.len and s[i] in {'0'..'9'}:
    inc i
  if i < s.len and s[i] == '.':
    inc i
    while i < s.len and s[i] in {'0'..'9'}:
      inc i
  if i < s.len and s[i] in {'e', 'E'}:
    inc i
    if i < s.len and s[i] in {'+', '-'}:
      inc i
    while i < s.len and s[i] in {'0'..'9'}:
      inc i
  if i == start:
    return err("expected number at pos " & $pos)
  try:
    ok((parseFloat(s[start ..< i]), i))
  except ValueError:
    err("bad number: " & s[start ..< i])

func readNumber(s: string; pos: int): Result[ParseState, string] =
  if pos + 1 < s.len and s[pos] == '0':
    case s[pos + 1]
    of 'x', 'X':
      return parseHexDigits(s, pos + 2)
    of 'b', 'B':
      return parseBinaryDigits(s, pos + 2)
    of 'o', 'O':
      return parseOctalDigits(s, pos + 2)
    else:
      discard
  parseDecimalNumber(s, pos)

func parseExpr(s: string; pos: int): Result[ParseState, string]

func parsePrimary(s: string; pos: int): Result[ParseState, string] =
  let i = skipWs(s, pos)
  let c = peek(s, i)
  if c == '(':
    let inner = parseExpr(s, i + 1).valueOr:
      return err(error)
    let closePos = skipWs(s, inner.pos)
    if peek(s, closePos) != ')':
      return err("expected ')'")
    return ok((inner.value, closePos + 1))
  if c in {'0'..'9', '.'}:
    return readNumber(s, i)
  if c == '\0':
    return err("unexpected end of expression")
  err("unexpected '" & $c & "'")

func parseUnary(s: string; pos: int): Result[ParseState, string] =
  let i = skipWs(s, pos)
  case peek(s, i)
  of '-':
    let parsed = parseUnary(s, i + 1).valueOr:
      return err(error)
    ok((-parsed.value, parsed.pos))
  of '+':
    parseUnary(s, i + 1)
  else:
    parsePrimary(s, i)

func parsePower(s: string; pos: int): Result[ParseState, string] =
  let left = parseUnary(s, pos).valueOr:
    return err(error)
  let i = skipWs(s, left.pos)
  if i + 1 < s.len and s[i] == '*' and s[i + 1] == '*':
    let right = parsePower(s, i + 2).valueOr:
      return err(error)
    return ok((pow(left.value, right.value), right.pos))
  ok(left)

func parseTerm(s: string; pos: int): Result[ParseState, string] =
  var current = parsePower(s, pos).valueOr:
    return err(error)
  while true:
    let i = skipWs(s, current.pos)
    let c = peek(s, i)
    case c
    of '*':
      if i + 1 < s.len and s[i + 1] == '*':
        break
      let rhs = parsePower(s, i + 1).valueOr:
        return err(error)
      current = (current.value * rhs.value, rhs.pos)
    of '/':
      let rhs = parsePower(s, i + 1).valueOr:
        return err(error)
      if rhs.value == 0.0:
        return err("division by zero")
      current = (current.value / rhs.value, rhs.pos)
    of '%':
      let rhs = parsePower(s, i + 1).valueOr:
        return err(error)
      if rhs.value == 0.0:
        return err("modulo by zero")
      current = (floorMod(current.value, rhs.value), rhs.pos)
    else:
      break
  ok(current)

func parseExpr(s: string; pos: int): Result[ParseState, string] =
  var current = parseTerm(s, pos).valueOr:
    return err(error)
  while true:
    let i = skipWs(s, current.pos)
    case peek(s, i)
    of '+':
      let rhs = parseTerm(s, i + 1).valueOr:
        return err(error)
      current = (current.value + rhs.value, rhs.pos)
    of '-':
      let rhs = parseTerm(s, i + 1).valueOr:
        return err(error)
      current = (current.value - rhs.value, rhs.pos)
    else:
      break
  ok(current)

func formatCalcValue(value: float): string =
  if abs(value - round(value)) < 1e-9 and abs(value) < 9e18:
    $int64(round(value))
  else:
    $value

func evalCalc*(expr: string): string {.gcsafe.} =
  ## Evaluates a math expression. Returns result or "Error: ...".
  let trimmed = expr.strip()
  if trimmed.len == 0:
    return "Error: empty expression"
  let parsed = parseExpr(trimmed, 0).valueOr:
    return "Error: " & error
  let finalPos = skipWs(trimmed, parsed.pos)
  if finalPos < trimmed.len:
    return "Error: unexpected '" & $trimmed[finalPos] & "' at pos " & $finalPos
  formatCalcValue(parsed.value)

# ── Glob matcher ───────────────────────────────────────────────────────────────

func globMatch*(pattern, str: string): bool =
  ## Simple glob: * matches any sequence, ? matches one character.
  var si, pi = 0
  var starIdx = -1
  var match   = 0
  while si < str.len:
    if pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == str[si]):
      inc pi; inc si
    elif pi < pattern.len and pattern[pi] == '*':
      starIdx = pi; match = si; inc pi
    elif starIdx >= 0:
      pi = starIdx + 1; inc match; si = match
    else:
      return false
  while pi < pattern.len and pattern[pi] == '*': inc pi
  pi == pattern.len
