## A failed `Result` is reported, never dropped: `isOkOr:` followed only by
## `discard` hides a send failure from the logs. Handle the error (log it,
## return it, or tell the user).

import std/[os, strutils, unittest]

proc runTests*() =
  suite "no swallowed errors":
    test "no isOkOr handler is a bare discard":
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        let lines = readFile(path).splitLines()
        for i in 0 ..< lines.len - 1:
          if lines[i].strip.endsWith("isOkOr:") and lines[i + 1].strip == "discard":
            checkpoint(path & ":" & $(i + 1))
            fail()

when isMainModule:
  runTests()
