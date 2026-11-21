## A failed `Result` is reported, never dropped: an `isOkOr:` handler whose
## whole body is `discard` hides a send failure from the logs. Handle the
## error (log it, return it, or tell the user).

import std/[os, sequtils, strutils, unittest]
import ./t_nim_source

func indentOf(line: string): int =
  while result < line.len and line[result] == ' ': inc result

func swallowedAt(lines: seq[string]): seq[int] =
  ## 0-based lines of `isOkOr:` handlers that only `discard`: the inline
  ## form, or a block whose code lines are all `discard`. Comments and
  ## literals are blanked first, so a `#` inside a string is not a comment.
  let code = codeOnly(lines.join("\n")).splitLines()
  for i, line in code:
    let t = line.strip
    let at = t.rfind("isOkOr:")
    if at < 0 or at + "isOkOr:".len < t.len and
       t[at + "isOkOr:".len .. ^1].strip notin ["", "discard"]:
      continue
    if t[at + "isOkOr:".len .. ^1].strip == "discard":
      result.add i
      continue
    var body: seq[string]
    for j in i + 1 ..< code.len:
      if code[j].strip.len == 0: continue
      if code[j].indentOf <= line.indentOf: break
      body.add code[j].strip
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
      check swallows("send(\"#\").isOkOr: discard")
      check swallows("send(\"#\").isOkOr:\n  discard")
      check swallows("send().isOkOr:  discard")
      check swallows("send().isOkOr:\tdiscard")
      check not swallows("send().isOkOr: log.warn(error)")
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
