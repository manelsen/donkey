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
