import std/[os, strutils, times, unittest]
import results
import donkey/adapters/channel/common_runtime
import donkey/adapters/memory/md_file
import donkey/domain/message
import donkey/ports/provider

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
