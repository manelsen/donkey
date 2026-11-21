## Exception hygiene: handlers catch `CatchableError`, so a `Defect`
## (index error, nil access, failed assertion) crashes loudly instead of
## turning into a silent "unavailable". `except Exception` is allowed only at
## an effect boundary the compiler requires: a proc with a closed raises list
## (`{.raises: [].}`, or a Chronos `{.async.}` proc, which admits only
## `CatchableError`) calling a callee whose raises are not annotated (a port
## closure, or a forward declaration without `raises`). Those lines carry the
## marker below. The fix for each one is to annotate the callee.

import std/[os, strutils, unittest]

const BoundaryMarker = "## effect boundary: callee raises are unannotated"

func isBareExcept(line: string): bool =
  ## `except:` with no exception type, whatever follows the colon: nothing,
  ## a comment, or an inline value (`except: newJObject()`).
  let t = line.strip
  t.startsWith("except") and t["except".len .. ^1].strip.startsWith(":")

proc runTests*() =
  suite "exception hygiene":
    test "a bare except is recognized with or without a trailing comment":
      check isBareExcept("  except:")
      check isBareExcept("except: # fallback")
      check isBareExcept("except :  ## why")
      check isBareExcept("except: newJObject()")
      check not isBareExcept("except CatchableError:")
      check not isBareExcept("except CatchableError: # fallback")
      check not isBareExcept("except ValueError, IOError:")
      check not isBareExcept("exceptional = true")

    test "no bare except and no unexplained except Exception in src":
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        var n = 0
        for line in readFile(path).splitLines():
          inc n
          let t = line.strip
          if isBareExcept(line):
            checkpoint(path & ":" & $n & " bare except")
            fail()
          if t.startsWith("except Exception") and BoundaryMarker notin line:
            checkpoint(path & ":" & $n & " except Exception without the boundary marker")
            fail()

when isMainModule:
  runTests()
