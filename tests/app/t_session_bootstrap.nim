import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/adapters/provider/runtime_builder
import donkey/app/session_bootstrap
import donkey/domain/more_tools
import donkey/domain/message
import donkey/domain/personality
when defined(withPostgres):
  import db_connector/db_postgres
  import donkey/adapters/memory/magma_graph
  import donkey/adapters/memory/magma_memory_adapter

suite "session_bootstrap":

  test "parseProviderPrefs returns defaults when empty":
    let prefs = parseProviderPrefs("")
    check prefs.providerName == "zai-coding"
    check prefs.modelName == ""

  test "parseProviderPrefs reads provider and model from toml":
    let prefs = parseProviderPrefs("""
provider = "gemini"
model = "gemini-2.5-pro"
""")
    check prefs.providerName == "gemini"
    check prefs.modelName == "gemini-2.5-pro"

  test "buildProviderSpec applies openrouter defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "openrouter", modelName: ""))
    check spec.providerName == "openrouter"
    check spec.modelName == "openai/gpt-6.1-sol"

  test "buildProviderSpec supports openai defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "openai", modelName: ""))
    check spec.providerName == "openai"
    check spec.modelName == "gpt-6.1-sol"

  test "buildProviderSpec supports deepseek defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "deepseek", modelName: ""))
    check spec.providerName == "deepseek"
    check spec.modelName == "deepseek-4.1-flash"

  test "buildProviderSpec supports ollama defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "ollama", modelName: ""))
    check spec.providerName == "ollama"
    check spec.modelName == "llama3.3"

  test "buildProviderSpec supports groq defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "groq", modelName: ""))
    check spec.providerName == "groq"
    check spec.modelName == "llama-3.3-70b-versatile"

  test "buildProviderSpec supports zai-anthropic defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "zai-anthropic", modelName: ""))
    check spec.providerName == "zai-anthropic"
    check spec.modelName == "glm-4.7"

  test "buildProviderSpec falls back to zai-coding defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "weird", modelName: ""))
    check spec.providerName == "zai-coding"
    check spec.modelName == "glm-4.7"

  test "providerLabelFromPrefs returns provider/model label":
    let label = providerLabelFromPrefs("""
provider = "anthropic"
model = "claude-opus"
""")
    check label == "anthropic/claude-opus"

  test "providerLabelFromPrefs returns auto when prefs do not pin provider":
    check providerLabelFromPrefs("thinking = \"medium\"") == "auto"

  test "providerLabelFromPrefs uses installation defaults when prefs are empty":
    let label = providerLabelFromPrefs(
      "", ProviderDefaults(providerName: "minimax", modelName: "MiniMax-M2"))
    check label == "minimax/MiniMax-M2"

  test "applyProviderDefaults leaves explicit user prefs untouched":
    let effective = applyProviderDefaults("""
provider = "gemini"
thinking = "medium"
""", ProviderDefaults(providerName: "zai-coding", modelName: "glm-4.7"))
    check effective.contains("provider = \"gemini\"")
    check not effective.contains("provider = \"zai-coding\"")

  test "encodeSessionPayload keeps plain text when no media":
    let msg = InboundMessage(userId: UserId("u1"), text: "hello")
    check encodeSessionPayload(msg) == "hello"

  test "encodeSessionPayload encodes media payload as json":
    let msg = InboundMessage(userId: UserId("u1"), text: "hello", mediaUrl: "https://x/y.png")
    let payload = parseJson(encodeSessionPayload(msg))
    check payload["text"].getStr() == "hello"
    check payload["mediaUrl"].getStr() == "https://x/y.png"

  test "encodeSessionPayload includes recent context when present":
    let msg = InboundMessage(userId: UserId("u1"), text: "hello")
    let payload = parseJson(encodeSessionPayload(msg, "User: oi"))
    check payload["text"].getStr() == "hello"
    check payload["recentContext"].getStr() == "User: oi"

  test "sessionReplyTo only returns telegram channel id":
    let tgMsg = InboundMessage(userId: UserId("u1"), channel: ckTelegram, channelId: "123")
    let dcMsg = InboundMessage(userId: UserId("u1"), channel: ckDiscord, channelId: "abc")
    check sessionReplyTo(tgMsg) == "123"
    check sessionReplyTo(dcMsg) == "channel:abc"

  test "buildSessionTaskMsg preserves encoded payload":
    let msg = InboundMessage(userId: UserId("u1"), channel: ckTelegram, channelId: "42",
                             text: "hi", mediaUrl: "https://x/z.png")
    let task = buildSessionTaskMsg(msg, "m1")
    let payload = parseJson(task.payload)
    check task.id == "m1"
    check payload["text"].getStr() == "hi"
    check payload["mediaUrl"].getStr() == "https://x/z.png"
    check task.replyTo == "42"

  test "loadRecentContext reads latest user and assistant messages":
    let tmpDir = getTempDir() / "donkey_recent_context"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-recent")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    var history = newHistory()
    history.addUser("primeira")
    history.addAssistant("resposta 1")
    history.addToolResult("t1", "bash", "pwd")
    history.addUser("segunda")
    history.addAssistant("resposta 2")
    memory.saveSession(userId, "100", history)
    var history2 = newHistory()
    history2.addUser("terceira")
    history2.addAssistant("resposta 3")
    memory.saveSession(userId, "200", history2)
    let recent = loadRecentContext(memory.toRuntimePort(), userId)
    check "User: resposta" notin recent
    check recent.contains("User: resposta 3") == false
    check recent.contains("User: terceira")
    check recent.contains("Assistant: resposta 3")
    check recent.contains("User: segunda")
    check recent.contains("Assistant: resposta 2")

  test "loadSessionContext reads prefs and paddock":
    let tmpDir = getTempDir() / "donkey_session_bootstrap_ctx"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-session-bootstrap")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, """
