import std/unittest

import donkey/core/tooling/native_tool_dispatch

suite "core native tool dispatch":
  test "category order is stable":
    check nativeToolCategoryOrder() == @[
      ntckLegacy,
      ntckShell,
      ntckWeb,
      ntckUtility,
      ntckSession,
      ntckAgent,
    ]

  test "classify shell tool":
    check classifyNativeTool("edit_file") == @[ntckShell]

  test "classify agent tool":
    check classifyNativeTool("await") == @[ntckAgent]

  test "unknown tool is not known":
    check classifyNativeTool("not_a_tool").len == 0
    check not isKnownNativeTool("not_a_tool")
