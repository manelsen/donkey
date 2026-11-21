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

func isIdentChar(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func codeOnly(src: string): string =
  ## `src` with comments and string/char literals blanked out, newlines kept,
  ## so "except:" in text is not mistaken for code and line numbers still
  ## match. Lexical state carries across lines: `#[ ]#` block comments (they
  ## nest), `"""` strings, raw strings (`r"…"`, `fmt"…"`, where `\` is not an
  ## escape and `""` is a quote), plain strings and char literals.
  var i = 0
  template blank(c: char) = result.add(if c == '\n': '\n' else: ' ')
  while i < src.len:
    let c = src[i]
    let prev = if i > 0: src[i - 1] else: ' '
    if c == '#' and (src.continuesWith("#[", i) or src.continuesWith("##[", i)):
      var depth = 0
      while i < src.len:
        if src.continuesWith("#[", i):
          inc depth; blank(src[i]); blank(src[i + 1]); i += 2
        elif src.continuesWith("]#", i):
          dec depth; blank(src[i]); blank(src[i + 1]); i += 2
          if depth == 0: break
        else:
          blank(src[i]); inc i
    elif c == '#':
      while i < src.len and src[i] != '\n':
        blank(src[i]); inc i
    elif src.continuesWith("\"\"\"", i):
      result.add "   "; i += 3
      while i < src.len and not src.continuesWith("\"\"\"", i):
        blank(src[i]); inc i
      while i < src.len and src[i] == '"':
        blank(src[i]); inc i
    elif c == '"' and isIdentChar(prev):
      blank(c); inc i
      while i < src.len and src[i] != '\n':
        if src[i] == '"':
          if i + 1 < src.len and src[i + 1] == '"':
            blank(src[i]); blank(src[i + 1]); i += 2
            continue
          break
        blank(src[i]); inc i
      if i < src.len and src[i] == '"':
        blank(src[i]); inc i
    elif c == '"' or (c == '\'' and not isIdentChar(prev)):
      blank(c); inc i
      while i < src.len and src[i] != c and src[i] != '\n':
        if src[i] == '\\' and i + 1 < src.len:
          blank(src[i]); inc i
        blank(src[i]); inc i
      if i < src.len and src[i] == c:
        blank(src[i]); inc i
    else:
      result.add c; inc i

type Handler = object
  firstLine, lastLine: int  ## 0-based span of `except … :`
  types: seq[string]        ## empty for a bare handler

func lineAt(code: string; pos: int): int = code[0 ..< pos].count('\n')

func inImport(code: string; pos: int): bool =
  ## `import a except b` / `from a import b except c` exclude symbols; they
  ## are not handlers.
  let lineStart = code.rfind('\n', last = max(pos - 1, 0)) + 1
  let head = code[lineStart ..< pos].strip
  head.startsWith("import ") or head.startsWith("from ") or
    head.startsWith("include ")

func handlers(code: string): seq[Handler] =
  ## Every exception handler in `code` (comments and literals already
  ## blanked). The head runs from `except` to its colon, across lines when
  ## the type list continues after a comma.
  var i = code.find("except")
  while i >= 0:
    let stop = i + "except".len
    let wordStart = i == 0 or not isIdentChar(code[i - 1])
    let wordEnd = stop >= code.len or not isIdentChar(code[stop])
    if wordStart and wordEnd and not code.inImport(i):
      let colon = code.find(':', stop)
      let headEnd = if colon < 0: code.len else: colon
      var head = code[stop ..< headEnd].replace('\n', ' ').strip
      let asAt = head.find(" as ")
      if asAt >= 0: head = head[0 ..< asAt]
      var h = Handler(firstLine: code.lineAt(i), lastLine: code.lineAt(headEnd))
      for t in head.split(','):
        var name = t.strip
        if name.startsWith("system."): name = name["system.".len .. ^1]
        if name.len > 0: h.types.add name
      result.add h
    i = code.find("except", stop)

func bare(src: string): bool =
  for h in handlers(codeOnly(src)):
    if h.types.len == 0: return true

func broad(src: string): bool =
  for h in handlers(codeOnly(src)):
    if "Exception" in h.types: return true

proc runTests*() =
  suite "exception hygiene":
    test "handlers are recognized in code, not in comments or literals":
      check bare("  except:")
      check bare("except: # fallback")
      check bare("except :  ## why")
      check bare("except: newJObject()")
      check bare("let x = (try: parseInt(s) except: -1)")
      check bare("let x = (try: r\"C:\\\" except: \"\")")
      check bare("const a = \"\"\"\nexcept:\n\"\"\"\nexcept:")
      check bare("let n = 0'i64\nexcept:")
      check not bare("let x = (try: parseInt(s) except ValueError: -1)")
      check not bare("echo \"except: in a string\"")
      check not bare("discard  # except: in a comment")
      check not bare("const a = \"\"\"\nexcept:\n\"\"\"")
      check not bare("#[\nexcept:\n#[ nested ]#\nexcept:\n]#")
      check not bare("let c = '\"'\necho \"except:\"")
      check not bare("except CatchableError:")
      check not bare("except CatchableError: # fallback")
      check not bare("except ValueError, IOError:")
      check not bare("exceptional = true")
      check broad("let x = (try: f() except Exception: 0)")
      check broad("except Exception as e:")
      check broad("except ValueError, Exception:")
      check broad("except Exception, ValueError as e:")
      check not broad("except CatchableError as e:")
      check not broad("except ValueError, IOError:")
      check not broad("echo \"except Exception:\"")
      check broad("except system.Exception: discard")
      check not broad("except system.CatchableError: discard")
      check broad("try: f()\nexcept ValueError,\n       Exception:\n  discard")
      check not bare("import std/os except\n  walkDir")
      check not bare("from std/os import nil except walkDir")
      check not bare("import std/strutils except strip")

    test "no bare except and no unexplained except Exception in src":
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        let lines = readFile(path).splitLines()
        for h in handlers(codeOnly(lines.join("\n"))):
          let at = path & ":" & $(h.firstLine + 1)
          if h.types.len == 0:
            checkpoint(at & " bare except")
            fail()
          if "Exception" in h.types:
            var marked = false
            for n in h.firstLine .. min(h.lastLine, lines.high):
              if BoundaryMarker in lines[n]: marked = true
            if not marked:
              checkpoint(at & " except Exception without the boundary marker")
              fail()

when isMainModule:
  runTests()