provider = "gemini"
model = "gemini-2.5-flash"
""")
    let ctx = loadSessionContext(memory.toRuntimePort(), userId)
    check ctx.preferencesMd.contains("provider = \"gemini\"")
    check ctx.paddockDir == memory.paddockDir(userId)
    check ctx.providerLabel == "gemini/gemini-2.5-flash"

  test "loadSessionContext applies provider defaults when prefs are empty":
    let tmpDir = getTempDir() / "donkey_session_bootstrap_ctx_defaults"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-session-bootstrap-defaults")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let ctx = loadSessionContext(
      memory.toRuntimePort(), userId,
      ProviderDefaults(providerName: "zai-coding", modelName: "glm-4.7"))
    check ctx.providerLabel == "zai-coding/glm-4.7"

  test "withNativeTools appends native tool descriptions":
    let base = startSessionToolBundle(@[], @[])
    let bundled = withNativeTools(base)
    check bundled.tools.len >= nativeSessionTools().len
    check bundled.tools.anyIt(it.name == BashToolName)
    for legacyName in [
      FindToolName,
      GrepToolName,
      SedToolName,
      WcToolName,
      HeadToolName,
      TailToolName,
      SortToolName,
      CpToolName,
      MvToolName,
      RmToolName,
      MkdirToolName,
    ]:
      check not bundled.tools.anyIt(it.name == legacyName)
    for name in [
      FsListToolName,
      FsReadToolName,
      FsWriteToolName,
      TextSearchToolName,
      TextReadToolName,
      TextReplaceToolName,
      JsonQueryToolName,
      TableQueryToolName,
      HttpFetchToolName,
      ArchiveExtractToolName,
      ArchiveCreateToolName,
    ]:
      check bundled.tools.anyIt(it.name == name)

  test "nativeSessionTools only exposes web_search when Brave is configured":
    let hadBrave = existsEnv("BRAVE_API_KEY")
    let previous = getEnv("BRAVE_API_KEY")
    defer:
      if hadBrave:
        putEnv("BRAVE_API_KEY", previous)
      else:
        delEnv("BRAVE_API_KEY")

    delEnv("BRAVE_API_KEY")
    check not nativeSessionTools().anyIt(it.name == WebSearchToolName)

    putEnv("BRAVE_API_KEY", "test-brave-key")
    check nativeSessionTools().anyIt(it.name == WebSearchToolName)

  test "loadSessionBootstrapPlan maps context fields":
    let plan = loadSessionBootstrapPlan(SessionContext(
      preferencesMd: "provider = \"zai-coding\"",
      paddockDir: "/tmp/paddock-x",
      providerLabel: "zai-coding",
    ))
    check plan.preferencesMd.contains("provider")
    check plan.paddockDir == "/tmp/paddock-x"
    check plan.providerLabel == "zai-coding"

  test "buildProviderBundle exposes streamFn only for providers that implement it":
    let openrouter = buildProviderBundle("provider = \"openrouter\"", runtime_builder.buildProviderBundle)
    let anthropic = buildProviderBundle("provider = \"anthropic\"", runtime_builder.buildProviderBundle)
    let zaiAnthropic = buildProviderBundle("provider = \"zai-anthropic\"", runtime_builder.buildProviderBundle)
    let openai = buildProviderBundle("provider = \"openai\"", runtime_builder.buildProviderBundle)
    let deepseek = buildProviderBundle("provider = \"deepseek\"", runtime_builder.buildProviderBundle)
    let groq = buildProviderBundle("provider = \"groq\"", runtime_builder.buildProviderBundle)
    let ollama = buildProviderBundle("provider = \"ollama\"", runtime_builder.buildProviderBundle)
    let gemini = buildProviderBundle("provider = \"gemini\"", runtime_builder.buildProviderBundle)
    let minimax = buildProviderBundle("provider = \"minimax\"", runtime_builder.buildProviderBundle)
    let zaiCoding = buildProviderBundle("provider = \"zai-coding\"", runtime_builder.buildProviderBundle)
    check openrouter.streamFn != nil
    check anthropic.streamFn != nil
    check zaiAnthropic.streamFn != nil
    check openai.streamFn != nil
    check deepseek.streamFn != nil
    check groq.streamFn != nil
    check ollama.streamFn != nil
    check gemini.streamFn == nil
    check minimax.streamFn == nil
    check zaiCoding.streamFn == nil

when defined(withPostgres):
  const testDsn = "host=localhost port=5432 dbname=donkey_test"

  proc setupGraph() =
    let g = newMagmaGraph(testDsn)
    g.migrate()

  proc cleanGraph() =
    let g = newMagmaGraph(testDsn)
    let db = g.openDb()
    defer: db.close()
    try:
      db.exec(sql"DELETE FROM magma_edges")
      db.exec(sql"DELETE FROM magma_nodes")
    except CatchableError:
      discard

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} = @[]

  suite "session_bootstrap with multigraph memory":

    test "loadSessionContext prefers multigraph memory when graph has data":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_session_bootstrap_magma_first"
      let userId = UserId("u-session-bootstrap-magma-first")
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir)
      createDir(tmpDir / $userId)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      writeFile(tmpDir / $userId / "PREFERENCES.md", """
