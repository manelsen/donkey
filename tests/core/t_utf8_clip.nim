import std/[unicode, unittest]
import donkey/core/utf8

proc runTests*() =
  suite "UTF-8 clipping":

    test "returns short strings unchanged":
      check clipUtf8("abc", 10) == "abc"

    test "appends a suffix when clipping":
      check clipUtf8("abcdef", 3) == "abc…"

    test "never splits a multi-byte code point":
      let text = "ação 😀 coração"
      for limit in 1 ..< text.len:
        let clipped = clipUtf8(text, limit)
        check validateUtf8(clipped) == -1

    test "zero limit returns only the suffix":
      check clipUtf8("abc", 0) == "…"

when isMainModule:
  runTests()
