## E12.1: where a Defect can be born on external data in the channels. With
## --panics:on a Defect (IndexDefect, FieldDefect) cannot be caught and takes
## the whole daemon down, every channel with it. The channel adapters and
## their pure parsers were audited (27/11) and are guarded; this test keeps
## the most dangerous shapes from coming back, at budget zero:
##
## - `split(...)[n]` with n >= 1: the n-th piece may not exist (a `[0]` always
##   does: split returns at least one piece);
## - indexing a JSON array's elements directly (`getElems()[i]`, `.elems[i]`):
##   the array may be shorter, or not an array at all.
##
## Index after a length check, or use the safe accessors (`{}`, `getOrDefault`).

import std/[os, strutils, unittest]
import ./t_nim_source

const
  Roots = ["src/donkey/adapters/channel", "src/donkey/domain/channels"]
  Budget = 0

func indexedSplit(line: string): bool =
  ## `.split(...)[n]` with n >= 1 (no regex: the project does without libpcre).
  var at = line.find(".split(")
  while at >= 0:
    var depth = 0
    var j = at + ".split".len
    while j < line.len:
      if line[j] == '(': inc depth
      elif line[j] == ')':
        dec depth
        if depth == 0: break
      inc j
    if j + 2 < line.len and line[j + 1] == '[' and line[j + 2] in {'1'..'9'}:
      return true
    at = line.find(".split(", at + 1)
  false

func shapeOf(line: string): string =
  if indexedSplit(line): "split(...)[n>=1]"
  elif "getElems()[" in line: "getElems()[i]"
  elif ".elems[" in line: ".elems[i]"
  else: ""

proc runTests*() =
  suite "channel defects (E12.1)":
    test "the shapes are recognised":
      check shapeOf("let x = s.split(':')[1]") == "split(...)[n>=1]"
      check shapeOf("let x = s.split(':')[0]") == ""
      check shapeOf("let x = s.split(f(a, b))[2].strip") == "split(...)[n>=1]"
      check shapeOf("let a = j{\"x\"}.getElems()[3]") == "getElems()[i]"
      check shapeOf("let a = j.elems[0]") == ".elems[i]"

    test "no unguarded indexing shape on external data in the channels":
      var found: seq[string]
      let root = currentSourcePath().parentDir.parentDir.parentDir
      for dir in Roots:
        for path in walkDirRec(root / dir):
          if not path.endsWith(".nim"): continue
          let code = codeOnly(readFile(path))
          var i = 0
          for line in code.splitLines:
            inc i
            let shape = shapeOf(line)
            if shape.len > 0:
              found.add relativePath(path, root) & ":" & $i & " " & shape
      if found.len > Budget:
        for f in found: echo "  ", f
      check found.len <= Budget

when isMainModule:
  runTests()