provider = "anthropic"
model = "claude-opus-4-6"
""")

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let magma = newMagmaMemoryAdapter(testDsn, fakeEmbedFn)
      magma.savePreferences(userId, """
provider = "gemini"
model = "gemini-2.5-pro"
""")
      magma.saveUserMd(userId, "# Graph User")
      magma.appendMemory(userId, "graph memory")

      let ctx = loadSessionContext(memory.toRuntimePort(), userId)
      check ctx.preferencesMd.contains("provider = \"gemini\"")
      check ctx.providerLabel == "gemini/gemini-2.5-pro"

    test "loadSessionContext bootstraps multigraph memory from markdown when graph is empty":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_session_bootstrap_magma_bootstrap"
      let userId = UserId("u-session-bootstrap-magma-bootstrap")
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir / $userId)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      writeFile(tmpDir / $userId / "USER.md", "# Bootstrap User")
      writeFile(tmpDir / $userId / "PREFERENCES.md", """
provider = "gemini"
model = "gemini-2.5-flash"
""")
      writeFile(tmpDir / $userId / "MEMORY.md", "bootstrap memory A\n\nbootstrap memory B")

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let ctx = loadSessionContext(memory.toRuntimePort(), userId)
      check ctx.preferencesMd.contains("provider = \"gemini\"")
      check ctx.providerLabel == "gemini/gemini-2.5-flash"

      let magma = newMagmaMemoryAdapter(testDsn, fakeEmbedFn)
      let graphCtx = magma.loadContext(userId)
      check graphCtx.userMd.contains("Bootstrap User")
      check graphCtx.preferencesMd.contains("gemini-2.5-flash")
      check graphCtx.memoryMd.contains("bootstrap memory A")
      check graphCtx.memoryMd.contains("bootstrap memory B")

    test "runtime port writes to multigraph without shadow markdown files":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_session_bootstrap_runtime_graph_only"
      let userId = UserId("u-session-bootstrap-runtime-graph-only")
      if dirExists(tmpDir):
        removeDir(tmpDir)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let port = memory.toRuntimePort()
      port.saveUserMd(userId, "# Graph User")
      port.savePreferences(userId, """
provider = "gemini"
model = "gemini-2.5-flash"
""")
      port.appendMemory(userId, "graph-only memory")

      check not fileExists(memory.userMdPath(userId))
      check not fileExists(memory.preferencesMdPath(userId))
      check not fileExists(memory.memoryMdPath(userId))

      let graphCtx = newMagmaMemoryAdapter(testDsn, fakeEmbedFn).loadContext(userId)
      check graphCtx.userMd == "# Graph User"
      check graphCtx.preferencesMd.contains("gemini-2.5-flash")
      check graphCtx.memoryMd.contains("graph-only memory")

    test "runtime identity and clearMemory use multigraph-backed preferences and memories":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_session_bootstrap_runtime_identity_graph"
      let userId = UserId("u-session-bootstrap-runtime-identity-graph")
      if dirExists(tmpDir):
        removeDir(tmpDir)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let port = memory.toRuntimePort()
      port.savePreferences(userId, "provider = \"openrouter\"")
      port.appendMemory(userId, "memory to clear")
      port.saveIdentity(userId, PersonalityTraits(
        energy: "warm",
        tone: "direct",
        length: "short",
        initiative: "medium",
      ), "Donkey")

      let (name, traits) = port.loadIdentity(userId)
      check name == "Donkey"
      check traits.energy == "warm"
      check not fileExists(memory.preferencesMdPath(userId))

      port.clearMemory(userId)
      let graphCtx = newMagmaMemoryAdapter(testDsn, fakeEmbedFn).loadContext(userId)
      check graphCtx.memoryMd == ""
      check graphCtx.preferencesMd.contains("agent_name = \"Donkey\"")
