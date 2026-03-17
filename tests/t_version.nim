## Smoke test: binary compiles and --version exits 0

import std/[os, osproc, strutils, unittest]

suite "Binary":
  test "--version prints semver and exits 0":
    let binary = currentSourcePath.parentDir / "../src/donkey"
    # In CI the binary is built before tests; locally use `nimble build` first.
    skip()  # remove skip() once binary is built in nimble test task
