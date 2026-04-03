import std/[os, strutils, times, unittest]
import results
import donkey/adapters/channel/common_runtime
import donkey/adapters/memory/md_file
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
