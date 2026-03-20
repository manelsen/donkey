## calc.nim — pure arithmetic expression evaluator + glob matcher.
##
## evalCalc: +, -, *, /, %, ** (power), parentheses, unary ±.
## Literals: decimal (3.14, 42), hex (0xFF), binary (0b1010), octal (0o777).
## Returns result string or "Error: message".
##
## globMatch: simple * / ? glob. Used by the find tool.

import std/[math, strutils]

type CalcError* = object of ValueError

# ── Parser internals ───────────────────────────────────────────────────────────

type Parser = object
  s:   string
  pos: int

proc peek(p: Parser): char {.inline.} =
  if p.pos < p.s.len: p.s[p.pos] else: '\0'

proc eat(p: var Parser): char {.discardable, inline.} =
  result = p.s[p.pos]; inc p.pos

proc skipWs(p: var Parser) =
  while p.pos < p.s.len and p.s[p.pos] in {' ', '\t', '\r', '\n'}:
    inc p.pos

proc readNumber(p: var Parser): float =
  let start = p.pos
  if p.pos + 1 < p.s.len and p.s[p.pos] == '0':
    case p.s[p.pos + 1]
    of 'x', 'X':
      p.pos += 2
      let hs = p.pos
      while p.pos < p.s.len and p.s[p.pos] in {'0'..'9','a'..'f','A'..'F'}:
        inc p.pos
      if p.pos == hs: raise newException(CalcError, "invalid hex literal")
      return float(parseHexInt(p.s[hs ..< p.pos]))
    of 'b', 'B':
      p.pos += 2
      var v, n = 0
      while p.pos < p.s.len and p.s[p.pos] in {'0','1'}:
        v = v * 2 + (ord(p.s[p.pos]) - ord('0')); inc p.pos; inc n
      if n == 0: raise newException(CalcError, "invalid binary literal")
      return float(v)
    of 'o', 'O':
      p.pos += 2
      var v, n = 0
      while p.pos < p.s.len and p.s[p.pos] in {'0'..'7'}:
        v = v * 8 + (ord(p.s[p.pos]) - ord('0')); inc p.pos; inc n
      if n == 0: raise newException(CalcError, "invalid octal literal")
      return float(v)
    else: discard
  while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
  if p.pos < p.s.len and p.s[p.pos] == '.':
    inc p.pos
    while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
  if p.pos < p.s.len and p.s[p.pos] in {'e','E'}:
    inc p.pos
    if p.pos < p.s.len and p.s[p.pos] in {'+','-'}: inc p.pos
    while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
  if p.pos == start: raise newException(CalcError, "expected number at pos " & $p.pos)
  try: parseFloat(p.s[start ..< p.pos])
  except ValueError: raise newException(CalcError, "bad number: " & p.s[start ..< p.pos])

proc parseExpr(p: var Parser): float   # forward decl

proc parsePrimary(p: var Parser): float =
  p.skipWs()
  if p.peek() == '(':
    discard p.eat()
    result = p.parseExpr()
    p.skipWs()
    if p.peek() == ')': discard p.eat()
    else: raise newException(CalcError, "expected ')'")
  elif p.peek() in {'0'..'9', '.'}:
    result = p.readNumber()
  else:
    let c = p.peek()
    if c == '\0': raise newException(CalcError, "unexpected end of expression")
    raise newException(CalcError, "unexpected '" & $c & "'")

proc parseUnary(p: var Parser): float =
  p.skipWs()
  case p.peek()
  of '-': discard p.eat(); return -p.parseUnary()
  of '+': discard p.eat(); return p.parseUnary()
  else:   return p.parsePrimary()

proc parsePower(p: var Parser): float =
  result = p.parseUnary()
  p.skipWs()
  if p.pos + 1 < p.s.len and p.s[p.pos] == '*' and p.s[p.pos + 1] == '*':
    p.pos += 2
    result = pow(result, p.parsePower())   # right-associative

proc parseTerm(p: var Parser): float =
  result = p.parsePower()
  while true:
    p.skipWs()
    let c = p.peek()
    if c == '*' and not (p.pos + 1 < p.s.len and p.s[p.pos + 1] == '*'):
      discard p.eat(); result = result * p.parsePower()
    elif c == '/':
      discard p.eat()
      let d = p.parsePower()
      if d == 0.0: raise newException(CalcError, "division by zero")
      result = result / d
    elif c == '%':
      discard p.eat()
      let d = p.parsePower()
      if d == 0.0: raise newException(CalcError, "modulo by zero")
      result = floorMod(result, d)
    else: break

proc parseExpr(p: var Parser): float =
  result = p.parseTerm()
  while true:
    p.skipWs()
    case p.peek()
    of '+': discard p.eat(); result = result + p.parseTerm()
    of '-': discard p.eat(); result = result - p.parseTerm()
    else:   break

proc evalCalc*(expr: string): string {.gcsafe.} =
  ## Evaluates a math expression. Returns result or "Error: ...".
  if expr.strip().len == 0: return "Error: empty expression"
  var p = Parser(s: expr.strip(), pos: 0)
  try:
    var v = 0.0
    {.cast(gcsafe).}: v = p.parseExpr()
    p.skipWs()
    if p.pos < p.s.len:
      return "Error: unexpected '" & $p.s[p.pos] & "' at pos " & $p.pos
    if abs(v - round(v)) < 1e-9 and abs(v) < 9e18:
      return $int64(round(v))
    else:
      return $v
  except CalcError as e:
    return "Error: " & e.msg
  except ValueError as e:
    return "Error: " & e.msg

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
