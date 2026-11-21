import std/[os, osproc, sets, strutils, tables, unittest]
import ./t_nim_source

type ImportGraph = Table[string, seq[string]]
  ## module -> the import paths it wrote, as the compiler resolved them

func parseDependDot(dot: string): ImportGraph =
  ## Edges of `nim genDepend`: `"importer" -> "imported/path";`.
  for line in dot.splitLines():
    let parts = line.strip.split("\" -> \"")
    if parts.len != 2: continue
    let src = parts[0].strip(chars = {'"'})
    let dst = parts[1].strip(chars = {'"', ';'})
    result.mgetOrPut(src, @[]).add dst

func moduleName(importPath: string): string =
  importPath.splitPath.tail.changeFileExt("")

proc importGraph(module: string): ImportGraph =
  ## The compiler's own view of the imports, so `when`, `include`, quoted
  ## and multi-line imports count exactly as they compile. genDepend writes
  ## `<module>.dot` next to the module; it is read and removed here.
  let dotPath = module.changeFileExt("dot")
  let nimcache = getTempDir() / ("donkey_gendepend_" & $getCurrentProcessId())
  defer:
    removeFile(dotPath)
    removeFile(module.changeFileExt("png"))
    removeDir(nimcache)
  createDir(nimcache)
  discard execCmdEx("nim genDepend --hints:off --nimcache:" &
                    quoteShell(nimcache) & " " & quoteShell(module))
  doAssert fileExists(dotPath), "nim genDepend wrote no graph for " & module
  parseDependDot(readFile(dotPath))

func reachableImports(graph: ImportGraph; root: string): seq[string] =
  ## Every import path reachable from `root`, by module name.
  var seen = initHashSet[string]()
  var stack = @[root]
  while stack.len > 0:
    let node = stack.pop()
    for path in graph.getOrDefault(node):
      result.add path
      let name = path.moduleName
      if name notin seen:
        seen.incl name
        stack.add name

proc runTests*() =
  suite "boundary enforcement":
    test "layer import rules stay intact":
      check execCmd("bash scripts/check_boundaries.sh") == 0

    test "genDepend edges are read":
      let graph = parseDependDot("digraph x {\n\"a\" -> \"../adapters/b\";\n" &
                                 "\"b\" -> \"std/os\";\n}")
      check graph["a"] == @["../adapters/b"]
      check reachableImports(graph, "a") == @["../adapters/b", "std/os"]

    test "the command dispatcher depends on ports, not adapters":
      ## Transitive: nothing the dispatcher imports may pull an adapter in.
      let graph = importGraph("src/donkey/app/command_dispatch.nim")
      check graph.hasKey("command_dispatch")
      for path in reachableImports(graph, "command_dispatch"):
        if "adapters/" in path:
          checkpoint("reaches " & path)
        check "adapters/" notin path
      let code = codeOnly(readFile("src/donkey/app/command_dispatch.nim"))
      check "MdFileAdapter" notin code
      check "IdentityResolver" notin code

when isMainModule:
  runTests()
