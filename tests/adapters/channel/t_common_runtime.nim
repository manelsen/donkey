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
