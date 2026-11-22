## The version the binary prints comes from donkey.nimble, so the two cannot
## drift apart (they had: the binary said 0.1.0 while the package was 0.2.0).

import std/[os, strutils, unittest]
import donkey/core/app_meta

proc nimbleVersion(): string =
  for line in readFile(currentSourcePath.parentDir / "../../donkey.nimble").splitLines:
    if line.startsWith("version"):
      return line.split('=')[1].strip.strip(chars = {'"'})

proc runTests*() =
  suite "app metadata":
    test "AppVersion is the package version":
      check AppVersion == nimbleVersion()

    test "this release is 0.3.0":
      check AppVersion == "0.3.0"

when isMainModule:
  runTests()
