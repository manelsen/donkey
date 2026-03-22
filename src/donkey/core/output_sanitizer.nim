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

func isSecretToken(token: string): bool =
  ## Returns true if `token` is flagged by the secret scanner.
  (token |> scanForSecrets).len > 0

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
