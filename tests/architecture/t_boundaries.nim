import std/[osproc, strutils, unittest]
import ./t_nim_source

proc runTests*() =
  suite "boundary enforcement":
    test "layer import rules stay intact":
      check execCmd("bash scripts/check_boundaries.sh") == 0

    test "the command dispatcher depends on ports, not adapters":
      ## Outside comments and literals, a module path only appears in an
      ## import, however many lines the import statement spans.
      let code = codeOnly(readFile("src/donkey/app/command_dispatch.nim"))
      check "adapters/" notin code
      check "MdFileAdapter" notin code
      check "IdentityResolver" notin code

    test "a multi-line import is still seen":
      check "adapters/" in codeOnly("import\n  ../adapters/channel/model_catalog_ui")
      check "adapters/" notin codeOnly("## see adapters/channel\nlet x = \"adapters/\"")

when isMainModule:
  runTests()
