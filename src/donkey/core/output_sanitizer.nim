## output_sanitizer — strip thought tags and mask secrets before user delivery.
##
## Used as the final pass on LLM responses before they are sent to the user,
## ensuring internal reasoning blocks and any accidentally leaked credentials
## are removed from the visible output.
##
## Pipeline topology (pipeops):
##   text |> stripThoughtTags              -- unary: remove <thinking> blocks
##   text |> maskSecrets                   -- unary: replace secret tokens
##   text |> cleanResponse                 -- unary: full sanitization pass
##   text |>-> stripTagPair("<x>", "</x>") -- last-arg: targeted tag removal
##
## clean_response pipeline:
##   text |> stripThoughtTags |> maskSecrets

import std/strutils
import ./pipeops
import ./security/secret_scan

# ── tag pairs removed by stripThoughtTags ─────────────────────────────────────

const ThoughtTagPairs = [
  ("<thinking>", "</thinking>"),
  ("<think>", "</think>"),
]

# ── tag stripping ──────────────────────────────────────────────────────────────

func stripTagPair*(open, close, text: string): string =
  ## Removes all occurrences of open…close blocks (case-sensitive).
  ## Content between the tags is discarded entirely.
  ## If a closing tag is missing, everything from the opening tag onward is dropped.
  ## Designed for |>-> piping: text |>-> stripTagPair("<thinking>", "</thinking>")
  var pos = 0
  while pos < text.len:
    let startIdx = text.find(open, pos)
    if startIdx < 0:
      result.add(text[pos .. ^1])
      break
    result.add(text[pos ..< startIdx])
    let closeIdx = text.find(close, startIdx + open.len)
    if closeIdx < 0:
      break  # no closing tag — strip everything after the open tag
    pos = closeIdx + close.len

func stripThoughtTags*(text: string): string =
  ## Removes all internal thought tag blocks from text.
  ## Strips <thinking>…</thinking> and <think>…</think> blocks.
  ## Designed for |> piping: text |> stripThoughtTags
  result = text
  for pair in ThoughtTagPairs:
    result = result |>-> stripTagPair(pair[0], pair[1])

# ── secret masking ─────────────────────────────────────────────────────────────

const MaskLabel = "[REDACTED]"

## Delimiter characters matching the tokenizer used in secret_scan.
const TokenDelimiters = {' ', '\t', '\n', '\r', '"', '\'', ',', ';',
                         '(', ')', '[', ']', '{', '}'}

func looksLikeStreamSecretToken(token: string): bool =
  ## True for a credential marker, including the value after `=` or `:`.
  looksLikeSecretPrefix(token) or looksLikeSecretPrefix(assignedValue(token))

func looksLikeAssignedSecret(token: string): bool =
  ## Final-response heuristic: a complete known marker after `=` or `:` on a
  ## credential-looking key. Avoids masking locale=sk-SK / x=AKIAN.
  let eq = token.find('=')
  let colon = token.find(':')
  let sep = if eq > 0: eq elif colon > 0: colon else: -1
  if sep <= 0:
    return false
  isContextKeyword(token[0 ..< sep]) and
    startsWithKnownSecretPrefix(token[sep + 1 .. ^1])

func isSecretToken(token: string): bool =
  ## Returns true if `token` is flagged by the secret scanner or carries a
  ## complete credential marker after an assignment separator.
  if (token |> scanForSecrets).len > 0:
    return true
  looksLikeAssignedSecret(token)

func maskSecrets*(text: string): string =
  ## Replaces secret-looking tokens in text with [REDACTED].
  ## Uses the same tokenizer as secret_scan for consistency.
  ## Designed for |> piping: text |> maskSecrets
  var current = ""
  for c in text:
    if c in TokenDelimiters:
      if current.len > 0:
        result.add(if isSecretToken(current): MaskLabel else: current)
        current = ""
      result.add(c)
    else:
      current.add(c)
  if current.len > 0:
    result.add(if isSecretToken(current): MaskLabel else: current)

# ── public API ─────────────────────────────────────────────────────────────────

func cleanResponse*(text: string): string =
  ## Strips thought tags and masks secrets in one pipeline pass.
  ## Main entry point for sanitizing LLM responses before user delivery.
  ## Pipeline: text |> stripThoughtTags |> maskSecrets
  text |> stripThoughtTags |> maskSecrets

# ── streaming ─────────────────────────────────────────────────────────────────

func openThoughtTagIndex(text: string): int =
  ## Index of an opening thought tag that has not been closed yet, or -1.
  ## Also catches a partial opening tag at the very end (e.g. "<thin").
  for pair in ThoughtTagPairs:
    var searchFrom = 0
    while true:
      let open = text.find(pair[0], searchFrom)
      if open < 0:
        break
      let close = text.find(pair[1], open + pair[0].len)
      if close < 0:
        return open
      searchFrom = close + pair[1].len

  let lt = text.rfind('<')
  let gt = text.rfind('>')
  if lt >= 0 and lt > gt:
    let suffix = text[lt .. ^1]
    for pair in ThoughtTagPairs:
      if pair[0].startsWith(suffix):
        return lt
  -1

func safeStreamPrefix*(text: string): string =
  ## Returns the portion of a streaming response that is safe to emit before
  ## the token/tag is complete. Holds back an unterminated thought tag and a
  ## trailing token that could be a credential (including after "Bearer").
  if text.len == 0:
    return ""

  let thoughtAt = openThoughtTagIndex(text)
  let head = if thoughtAt >= 0: text[0 ..< thoughtAt] else: text
  if head.len == 0:
    return ""

  var lastDelimiter = -1
  for i, c in head:
    if c in TokenDelimiters:
      lastDelimiter = i

  if lastDelimiter < 0:
    return if looksLikeStreamSecretToken(head): "" else: head

  let tail = head[lastDelimiter + 1 .. ^1]
  if tail.len > 0:
    var prevEnd = lastDelimiter
    while prevEnd > 0 and head[prevEnd - 1] in TokenDelimiters:
      dec prevEnd
    var prevStart = prevEnd
    while prevStart > 0 and head[prevStart - 1] notin TokenDelimiters:
      dec prevStart
    let previous = head[prevStart ..< prevEnd]
    if previous.toLowerAscii() == "bearer":
      return head[0 .. lastDelimiter]
    if looksLikeStreamSecretToken(tail):
      return head[0 .. lastDelimiter]

  head
