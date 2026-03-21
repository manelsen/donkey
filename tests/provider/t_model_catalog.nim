import std/unittest
import results
import donkey/adapters/provider/model_catalog

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
