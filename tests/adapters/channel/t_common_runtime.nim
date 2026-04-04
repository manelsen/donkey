import std/[os, sequtils, strutils, tables, times, unittest]
import results
import donkey/adapters/channel/common_runtime
import donkey/adapters/memory/md_file
import donkey/config/clawhub_registry
import donkey/config/skills_registry
import donkey/domain/message
import donkey/ports/provider
when defined(withPostgres):
  import db_connector/db_postgres
  import donkey/adapters/memory/magma_graph
  import donkey/adapters/memory/magma_memory_adapter

suite "common_runtime":

  test "parseModelsArgs validates provider and model":
    let parsed = parseModelsArgs("gemini gemini-2.5-pro").get()
    check parsed[0] == "gemini"
    check parsed[1] == "gemini-2.5-pro"
    check parseModelsArgs("gemini nope").isErr
    let zaiAnthropic = parseModelsArgs("zai-anthropic glm-4.7").get()
    check zaiAnthropic[0] == "zai-anthropic"
    check zaiAnthropic[1] == "glm-4.7"

  test "parseModelsProviderArg validates provider-only route":
    check parseModelsProviderArg("groq").get() == "groq"
    check parseModelsProviderArg("groq llama").isErr
    check parseModelsProviderArg("nope").isErr

  test "applyModelsTextCommand persists selection":
    let tmpDir = getTempDir() / "donkey_common_runtime_models"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-models")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let text = applyModelsTextCommand(memory, userId, "gemini gemini-2.5-pro").get()
    check text.contains("gemini / gemini-2.5-pro")
    check getCurrentProviderModel(memory, userId) == ("gemini", "gemini-2.5-pro")

  test "applyModelsTextCommand shows provider catalog with single arg":
    let tmpDir = getTempDir() / "donkey_common_runtime_provider_catalog"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-provider-catalog")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let loader: ModelCatalogLoader =
      proc(providerName: string): Result[ModelCatalogResult, string] =
        ok(ModelCatalogResult(
          entries: @[
            ModelCatalogEntry(providerName: providerName, modelName: "free-model", label: "free-model", isFree: true, available: true),
            ModelCatalogEntry(providerName: providerName, modelName: "paid-model", label: "paid-model", isFree: false, available: true),
          ],
          source: mcsLive,
          fetchedAtUnix: getTime().toUnix(),
        ))
    let text = applyModelsTextCommand(memory, userId, "groq", loader).get()
    check text.contains("Provider: groq")
    check text.contains("`free-model` [free]")
    check text.contains("Fonte: live")

  test "normalizeModelCatalog treats ZAI provider aliases as the same catalog family":
    let normalized = normalizeModelCatalog("zai-anthropic", @[
      ModelCatalogEntry(providerName: "zai-coding", modelName: "glm-4.7", label: "GLM 4.7", available: true),
      ModelCatalogEntry(providerName: "zai-anthropic", modelName: "glm-4.7", label: "GLM 4.7 duplicate", available: true),
      ModelCatalogEntry(providerName: "zai", modelName: "glm-5", label: "GLM 5", available: true),
    ])
    check normalized.len == 2
    check normalized.anyIt(it.modelName == "glm-4.7")
    check normalized.anyIt(it.modelName == "glm-5")

  test "buildModelPageText shows explicit empty state when catalog has no models":
    let text = buildModelPageText(
      "zai-anthropic",
      0,
      @[],
      ModelCatalogResult(source: mcsLive, fetchedAtUnix: getTime().toUnix()),
    )
    check text.contains("Modelos de zai-anthropic")
    check text.contains("Fonte: live")
    check text.contains("Nenhum modelo disponível para este provider no catálogo atual.")

  test "applyThinkTextCommand persists level":
    let tmpDir = getTempDir() / "donkey_common_runtime_think"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-think")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let text = applyThinkTextCommand(memory, userId, "high").get()
    check text.contains("high")
    check getCurrentThinkLevel(memory, userId) == "high"

  test "applyBudgetTextCommand persists policy":
    let tmpDir = getTempDir() / "donkey_common_runtime_budget"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-budget")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let text = applyBudgetTextCommand(memory, userId, "cheap-first").get()
    check text.contains("cheap-first")
    check getCurrentBudgetPolicy(memory, userId) == "cheap-first"

  test "buildModelsHelpText shows catalog source":
    let tmpDir = getTempDir() / "donkey_common_runtime_catalog"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-catalog")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let loader: ModelCatalogLoader =
      proc(providerName: string): Result[ModelCatalogResult, string] =
        ok(ModelCatalogResult(
          entries: @[
            ModelCatalogEntry(providerName: providerName, modelName: "model-a", label: "model-a", isFree: true, available: true)
          ],
          source: mcsCache,
          fetchedAtUnix: getTime().toUnix(),
        ))
    let text = buildModelsHelpText(memory, userId, loader)
    check text.contains("Fonte: cache")
    check text.contains("model-a")

  test "buildModelsHelpText shows auto routing preview when provider is not pinned":
    let tmpDir = getTempDir() / "donkey_common_runtime_auto_models"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-auto-models")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "thinking = \"medium\"\nbudget = \"cheap-first\"")
    let text = buildModelsHelpText(memory, userId)
    check text.contains("Provider atual: auto")
    check text.contains("cheap-first")

  test "buildTextStatusText shows auto routing preview when provider is not pinned":
    let tmpDir = getTempDir() / "donkey_common_runtime_auto_status"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-common-auto-status")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "thinking = \"high\"\nbudget = \"quality-first\"")
    let text = buildTextStatusText(memory, userId, 3, 1, 0)
    check text.contains("Provider: auto [quality-first]")

  suite "common_runtime skills":

    proc setupInstalledRemoteSkill(home, slug: string;
                                   scriptsToml = "";
                                   scriptFile = "main.ts") =
      let skillDir = remoteSkillDir(home, slug)
      createDir(skillDir)
      writeFile(skillDir / "SKILL.md", "# " & slug & "\n")
      if scriptsToml.len > 0:
        writeFile(skillDir / "skills.toml", scriptsToml)
      writeFile(skillDir / scriptFile, "console.log('ok')\n")
      writeRemoteSkillOrigin(skillDir, RemoteSkillOrigin(
        version: 1,
        registry: ClawhubDefaultRegistry,
        slug: slug,
        installedVersion: "1.2.3",
        installedAt: getTime().toUnix(),
      ))
      var lock = readRemoteSkillLockfile(home)
      lock.skills[slug] = RemoteSkillLockEntry(version: "1.2.3", installedAt: getTime().toUnix())
      writeRemoteSkillLockfile(home, lock)

    test "applySkillTextCommand shows help and list":
      let home = getTempDir() / "donkey_common_runtime_skill_help"
      let memory = MdFileAdapter(paddocksDir: home / "paddocks")
      let userId = UserId("u-common-skill-help")
      defer:
        if dirExists(home):
          removeDir(home)

      discard saveSkillEntry(memory.userSkillsPath(userId), SkillManifest(
        name: "local-browser",
        version: "0.1.0",
        script: "/tmp/browser.ts",
      ))
      setupInstalledRemoteSkill(home, "remote-browser")

      let help = applySkillTextCommand(memory, userId, "", homeDir = home).get()
      check help.contains("/skill install <slug>")

      let listing = applySkillTextCommand(memory, userId, "list", homeDir = home).get()
      check listing.contains("local-browser")
      check listing.contains("remote-browser")

    test "applySkillTextCommand enables installed remote skills for the current user":
      let home = getTempDir() / "donkey_common_runtime_skill_enable"
      let memory = MdFileAdapter(paddocksDir: home / "paddocks")
      let userId = UserId("u-common-skill-enable")
      defer:
        if dirExists(home):
          removeDir(home)

      setupInstalledRemoteSkill(
        home,
        "remote-browser",
        scriptsToml = """
[[skill]]
name = "remote-browser"
version = "1.2.3"
script = "main.ts"
permissions = ["--allow-net=clawhub.ai"]
""",
      )

      let reply = applySkillTextCommand(memory, userId, "enable remote-browser", homeDir = home).get()
      check reply.contains("habilitada")
      let enabled = loadSkillRegistry(memory.userSkillsPath(userId))
      check enabled.len == 1
      check enabled[0].name == "remote-browser"
      check enabled[0].script == remoteSkillDir(home, "remote-browser") / "main.ts"
      check enabled[0].permissions == @["--allow-net=clawhub.ai"]

    test "applySkillTextCommand installs and enables remote skills via injected backend":
      let home = getTempDir() / "donkey_common_runtime_skill_install"
      let memory = MdFileAdapter(paddocksDir: home / "paddocks")
      let userId = UserId("u-common-skill-install")
      defer:
        if dirExists(home):
          removeDir(home)

      let fakeInstall =
        proc(homeDir, registry, slug: string): Result[RemoteSkillOrigin, string] {.gcsafe.} =
          setupInstalledRemoteSkill(homeDir, slug)
          ok(RemoteSkillOrigin(
            version: 1,
            registry: registry,
            slug: slug,
            installedVersion: "1.2.3",
            installedAt: getTime().toUnix(),
          ))

      let reply = applySkillTextCommand(
        memory,
        userId,
        "install remote-browser",
        homeDir = home,
        installBackend = fakeInstall,
      ).get()

      check reply.contains("instalada e habilitada")
      let enabled = loadSkillRegistry(memory.userSkillsPath(userId))
      check enabled.len == 1
      check enabled[0].script == remoteSkillDir(home, "remote-browser") / "main.ts"

