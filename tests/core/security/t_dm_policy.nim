## Group-chat gating policy (TG-016).
##
## A group allowlist is a chat-level gate: when it is configured, a message
## from any other chat is dropped before a session exists, regardless of the
## DM policy. An empty list keeps the previous behaviour (every group).

import std/unittest
import donkey/core/security/dm_policy
import donkey/core/types

proc runTests*() =
  suite "group chat allowlist":

    test "an empty allowlist allows every group":
      check groupChatAllowed(GroupGate(), "-100123")
      check groupChatAllowed(GroupGate(allowedChats: @[]), "-100123")

    test "a listed chat is allowed":
      let gate = GroupGate(allowedChats: @["-100123", "-100456"])
      check groupChatAllowed(gate, "-100123")
      check groupChatAllowed(gate, "-100456")

    test "an unlisted chat is denied":
      let gate = GroupGate(allowedChats: @["-100123"])
      check not groupChatAllowed(gate, "-100999")
      check not groupChatAllowed(gate, "")

    test "ids are compared exactly, without prefix matching":
      let gate = GroupGate(allowedChats: @["-100"])
      check not groupChatAllowed(gate, "-100123")

  suite "chat id list parsing":

    test "splits on commas, trims and drops empties":
      check parseChatIdList(" -1001, -1002 ,, -1003 ") ==
            @["-1001", "-1002", "-1003"]

    test "deduplicates while preserving order":
      check parseChatIdList("-1,-2,-1,-3,-2") == @["-1", "-2", "-3"]

    test "an empty value yields an empty list":
      check parseChatIdList("").len == 0
      check parseChatIdList("  ,  ").len == 0

when isMainModule:
  runTests()
