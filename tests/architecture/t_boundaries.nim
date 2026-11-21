import std/[osproc, strutils, unittest]

proc runTests*() =
  suite "boundary enforcement":
    test "layer import rules stay intact":
      check execCmd("bash scripts/check_boundaries.sh") == 0

    test "the command dispatcher depends on ports, not adapters":
      let source = readFile("src/donkey/app/command_dispatch.nim")
      for line in source.splitLines():
        let trimmed = line.strip
        if trimmed.startsWith("import") or trimmed.startsWith("from"):
          check "adapters/" notin trimmed
      check "MdFileAdapter" notin source
      check "IdentityResolver" notin source

when isMainModule:
  runTests()
