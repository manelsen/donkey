## The environment snapshot: read once, passed down, built by hand in tests.

import std/[os, unittest]
import donkey/config/environment

proc runTests*() =
  suite "environment snapshot":
    test "an unset or empty name yields the default":
      let env = environmentOf({"EMPTY": "", "SET": "x"})
      check env.get("UNSET") == ""
      check env.get("UNSET", "d") == "d"
      check env.get("EMPTY", "d") == "d"
      check env.get("SET", "d") == "x"

    test "stripped trims and treats blanks as unset":
      let env = environmentOf({"PAD": "  v  ", "BLANK": "   "})
      check env.stripped("PAD") == "v"
      check env.stripped("BLANK", "d") == "d"
      check env.get("PAD") == "  v  "

    test "has is true only for a non-blank value":
      let env = environmentOf({"SET": "x", "BLANK": " ", "EMPTY": ""})
      check env.has("SET")
      check not env.has("BLANK")
      check not env.has("EMPTY")
      check not env.has("UNSET")

    test "its pairs can be copied out, as plain data for a worker":
      var got: seq[(string, string)]
      for name, value in environmentOf({"A": "1", "B": "2"}).pairs:
        got.add (name, value)
      check ("A", "1") in got and ("B", "2") in got and got.len == 2

    test "with returns a copy and leaves the original alone":
      let base = environmentOf({"A": "1"})
      let changed = base.with("A", "2").with("B", "3")
      check base.get("A") == "1"
      check base.get("B") == ""
      check changed.get("A") == "2"
      check changed.get("B") == "3"

    test "a snapshot does not follow later changes to the process":
      putEnv("DONKEY_T_ENV_SNAPSHOT", "before")
      let env = readEnvironment()
      putEnv("DONKEY_T_ENV_SNAPSHOT", "after")
      delEnv("DONKEY_T_ENV_SNAPSHOT")
      check env.get("DONKEY_T_ENV_SNAPSHOT") == "before"

when isMainModule:
  runTests()
