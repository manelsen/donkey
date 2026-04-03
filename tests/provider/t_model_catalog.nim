import std/[os, sequtils, unittest]
import results
import donkey/adapters/provider/model_catalog
import donkey/ports/provider

suite "model_catalog":

  test "parseSimpleListCatalog parses openai style list and sorts free first":
    let body = """
{"object":"list","data":[
  {"id":"paid-model","object":"model"},
  {"id":"free-model-free","object":"model"},
  {"id":"models/prefixed-model","object":"model"}
]}
"""
    let parsed = parseSimpleListCatalog("zen", body).get()
    check parsed.len == 3
    check parsed[0].modelName == "free-model-free"
    check parsed[0].isFree
    check parsed[1].modelName == "paid-model"
    check parsed[2].modelName == "prefixed-model"

  test "parseSimpleListCatalog accepts nested data list":
    let body = """
{"data":{"list":[
  {"id":"glm-5","display_name":"GLM 5"},
  {"id":"glm-4.7","display_name":"GLM 4.7"}
]}}
"""
    let parsed = parseSimpleListCatalog("zai", body).get()
    check parsed.len == 2
    check parsed[0].providerName == "zai"
    check parsed[0].modelName == "glm-4.7"
    check parsed[1].label == "GLM 5"

  test "parseSimpleListCatalog rejects bodies without model array":
    check parseSimpleListCatalog("zen", """{"ok":true}""").isErr

  test "parseOllamaTagsCatalog extracts model names":
    let body = """
{"models":[
  {"name":"llama3:latest","modified_at":"2024-01-01T00:00:00Z","size":4000000000},
  {"name":"mistral:7b","modified_at":"2024-01-02T00:00:00Z","size":4000000000}
]}
"""
    let parsed = parseOllamaTagsCatalog(body).get()
    check parsed.len == 2
    ## sorted alphabetically (both free)
    check parsed[0].modelName == "llama3:latest"
    check parsed[0].isFree
    check parsed[0].providerName == "ollama"

  test "parseOllamaTagsCatalog rejects missing models array":
    check parseOllamaTagsCatalog("""{"ok":true}""").isErr

  test "parseOpenRouterCatalog keeps pricing metadata":
    let body = """
{"data":[
  {"id":"cheap-model","name":"cheap-model","pricing":{"prompt":"0.0000001","completion":"0.0000002"}},
  {"id":"free-model:free","name":"free-model:free","pricing":{"prompt":"0","completion":"0"}}
]}
"""
    let parsed = parseOpenRouterCatalog(body).get()
    check parsed.len == 2
    check parsed[0].modelName == "free-model:free"
    check parsed[0].hasPricing
    check parsed[0].inputCostMicrosPer1k == 0
    check parsed[1].modelName == "cheap-model"
    check parsed[1].hasPricing
    check parsed[1].inputCostMicrosPer1k == 100
    check parsed[1].outputCostMicrosPer1k == 200

  test "buildModelCatalogLoader exposes zai-anthropic fallback catalog without keys":
    let savedZaiAnthropic = getEnv("ZAI_ANTHROPIC_API_KEY")
    let savedAnthropicAuth = getEnv("ANTHROPIC_AUTH_TOKEN")
    let savedZaiCoding = getEnv("ZAI_CODING_API_KEY")
    let savedZai = getEnv("ZAI_API_KEY")
    let savedZhipu = getEnv("ZHIPU_API_KEY")
    defer:
      putEnv("ZAI_ANTHROPIC_API_KEY", savedZaiAnthropic)
      putEnv("ANTHROPIC_AUTH_TOKEN", savedAnthropicAuth)
      putEnv("ZAI_CODING_API_KEY", savedZaiCoding)
      putEnv("ZAI_API_KEY", savedZai)
      putEnv("ZHIPU_API_KEY", savedZhipu)

    putEnv("ZAI_ANTHROPIC_API_KEY", "")
    putEnv("ANTHROPIC_AUTH_TOKEN", "")
    putEnv("ZAI_CODING_API_KEY", "")
    putEnv("ZAI_API_KEY", "")
    putEnv("ZHIPU_API_KEY", "")

    let loader = buildModelCatalogLoader()
    let loaded = loader("zai-anthropic").get()
    check loaded.source == mcsFallback
    check loaded.entries.len >= 1
    check loaded.entries.anyIt(it.modelName == "glm-4.7")
