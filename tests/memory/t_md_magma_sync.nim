## Regression: loading context must not re-import MEMORY.md into MAGMA.

when defined(withSqlite):
  import std/[os, strutils, unittest]
  import donkey/core/types
  import donkey/adapters/memory/md_file
  import donkey/adapters/memory/magma_memory_adapter
  import donkey/core/pipeops
  import donkey/domain/memory/provenance_pure
  import donkey/ports/memory
  import donkey/ports/multigraph_store

  proc memoryNodeCount(a: MdFileAdapter; uid: UserId): int =
    let magma = a.newMagmaAdapter()
    doAssert magma != nil
    magma.graph.listNodes($uid, "memory").len

  suite "MdFileAdapter ↔ MAGMA memory sync":
    let root = getTempDir() / "donkey_md_magma_sync"
    let uid = UserId("u-sync")

    setup:
      removeDir(root)
      createDir(root)
      delEnv("OPENROUTER_API_KEY")

    teardown:
      removeDir(root)

    proc newAdapter(): MdFileAdapter =
      MdFileAdapter(
        paddocksDir: root / "paddocks",
        magmaSqlitePath: root / "magma.sqlite",
      )

    test "multi-paragraph entries are not re-imported on load":
      let a = newAdapter()
      a.appendMemory(uid, "- **User:** pergunta A\n  **Response:** primeiro\n\nsegundo paragrafo\n")
      a.appendMemory(uid, "- **User:** pergunta B\n  **Response:** resposta B\n\nfecho de B\n")
      a.appendMemory(uid, "- **User:** pergunta C\n  **Response:** resposta C\n")
      check a.memoryNodeCount(uid) == 3
      for _ in 1 .. 3:
        discard a.loadContext(uid)
      check a.memoryNodeCount(uid) == 3

    test "loaded context does not repeat stored paragraphs":
      let a = newAdapter()
      a.appendMemory(uid, "- **User:** pergunta A\n  **Response:** primeiro\n\nsegundo paragrafo\n")
      a.appendMemory(uid, "- **User:** pergunta B\n  **Response:** resposta B\n\nfecho de B\n")
      let memoryMd = a.loadContext(uid).memoryMd
      check memoryMd.count("segundo paragrafo") == 1
      check memoryMd.count("pergunta B") == 1
      check memoryMd.count("fecho de B") == 1

    test "entries beyond the recent window are not re-imported":
      let a = newAdapter()
      const total = 215
      for i in 1 .. total:
        a.appendMemory(uid, "- fato numero " & $i & "\n")
      check a.memoryNodeCount(uid) == total
      for _ in 1 .. 2:
        discard a.loadContext(uid)
      check a.memoryNodeCount(uid) == total

    test "a line added right below a stored entry is imported alone":
      let a = newAdapter()
      a.appendMemory(uid, "- fato antigo\n")
      let path = a.memoryMdPath(uid)
      writeFile(path, readFile(path) & "- fato novo\n")
      discard a.loadContext(uid)
      let magma = a.newMagmaAdapter()
      var contents: seq[string]
      for node in magma.graph.listNodes($uid, "memory"):
        contents.add(node.content.strip)
      check contents == @["- fato antigo", "- fato novo"]

    test "context lists each contiguous entry once beyond the recent window":
      let a = newAdapter()
      const total = 215
      for i in 1 .. total:
        a.appendMemory(uid, "- fato numero " & $i & "\n")
      var seen = 0
      for line in a.loadContext(uid).memoryMd.splitLines():
        if line.startsWith("- fato numero "):
          inc seen
      check seen == total

    test "a paragraph written by hand into MEMORY.md is imported once":
      let a = newAdapter()
      a.appendMemory(uid, "- fato gravado pelo agente\n")
      let path = a.memoryMdPath(uid)
      writeFile(path, readFile(path) & "\n\nnota escrita a mao pelo usuario\n")
      discard a.loadContext(uid)
      check a.memoryNodeCount(uid) == 2
      discard a.loadContext(uid)
      check a.memoryNodeCount(uid) == 2

    proc memoryOrigins(a: MdFileAdapter; uid: UserId): seq[MemoryOrigin] =
      let magma = a.newMagmaAdapter()
      doAssert magma != nil
      for node in magma.graph.listNodes($uid, "memory"):
        result.add(originFromMeta(node.meta))

    test "runtime port tags appended memory with its origin":
      let a = newAdapter()
      let port = a.toRuntimePort()
      check port.appendMemoryFrom != nil
      port.appendMemoryFrom(uid, "- **User:** a\n  **Response:** b\n", turnOrigin("s7"))
      port.appendMemory(uid, "sem origem")
      check a.memoryOrigins(uid) == @[turnOrigin("s7"), MemoryOrigin()]

    test "consolidated memory is tagged as consolidation":
      let a = newAdapter()
      let port = a.toRuntimePort()
      check port.appendExtractedMemory(uid, "## Consolidated memory\n- Fact: x\n").isOk
      check a.memoryOrigins(uid) == @[MemoryOrigin(source: msConsolidation)]

    test "paragraphs imported from MEMORY.md are tagged as markdown":
      let a = newAdapter()
      a.ensurePaddock(uid)
      writeFile(a.memoryMdPath(uid), "nota escrita a mao\n")
      a.newMagmaAdapter().saveUserMd(uid, "# Ada")
      discard a.loadContext(uid)
      check a.memoryOrigins(uid) == @[MemoryOrigin(source: msMarkdown)]

    test "first import of an existing MEMORY.md is tagged as markdown":
      let a = newAdapter()
      a.ensurePaddock(uid)
      writeFile(a.memoryMdPath(uid), "nota antiga um\n\nnota antiga dois\n")
      discard a.loadContext(uid)
      check a.memoryOrigins(uid) ==
        @[MemoryOrigin(source: msMarkdown), MemoryOrigin(source: msMarkdown)]

    test "backend without MAGMA exposes no origin hook":
      let plain = MdFileAdapter(paddocksDir: root / "paddocks")
      check plain.toRuntimePort().appendMemoryFrom == nil
