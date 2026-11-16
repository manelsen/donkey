## With a MAGMA backend the graph is the source of truth and the Markdown
## files in the paddock are an export of it.

when defined(withSqlite):
  import std/[os, sequtils, strutils, unittest]
  import donkey/core/pipeops
  import donkey/core/types
  import donkey/adapters/memory/md_file
  import donkey/adapters/memory/magma_memory_adapter
  import donkey/adapters/memory/multigraph_runtime
  import donkey/domain/memory/episode_pure
  import donkey/domain/memory/session_search_pure
  import donkey/domain/personality
  import donkey/ports/memory
  import donkey/ports/multigraph_store

  suite "MdFileAdapter with MAGMA — the graph is the source of truth":
    let root = getTempDir() / "donkey_md_magma_truth"
    let uid = UserId("u-truth")

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

    proc memoryNodes(a: MdFileAdapter; uid: UserId): seq[MagmaNode] =
      let magma = a.newMagmaAdapter()
      doAssert magma != nil
      magma.graph.listNodes($uid, "memory")

    proc memoryOrigins(a: MdFileAdapter; uid: UserId): seq[MemoryOrigin] =
      a.memoryNodes(uid).mapIt(originFromMeta(it.meta))

    test "writes land in the graph and are exported to the Markdown files":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.savePreferences(uid, "language = \"pt-BR\"")
      a.appendMemory(uid, "- gosta de Nim\n")
      a.appendMemory(uid, "- mora em BH\n")
      let magma = a.newMagmaAdapter()
      let graph = magma.loadContext(uid)
      check graph.userMd == "# Ada"
      check graph.preferencesMd == "language = \"pt-BR\""
      check a.memoryNodes(uid).mapIt(it.content.strip) ==
        @["- gosta de Nim", "- mora em BH"]
      check readFile(a.userMdPath(uid)) == "# Ada"
      check readFile(a.preferencesMdPath(uid)) == "language = \"pt-BR\""
      check readFile(a.memoryMdPath(uid)) == "- gosta de Nim\n- mora em BH\n"

    test "context comes from the graph even when the files say otherwise":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.savePreferences(uid, "language = \"pt-BR\"")
      a.appendMemory(uid, "- gosta de Nim\n")
      writeFile(a.userMdPath(uid), "# Editado a mao")
      writeFile(a.preferencesMdPath(uid), "language = \"en\"")
      writeFile(a.memoryMdPath(uid), "- gosta de Nim\n\nnota escrita a mao\n")
      for _ in 1 .. 3:
        let ctx = a.loadContext(uid)
        check ctx.userMd == "# Ada"
        check ctx.preferencesMd == "language = \"pt-BR\""
        check "nota escrita a mao" notin ctx.memoryMd
        check "gosta de Nim" in ctx.memoryMd
      check a.memoryNodes(uid).len == 1

    test "loading context never adds memory nodes":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.appendMemory(uid, "- **User:** A\n  **Response:** um\n\ndois paragrafos\n")
      a.appendMemory(uid, "- **User:** B\n  **Response:** resposta\n")
      for i in 1 .. 210:
        a.appendMemory(uid, "- fato numero " & $i & "\n")
      let before = a.memoryNodes(uid).len
      check before == 212
      for _ in 1 .. 3:
        discard a.loadContext(uid)
      check a.memoryNodes(uid).len == before

    test "a paddock that only has files is imported once, tagged as markdown":
      let a = newAdapter()
      a.ensurePaddock(uid)
      writeFile(a.userMdPath(uid), "# Ada")
      writeFile(a.preferencesMdPath(uid), "language = \"pt-BR\"")
      writeFile(a.memoryMdPath(uid), "nota antiga um\n\nnota antiga dois\n")
      let first = a.loadContext(uid)
      check first.userMd == "# Ada"
      check first.preferencesMd == "language = \"pt-BR\""
      check "nota antiga um" in first.memoryMd
      check a.memoryOrigins(uid) ==
        @[MemoryOrigin(source: msMarkdown), MemoryOrigin(source: msMarkdown)]
      writeFile(a.memoryMdPath(uid), "nota antiga um\n\nnota antiga dois\n\nnota nova\n")
      let second = a.loadContext(uid)
      check "nota nova" notin second.memoryMd
      check a.memoryNodes(uid).len == 2

    test "profile and identity are answered by the graph, not by the files":
      let a = newAdapter()
      check not a.hasProfile(uid)
      a.saveUserMd(uid, "# Ada\n\n**Preferred name:** Ada\n")
      a.saveIdentity(uid, PersonalityTraits(tone: "seco"), "Guano")
      removeFile(a.userMdPath(uid))
      removeFile(a.preferencesMdPath(uid))
      check a.hasProfile(uid)
      check a.hasIdentity(uid)
      let (name, traits) = a.loadIdentity(uid)
      check name == "Guano"
      check traits.tone == "seco"
      check a.listUsers().anyIt(it.userId == uid and it.hasProfile and
                                it.preferredName == "Ada")

    test "updating a user field edits the graph copy and refreshes the export":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada\n\n**Preferred name:** Ada\n")
      writeFile(a.userMdPath(uid), "# arquivo defasado")
      a.updateUserField(uid, "Access", "revoked")
      check a.isRevoked(uid)
      let ctx = a.loadContext(uid)
      check "Preferred name:** Ada" in ctx.userMd
      check readFile(a.userMdPath(uid)) == ctx.userMd

    test "clearMemory empties the graph memory and its export":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.appendMemory(uid, "- gosta de Nim\n")
      a.clearMemory(uid)
      check a.memoryNodes(uid).len == 0
      check readFile(a.memoryMdPath(uid)) == ""
      check a.loadContext(uid).memoryMd.strip == ""
      check a.loadContext(uid).userMd == "# Ada"

    test "resetBootstrap removes profile and preferences from both":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.savePreferences(uid, "language = \"pt-BR\"")
      a.resetBootstrap(uid)
      check not a.hasProfile(uid)
      check not fileExists(a.userMdPath(uid))
      check a.loadContext(uid).preferencesMd == ""

    test "session search does not return a memory twice":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.appendMemory(uid, "- o codinome e zarabatana\n")
      let hits = a.toRuntimePort().searchSessions(uid, "zarabatana", 10, true).get()
      check hits.len == 1
      check hits[0].kind == shkMemory

    test "runtime port and adapter share one write path":
      let a = newAdapter()
      let port = a.toRuntimePort()
      port.saveUserMd(uid, "# Ada")
      port.savePreferences(uid, "language = \"pt-BR\"")
      port.appendMemory(uid, "sem origem")
      check readFile(a.userMdPath(uid)) == "# Ada"
      check readFile(a.preferencesMdPath(uid)) == "language = \"pt-BR\""
      check readFile(a.memoryMdPath(uid)).strip == "sem origem"
      check port.hasProfile(uid)
      check port.loadContext(uid).userMd == "# Ada"

    test "runtime port tags appended memory with its origin and reports success":
      let a = newAdapter()
      let port = a.toRuntimePort()
      check port.appendMemoryFrom != nil
      check port.appendMemoryFrom(
        uid, "- **User:** a\n  **Response:** b\n", turnOrigin("s7")).isOk
      port.appendMemory(uid, "sem origem")
      check a.memoryOrigins(uid) == @[turnOrigin("s7"), MemoryOrigin()]

    test "consolidated memory is tagged as consolidation":
      let a = newAdapter()
      let port = a.toRuntimePort()
      check port.appendExtractedMemory(uid, "## Consolidated memory\n- Fact: x\n").isOk
      check a.memoryOrigins(uid) == @[MemoryOrigin(source: msConsolidation)]

    test "episodes are stored in the graph":
      let a = newAdapter()
      let port = a.toRuntimePort()
      let episode = newEpisodeJournal(
        "Port episode", "The port persisted an episode.",
        1_700_000_000, 1_700_000_100, @[])
      check port.saveEpisode(uid, episode).isOk
      check a.newMagmaAdapter().loadEpisodes(uid).len == 1

    test "the explicit import replaces the graph with the edited files":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.appendMemory(uid, "- gosta de Nim\n")
      writeFile(a.userMdPath(uid), "# Ada Lovelace")
      writeFile(a.memoryMdPath(uid), "- gosta de Nim\n\nnota escrita a mao\n")
      check "nota escrita a mao" notin a.loadContext(uid).memoryMd
      ctlMemoryImport(a, $uid)
      let ctx = a.loadContext(uid)
      check ctx.userMd == "# Ada Lovelace"
      check "nota escrita a mao" in ctx.memoryMd
      check a.memoryOrigins(uid) ==
        @[MemoryOrigin(source: msMarkdown), MemoryOrigin(source: msMarkdown)]

    test "the explicit import refuses to replace the graph with empty files":
      let a = newAdapter()
      a.saveUserMd(uid, "# Ada")
      a.appendMemory(uid, "- gosta de Nim\n")
      removeFile(a.userMdPath(uid))
      removeFile(a.memoryMdPath(uid))
      ctlMemoryImport(a, $uid)
      check a.loadContext(uid).userMd == "# Ada"
      check a.memoryNodes(uid).len == 1

    test "backend without MAGMA keeps Markdown as its only store":
      let plain = MdFileAdapter(paddocksDir: root / "paddocks")
      let port = plain.toRuntimePort()
      check port.appendMemoryFrom == nil
      plain.saveUserMd(uid, "# Ada")
      plain.appendMemory(uid, "- gosta de Nim\n")
      writeFile(plain.memoryMdPath(uid), "- gosta de Nim\n\nnota a mao\n")
      check "nota a mao" in plain.loadContext(uid).memoryMd
