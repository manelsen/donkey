import std/unittest

import donkey/core/tooling/native_tool_dispatch

suite "core native tool dispatch":
  test "category order is stable":
    check nativeToolCategoryOrder() == @[
      ntckLegacy,
      ntckShell,
      ntckStructured,
      ntckCode,
      ntckWeb,
      ntckUtility,
      ntckSession,
      ntckAgent,
    ]

  test "classify shell tool":
    check classifyNativeTool("edit_file") == @[ntckShell]

  test "classify agent tool":
    check classifyNativeTool("await") == @[ntckAgent]

  test "classify structured tool":
    check classifyNativeTool("json_query") == @[ntckStructured]

  test "classify execute_code":
    check classifyNativeTool("execute_code") == @[ntckCode]
    check isKnownNativeTool("execute_code")

  test "legacy unix-like tools are no longer classified":
    for name in ["find", "grep", "sed", "wc", "head", "tail", "sort", "cp", "mv", "rm", "mkdir"]:
      check classifyNativeTool(name).len == 0
      check not isKnownNativeTool(name)

  test "classify session tool":
    check classifyNativeTool("manage_skills") == @[ntckSession]
    check classifyNativeTool("session_search") == @[ntckSession]

  test "unknown tool is not known":
    check classifyNativeTool("not_a_tool").len == 0
    check not isKnownNativeTool("not_a_tool")
