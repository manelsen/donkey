import std/[json, unittest]
import donkey/core/tooling/structured_tool_result
import donkey/domain/message

suite "structured tool result contract":

  test "success envelope wraps data with stable metadata":
    let payload = %*{
      "items": [
        {"path": "src/main.nim", "kind": "file"},
        {"path": "src/lib/", "kind": "dir"}
      ]
    }
    let result = successToolResult(payload)
    let encoded = result.toJson()
    let parsed = parseJson(encoded)

    check parsed["ok"].getBool()
    check parsed["status"].getStr() == "output"
    check parsed["contract"].getStr() == "donkey.native_tool/v1"
    check parsed["data"]["items"].len == 2
    check not parsed.hasKey("error")

  test "usage error envelope is distinct from operational error":
    let usage = usageErrorToolResult("path is required")
    let operational = operationalErrorToolResult("timeout")

    let usageJson = parseJson(usage.toJson())
    let operationalJson = parseJson(operational.toJson())

    check not usageJson["ok"].getBool()
    check usageJson["status"].getStr() == "usage_error"
    check usageJson["error"]["message"].getStr() == "path is required"
    check not usageJson.hasKey("data")

    check not operationalJson["ok"].getBool()
    check operationalJson["status"].getStr() == "operational_error"
    check operationalJson["error"]["message"].getStr() == "timeout"
    check not operationalJson.hasKey("data")

  test "result kind enum includes usage_error label":
    check toolResultKindLabel(trkUsageError) == "usage_error"

  test "output envelopes are composable JSON objects":
    let payload = %*{
      "rows": [
        {"path": "a.txt", "line": 1, "text": "alpha"},
        {"path": "b.txt", "line": 2, "text": "beta"}
      ],
      "count": 2
    }
    let parsed = parseJson(successToolResult(payload).toJson())
    check parsed.kind == JObject
    check parsed["data"]["count"].getInt() == 2
    check parsed["data"]["rows"][1]["text"].getStr() == "beta"
