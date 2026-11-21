import std/[osproc, strutils, unittest]
import ./t_nim_source

func importSpans(src: string): seq[string] =
  ## Each import statement (`import`, `from`, `include`) with comments
  ## removed and paths kept, quoted ones included. A statement continues
  ## over deeper-indented lines; blank and comment-only lines in between do
  ## not end it.
  let lines = withoutComments(src).splitLines()
  func indentOf(line: string): int = line.len - line.strip(trailing = false).len
  var i = 0
  while i < lines.len:
    let t = lines[i].strip
    if t.startsWith("import ") or t == "import" or t.startsWith("from ") or
       t.startsWith("include "):
      var statement = @[lines[i].strip(leading = false)]
      var j = i + 1
      while j < lines.len:
        if lines[j].strip.len == 0:
          inc j
          continue
        if lines[j].indentOf <= lines[i].indentOf:
          break
        statement.add lines[j].strip
        inc j
      result.add statement.join(" ")
      i = j
    else:
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
      check importSpans("import std/os,\n  # more\n  \"../adapters/x\"")[0].contains("adapters/")
      check not importSpans("import std/os # adapters/x")[0].contains("adapters/")
      check not importSpans("import std/os #[ adapters/x ]#")[0].contains("adapters/")

when isMainModule:
  runTests()
