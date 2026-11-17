## telegram_policy.nim — outbound policies derived from the Bot API behavior.
##
## Pure functions only: the adapter decides when to call them, this module
## decides what the API contract requires.

import std/strutils

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
