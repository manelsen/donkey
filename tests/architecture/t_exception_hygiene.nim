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

func codeOf(line: string): string =
  ## The line without string/char literals and without its comment, so that
  ## "except:" in text or after `#` is not mistaken for code.
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '#': break
    if c == '"' or c == '\'':
      inc i
      while i < line.len and line[i] != c:
        if line[i] == '\\': inc i
        inc i
      result.add ' '
    else:
      result.add c
    inc i

func isIdentChar(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func exceptHeads(line: string): seq[string] =
  ## What follows each `except` keyword in the code part of the line, up to
  ## the colon: "" for a bare handler, "Exception", "CatchableError", ...
  let code = codeOf(line)
  var i = code.find("except")
  while i >= 0:
    let stop = i + "except".len
    let wordStart = i == 0 or not isIdentChar(code[i - 1])
    let wordEnd = stop >= code.len or not isIdentChar(code[stop])
    if wordStart and wordEnd:
      let colon = code.find(':', stop)
      result.add(if colon < 0: code[stop .. ^1].strip else: code[stop ..< colon].strip)
    i = code.find("except", stop)

func isBareExcept(line: string): bool =
  ## `except:` with no exception type, anywhere in the line's code: alone,
  ## before a comment, with an inline value, or inside a one-line `try`.
  "" in exceptHeads(line)

func catchesException(line: string): bool =
  for head in exceptHeads(line):
    if head == "Exception" or head.startsWith("Exception ") or
       head.startsWith("Exception,"):
      return true

proc runTests*() =
  suite "exception hygiene":
    test "a bare except is recognized with or without a trailing comment":
      check isBareExcept("  except:")
      check isBareExcept("except: # fallback")
      check isBareExcept("except :  ## why")
      check isBareExcept("except: newJObject()")
      check isBareExcept("let x = (try: parseInt(s) except: -1)")
      check not isBareExcept("let x = (try: parseInt(s) except ValueError: -1)")
      check not isBareExcept("echo \"except: in a string\"")
      check not isBareExcept("discard  # except: in a comment")
      check catchesException("let x = (try: f() except Exception: 0)")
      check catchesException("except Exception as e:")
      check not catchesException("except CatchableError as e:")
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
          if isBareExcept(line):
            checkpoint(path & ":" & $n & " bare except")
            fail()
          if catchesException(line) and BoundaryMarker notin line:
            checkpoint(path & ":" & $n & " except Exception without the boundary marker")
            fail()

when isMainModule:
  runTests()
