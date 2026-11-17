## telegram_policy.nim — outbound policies derived from the Bot API behavior.
##
## Pure functions only: the adapter decides when to call them, this module
## decides what the API contract requires.

import std/[strutils, unicode]
import ./telegram_split

func isEditNoopError*(message: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 7ac9088d5c; see
  ## docs/hermes-mining/telegram/CASES.md#tg-002
  ##
  ## editMessageText answers 400 "message is not modified" when the new text is
  ## identical to the current one. The message is already what the caller
  ## wanted, so this is success, not a failure to retry.
  message.toLowerAscii().contains("message is not modified")

func isMissingReplyAnchorError*(message: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix b60cfd6ce6; see
  ## docs/hermes-mining/telegram/CASES.md#tg-005
  ##
  ## Replying to a message that was deleted answers 400 "message to be replied
  ## not found". The answer is still valid; only the anchor is gone.
  let lower = message.toLowerAscii()
  lower.contains("to be replied not found") or
    lower.contains("reply message not found")

func shouldSkipOutboundText*(text: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 83dec2b3ec; see
  ## docs/hermes-mining/telegram/CASES.md#tg-006
  ##
  ## sendMessage refuses empty or whitespace-only text with 400 "message text
  ## is empty". Skipping the call keeps the turn from failing on nothing.
  text.strip.len == 0

func clipCaption*(text: string; limit = 1024): string =
  ## Behavior derived from hermes-agent (MIT) fix f828b087e7; see
  ## docs/hermes-mining/telegram/CASES.md#tg-007
  ##
  ## The media caption limit (1024) is smaller than the message body limit
  ## (4096). Clipping on a character boundary keeps the upload valid instead of
  ## letting the API refuse the whole media message.
  if limit <= 0:
    return ""
  var count = 0
  for _ in text.runes: inc count
  if count <= limit:
    return text
  var clipped = ""
  var kept = 0
  for r in text.runes:
    if kept + 1 > limit - 1:
      break
    clipped.add($r)
    inc kept
  clipped & "…"

func planEditChunks*(text: string; limit = 4096): seq[string] =
  ## Behavior derived from hermes-agent (MIT) fix bf1f40996f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-008
  ##
  ## editMessageText has the same 4096-unit limit as sendMessage. The first
  ## chunk replaces the current message; the rest must be delivered as new
  ## messages, or the tail is silently lost.
  splitForTelegram(text, limit)

func callbackDataError*(data: string): string =
  ## Behavior derived from hermes-agent (MIT) fix 6fb57bc9cf; see
  ## docs/hermes-mining/telegram/CASES.md#tg-009
  ##
  ## Telegram rejects a button whose callback_data is empty or exceeds 64
  ## bytes, and it rejects the whole message. Returning the reason keeps this
  ## pure; the adapter turns it into its own error.
  if data.len == 0:
    return "callback_data is empty"
  if data.len > 64:
    return "callback_data exceeds 64 bytes (" & $data.len & ")"
  ""

func splitCaption*(text: string; limit = 1024): tuple[head, tail: string] =
  ## Behavior derived from hermes-agent (MIT) fix f828b087e7; see
  ## docs/hermes-mining/telegram/CASES.md#tg-007
  ##
  ## The caption limit is 1024 characters. The head fits the media message; the
  ## tail must be delivered separately so no text is lost.
  var kept = 0
  var bytePos = 0
  for r in text.runes:
    if kept >= limit:
      break
    bytePos += r.size
    inc kept
  (text[0 ..< bytePos], text[bytePos .. ^1])
