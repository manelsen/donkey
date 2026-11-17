## Tests for outbound Telegram policies extracted from the hermes history.
##
## Each test starts with the case id from docs/hermes-mining/telegram/CASES.md.

import std/[strutils, unittest]
import donkey/domain/channels/telegram_policy

suite "telegram_policy — edit errors":

  test "TG-002: \"message is not modified\" is treated as success":
    check isEditNoopError(
      "Telegram API error [editMessageText]: bad request: message is not modified")
    check isEditNoopError("MESSAGE IS NOT MODIFIED")

  test "TG-002: other edit errors are not swallowed":
    check not isEditNoopError("")
    check not isEditNoopError("chat not found")
    check not isEditNoopError(
      "Telegram API error [editMessageText]: message to edit not found")


suite "telegram_policy — reply anchors":

  test "TG-005: a missing reply anchor is recognised":
    check isMissingReplyAnchorError(
      "Telegram API error [sendMessage]: Bad Request: message to be replied not found")
    check isMissingReplyAnchorError("reply message not found")

  test "TG-005: unrelated errors are not treated as a missing anchor":
    check not isMissingReplyAnchorError("chat not found")
    check not isMissingReplyAnchorError("")


suite "telegram_policy — outbound text":

  test "TG-006: empty and whitespace-only text is not sent":
    check shouldSkipOutboundText("")
    check shouldSkipOutboundText("   \n\t ")
    check not shouldSkipOutboundText("oi")
