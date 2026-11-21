## Exception hygiene: handlers catch `CatchableError`, so a `Defect`
## (index error, nil access, failed assertion) crashes loudly instead of
## turning into a silent "unavailable". `except Exception` is allowed only at
## an effect boundary the compiler requires: a `{.raises: [].}` proc calling a
## callee whose raises are not annotated. Those lines carry the marker below.

import std/[os, strutils, unittest]

const BoundaryMarker = "## effect boundary: callee raises are unannotated"

proc runTests*() =
  suite "exception hygiene":
    test "no bare except and no unexplained except Exception in src":
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        var n = 0
        for line in readFile(path).splitLines():
          inc n
          let t = line.strip
          if t == "except:":
            checkpoint(path & ":" & $n & " bare except")
            fail()
          if t.startsWith("except Exception") and BoundaryMarker notin line:
            checkpoint(path & ":" & $n & " except Exception without the boundary marker")
            fail()

when isMainModule:
  runTests()
