## The domain rule (ADR-007, accepted 2026-11-23): `domain/` has no I/O, no
## exceptions and no global state. `Result` is allowed as a value, `func` is
## the default and `proc` is accepted only because a stdlib call (building a
## `JsonNode`, `parseJson`) is not marked `noSideEffect`.
##
## I/O imports are refused by `scripts/check_boundaries.sh`; this test checks
## the other two promises in the code itself (comments and literals blanked):
## no `raise`, and no module-level `var`, `{.threadvar.}` or `{.global.}`.

import std/[os, strutils, unittest]
import ./t_nim_source

const DomainDir = currentSourcePath().parentDir / ".." / ".." / "src" / "donkey" / "domain"

func hasWord(line, word: string): bool =
  var i = line.find(word)
  while i >= 0:
    let before = i == 0 or not isIdentChar(line[i - 1])
    let stop = i + word.len
    let after = stop >= line.len or not isIdentChar(line[stop])
    if before and after: return true
    i = line.find(word, i + 1)
  false

proc offences(path: string): seq[string] =
  let code = codeOnly(readFile(path))
  let lines = code.splitLines()
  for n, line in lines:
    let at = path.relativePath(DomainDir) & ":" & $(n + 1)
    if line.hasWord("raise"):
      result.add(at & " raise")
    if line.startsWith("var ") or line.strip == "var":
      result.add(at & " module-level var")
    if "{.threadvar.}" in line or "{.global.}" in line:
      result.add(at & " thread/global state")

proc runTests*() =
  suite "domain purity (ADR-007)":
    test "no raise, no global state anywhere in domain/":
      var found: seq[string]
      for path in walkDirRec(DomainDir):
        if path.endsWith(".nim"):
          found.add(offences(path))
      if found.len > 0:
        checkpoint(found.join("\n"))
      check found.len == 0

    test "the scanner sees what it must":
      check "    raise newException(ValueError, \"x\")".hasWord("raise")
      check not "let raised = 1".hasWord("raise")

when isMainModule:
  runTests()
