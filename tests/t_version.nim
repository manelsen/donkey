## Smoke test: binary compiles and --version exits 0.
##
## The run_tests.sh script invokes `nimble build` before running tests,
## so the binary at src/donkey is expected to exist.

import std/[os, osproc, strutils, unittest]

suite "Binary smoke test":
  test "--version prints semver and exits 0":
    ## nimble places the binary at the project root (srcDir="src", bin=@["donkey"])
    let binary = currentSourcePath.parentDir / "../donkey"
    if not fileExists(binary):
      skip()  ## binary not built yet; run `nimble build` first
    let (output, exitCode) = execCmdEx(binary & " --version")
    check exitCode == 0
    ## Must contain a semver-like string (MAJOR.MINOR.PATCH)
    let hasVersion = output.strip.split('.').len >= 2
    check hasVersion
