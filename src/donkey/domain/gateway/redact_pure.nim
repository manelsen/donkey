## Pure client-facing redaction.
##
## Error bodies and dashboard payloads leave the process through the HTTP
## gateway, so secrets that leaked into a provider message must not survive
## the trip. This is deliberately conservative: known bearer/API-key shapes are
## replaced regardless of context, then the result is clipped to a small,
## fixed budget.

import std/strutils

const
  RedactMaxChars* = 300
  RedactedPlaceholder* = "[redacted]"

func lowerAt(s: string; i: int; literal: string): bool =
  ## Case-insensitive prefix test at `i` without allocating a slice.
  if i < 0 or i + literal.len > s.len:
    return false
  for j in 0 ..< literal.len:
    if toLowerAscii(s[i + j]) != literal[j]:
      return false
  true

func isSecretSpace(c: char): bool =
  c in {' ', '\t', '\n', '\r', '\v', '\f'}

func isSecretValueChar(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
    (c >= '0' and c <= '9') or c in {'_', '-', '.', '~', '+', '/', '=', '%'}

func skipSecretValue(s: string; start: int): int =
  ## Consumes a secret value. A quoted value is consumed up to and including
  ## its closing quote: stopping at the quote would leave the secret itself in
  ## the output (`key="secret"` would become `key=[redacted]"secret"`).
  if start < s.len and s[start] in {'"', '\''}:
    let quote = s[start]
    var i = start + 1
    while i < s.len and s[i] != quote:
      inc i
    if i < s.len:
      return i + 1
    return i
  var i = start
  while i < s.len and isSecretValueChar(s[i]):
    inc i
  i

func namedSecretValueStart(s: string; i: int; name: string): int =
  ## Matches `name ["] [ws] (=|:) [ws] value` and returns the value start, or
  ## -1. The colon form exists for JSON (`"api_key": "value"`); prose such as
  ## "monkey: business" must not be mangled, so a colon only counts when the
  ## value is quoted.
  if not lowerAt(s, i, name):
    return -1
  var j = i + name.len
  while j < s.len and isSecretSpace(s[j]):
    inc j
  if j < s.len and s[j] in {'"', '\''}:
    inc j
  while j < s.len and isSecretSpace(s[j]):
    inc j
  if j >= s.len or (s[j] != '=' and s[j] != ':'):
    return -1
  let colon = s[j] == ':'
  inc j
  while j < s.len and isSecretSpace(s[j]):
    inc j
  if colon:
    if j >= s.len or s[j] notin {'"', '\''}:
      return -1
  j

## Lowercase on purpose: `lowerAt` compares against lowercased input, so an
## uppercase literal would never match.
const KnownSecretPrefixes = ["xoxb-", "xoxp-", "xoxa-", "ghp_", "gho_",
                             "ghu_", "ghs_", "github_pat_", "akia", "aiza",
                             "nvapi-"]

func prefixSecretAt(s: string; i: int): int =
  ## Length of a known token prefix starting at `i`, or 0. Case-insensitive,
  ## so an unusual spelling is over-redacted rather than leaked.
  for prefix in KnownSecretPrefixes:
    if lowerAt(s, i, prefix):
      return prefix.len
  0

func redactForClient*(text: string): string =
  ## Removes `Bearer <token>` (any whitespace run after `Bearer`),
  ## `sk-<key>`, `key = <value>` and `token = <value>` (optional spaces around
  ## `=`), then caps the result at `RedactMaxChars` bytes on a UTF-8 boundary.
  var buf = ""
  var i = 0
  while i < text.len:
    if lowerAt(text, i, "bearer"):
      var j = i + 6
      if j < text.len and isSecretSpace(text[j]):
        while j < text.len and isSecretSpace(text[j]):
          inc j
        buf.add(RedactedPlaceholder)
        i = skipSecretValue(text, j)
      else:
        buf.add(text[i])
        inc i
    elif lowerAt(text, i, "basic"):
      var j = i + 5
      if j < text.len and isSecretSpace(text[j]):
        while j < text.len and isSecretSpace(text[j]):
          inc j
        buf.add(RedactedPlaceholder)
        i = skipSecretValue(text, j)
      else:
        buf.add(text[i])
        inc i
    elif lowerAt(text, i, "sk-"):
      buf.add(RedactedPlaceholder)
      i = skipSecretValue(text, i + 3)
    elif prefixSecretAt(text, i) > 0:
      buf.add(RedactedPlaceholder)
      i = skipSecretValue(text, i + prefixSecretAt(text, i))
    else:
      let tokenStart = namedSecretValueStart(text, i, "token")
      let keyStart = namedSecretValueStart(text, i, "key")
      if tokenStart >= 0:
        buf.add("token=" & RedactedPlaceholder)
        i = skipSecretValue(text, tokenStart)
      elif keyStart >= 0:
        buf.add("key=" & RedactedPlaceholder)
        i = skipSecretValue(text, keyStart)
      else:
        buf.add(text[i])
        inc i

  if buf.len > RedactMaxChars:
    var endIdx = RedactMaxChars
    while endIdx > 0 and (ord(buf[endIdx]) and 0xC0) == 0x80:
      dec endIdx
    buf.setLen(endIdx)
  buf
