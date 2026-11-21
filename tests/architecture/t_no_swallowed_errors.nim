## A failed `Result` is reported, never dropped: an `isOkOr:` handler whose
## whole body is `discard` hides a send failure from the logs. Handle the
## error (log it, return it, or tell the user).

import std/[os, sequtils, strutils, unittest]

func indentOf(line: string): int =
  while result < line.len and line[result] == ' ': inc result

func isCode(line: string): bool =
  let t = line.strip
  t.len > 0 and not t.startsWith("#")

func swallowedAt(lines: seq[string]): seq[int] =
  ## 0-based lines of `isOkOr:` handlers that only `discard`: the inline
  ## form, or a block whose code lines (comments and blank lines skipped)
  ## are all `discard`.
  for i, line in lines:
    let code = line.split('#')[0].strip
    if code.endsWith("isOkOr: discard"):
      result.add i
      continue
    if not code.endsWith("isOkOr:"):
      continue
    var body: seq[string]
    for j in i + 1 ..< lines.len:
      if not lines[j].isCode: continue
      if lines[j].indentOf <= line.indentOf: break
      body.add lines[j].split('#')[0].strip
    if body.len > 0 and body.allIt(it == "discard"):
      result.add i

func swallows(src: string): bool = swallowedAt(src.splitLines).len > 0

proc runTests*() =
  suite "no swallowed errors":
    test "a discard-only handler is found whatever its layout":
      check swallows("send().isOkOr:\n  discard")
      check swallows("send().isOkOr:\n  # ignored\n\n  discard")
      check swallows("send().isOkOr: discard")
      check swallows("send().isOkOr:  # why\n  discard  # nothing")
      check not swallows("send().isOkOr:\n  log.warn(error)")
      check not swallows("send().isOkOr:\n  discard\n  log.warn(error)")
      check not swallows("send().isOkOr:\n  log.warn(error)\nother()\ndiscard")

    test "no isOkOr handler is a bare discard":
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        for i in swallowedAt(readFile(path).splitLines()):
          checkpoint(path & ":" & $(i + 1))
          fail()

when isMainModule:
  runTests()