when defined(withPostgres):
  const testDsn = "host=localhost port=5432 dbname=donkey_test"

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} =
    for i in 0 ..< 4096:
      result.add(if i == 0: 1.0'f32 else: 0.0'f32)

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

  proc stubDoctorCompleteBuilder(preferencesMd: string): CompleteFn {.gcsafe.} =
    proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
      ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))

  suite "common_runtime doctor":

    test "buildDoctorReport prefers multigraph memory stats over paddock file counts":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_common_runtime_doctor"
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir)
      createDir(tmpDir / "u-common-memory-view")
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let userId = UserId("u-common-doctor")
      let magma = newMagmaMemoryAdapter(testDsn, fakeEmbedFn)
      magma.saveUserMd(userId, "# Ada")
      magma.savePreferences(userId, "language = \"nim\"")
      magma.appendMemory(userId, "m1")

      let report = buildDoctorReport(
        memory,
        stubDoctorCompleteBuilder,
        userId,
        toolsCount = 4,
        toolClientsCount = 1,
        sessionCount = 2,
      )

      check report.contains("🧠 Multigraph Memory:")
      check report.contains("nodes=3")
      check report.contains("embeddings=3")
      check report.contains("📁 Memory dir (debug):")

    test "buildMemoryViewText prefers multigraph memory when available":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_common_runtime_memory_view"
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let userId = UserId("u-common-memory-view")
      let magma = newMagmaMemoryAdapter(testDsn, fakeEmbedFn)
      magma.appendMemory(userId, "graph-backed memory")
      createDir(tmpDir / $userId)
      writeFile(tmpDir / $userId / "MEMORY.md", "markdown memory only")

      let view = buildMemoryViewText(memory, userId)
      check view.contains("Multigraph Memory")
      check view.contains("graph-backed memory")
      check "markdown memory only" notin view

    test "buildMemoryViewText falls back to markdown when graph is empty":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_common_runtime_memory_fallback"
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir / "u-common-memory-fallback")
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let userId = UserId("u-common-memory-fallback")
      writeFile(tmpDir / $userId / "MEMORY.md", "markdown fallback memory")

      let view = buildMemoryViewText(memory, userId)
      check view.contains("Markdown fallback")
      check view.contains("markdown fallback memory")

    test "buildMemoryViewText shows profile and preferences when episodic memory is empty":
      setupGraph()
      cleanGraph()
      let tmpDir = getTempDir() / "donkey_common_runtime_memory_profile_only"
      if dirExists(tmpDir):
        removeDir(tmpDir)
      createDir(tmpDir)
      defer:
        if dirExists(tmpDir):
          removeDir(tmpDir)

      let memory = MdFileAdapter(paddocksDir: tmpDir, magmaDsn: testDsn)
      let userId = UserId("u-common-memory-profile-only")
      let magma = newMagmaMemoryAdapter(testDsn, fakeEmbedFn)
      magma.saveUserMd(userId, "# Void\n**Timezone:** America/Sao_Paulo")
      magma.savePreferences(userId, "language = \"pt-BR\"")

      let view = buildMemoryViewText(memory, userId)
      check view.contains("Multigraph Memory")
      check view.contains("👤 Perfil")
      check view.contains("America/Sao_Paulo")
      check view.contains("⚙️ Preferências")
      check view.contains("language = \"pt-BR\"")
      check view.contains("Nenhuma memória salva ainda.")
