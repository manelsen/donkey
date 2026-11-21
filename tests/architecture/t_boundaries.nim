import std/[osproc, strutils, unittest]
import ./t_nim_source

func importSpans(src: string): seq[string] =
  ## The source text of each import statement (`import`, `from`, `include`),
  ## continuation lines included. Statements are found in `codeOnly` (so a
  ## commented-out import is ignored) and read back from `src` at the same
  ## offsets, so a quoted path such as `import "../adapters/x"` is kept.
  let code = codeOnly(src)
  let lines = code.splitLines()
  let original = src.splitLines()
  var offset = 0
  var i = 0
  while i < lines.len:
    let t = lines[i].strip
    let start = offset
    let indent = lines[i].len - lines[i].strip(trailing = false).len
    if t.startsWith("import ") or t == "import" or t.startsWith("from ") or
       t.startsWith("include "):
      var stop = offset + lines[i].len
      var j = i + 1
      var o = stop + 1
      ## A continuation is a deeper-indented line that is not blank or a
      ## comment in the source (a line holding only a quoted path is blank
      ## in `code`, so the source decides).
      while j < lines.len and original[j].strip.len > 0 and
            not original[j].strip.startsWith("#") and
            lines[j].len - lines[j].strip(trailing = false).len > indent:
        stop = o + lines[j].len
        o = stop + 1
        inc j
      result.add src[start ..< min(stop, src.len)]
      for k in i ..< j:
        offset += lines[k].len + 1
      i = j
    else:
      offset += lines[i].len + 1
      inc i

proc runTests*() =
  suite "boundary enforcement":
    test "layer import rules stay intact":
      check execCmd("bash scripts/check_boundaries.sh") == 0

    test "the command dispatcher depends on ports, not adapters":
      ## Outside comments and literals, a module path only appears in an
      ## import, however many lines the import statement spans.
      let source = readFile("src/donkey/app/command_dispatch.nim")
      let code = codeOnly(source)
      for statement in importSpans(source):
        check "adapters/" notin statement
      check "MdFileAdapter" notin code
      check "IdentityResolver" notin code

    test "import statements are read whole, quoted paths included":
      check importSpans("import\n  ../adapters/channel/model_catalog_ui")[0].contains("adapters/")
      check importSpans("import \"../adapters/channel/model_catalog_ui\"")[0].contains("adapters/")
      check importSpans("import std/os,\n  \"../adapters/x\"\nlet y = 1")[0].contains("adapters/")
      check importSpans("## import ../adapters/x\nlet x = \"adapters/\"").len == 0
      check importSpans("import a\nlet z = \"adapters/\"") == @["import a"]

when isMainModule:
  runTests()
