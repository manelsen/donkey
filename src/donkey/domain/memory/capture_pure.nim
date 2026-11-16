## capture_pure — policy for the automatic per-turn memory capture.
##
## Decides whether a finished turn is worth appending to long-term memory and
## formats the entry. No I/O; the orchestrator owns the append.
##
## There is no minimum length on the user side: a short message is often a
## correction ("não, o prazo é sexta"), and dropping it leaves the wrong answer
## as the only record of the exchange. What is skipped instead is text with
## nothing to remember: greetings, bare acknowledgements, slash commands and
## operational failures.

import std/[strutils, unicode]

const
  AutoMemoryCaptureMaxChars* = 4000
  AutoMemoryTruncationMarker* = "\n[…truncated]"

  AutoMemorySkipNeedles* = [
    "não consigo acessar a web",
    "search isn't working",
    "ferramentas indisponíveis",
    "docker sandbox unavailable",
    "wasmtime not found",
    "não consigo criar arquivos",
    "limitations de escrita",
    "limitações de escrita",
    "the workspace appears to be empty",
    "no heartbeat.md found",
    "tool result's tool id",
  ]

  ## Compared after lowercasing and dropping everything that is not a letter,
  ## digit or single space. "sim"/"não" are deliberately absent: a bare yes or
  ## no is a decision.
  AutoMemoryTrivialUserTexts* = [
    "oi", "ola", "olá", "opa", "e ai", "e aí", "bom dia", "boa tarde",
    "boa noite", "ok", "okay", "blz", "beleza",
    "obrigado", "obrigada", "valeu", "vlw", "tchau", "ate mais", "até mais",
    "hi", "hello", "hey", "thanks", "thank you", "bye",
  ]

func lettersAndDigitsOnly(text: string): string =
  ## Lowercases and keeps letters, digits and single inner spaces, so that
  ## "Oi!", "ok." and "valeu 😊" compare equal to their bare words.
  var pendingSpace = false
  for r in text.runes:
    if r.isAlpha or (r.int >= ord('0') and r.int <= ord('9')):
      if pendingSpace and result.len > 0:
        result.add(' ')
      pendingSpace = false
      result.add($toLower(r))
    else:
      pendingSpace = true

func isTrivialUserText*(userText: string): bool =
  ## True for empty text, slash commands, and messages that are only a
  ## greeting, an acknowledgement, punctuation or emoji.
  let trimmed = userText.strip
  if trimmed.len == 0 or trimmed.startsWith("/"):
    return true
  let bare = lettersAndDigitsOnly(trimmed)
  bare.len == 0 or bare in AutoMemoryTrivialUserTexts

func isOperationalFailure*(responseText: string): bool =
  let lowered = unicode.toLower(responseText).strip
  if lowered.startsWith("desculpe, ocorreu um erro:") or
     lowered.startsWith("error: "):
    return true
  for needle in AutoMemorySkipNeedles:
    if lowered.contains(needle):
      return true
  false

func shouldSkipAutoMemoryCapture*(userText, responseText: string): bool =
  isTrivialUserText(userText) or responseText.strip.len == 0 or
    isOperationalFailure(responseText)

func clipAutoMemoryCapture*(text: string): string =
  ## Trims and bounds one side of the entry, never splitting a UTF-8 code
  ## point, and marks the cut so the reader knows text is missing.
  let trimmed = text.strip
  if trimmed.len <= AutoMemoryCaptureMaxChars:
    return trimmed
  var cut = AutoMemoryCaptureMaxChars - AutoMemoryTruncationMarker.len
  while cut > 0 and (ord(trimmed[cut]) and 0xC0) == 0x80:
    dec cut
  trimmed[0 ..< cut] & AutoMemoryTruncationMarker

func formatAutoMemoryEntry*(userText, responseText: string): string =
  "- **User:** " & clipAutoMemoryCapture(userText) & "\n" &
    "  **Response:** " & clipAutoMemoryCapture(responseText) & "\n"
