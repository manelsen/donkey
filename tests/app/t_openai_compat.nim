## /v1/chat/completions reply tests with a fake completion function.

import std/[json, strutils, unittest]
import donkey/app/openai_compat_runtime
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

proc stubComplete(text: string): CompleteFn =
  result = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    ok(CompletionResponse(text: text, inputTokens: 4, outputTokens: 6))

proc failingComplete(): CompleteFn =
  result = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    err("provider down")

const Body = """{"model":"gpt","messages":[{"role":"user","content":"oi"}]}"""

suite "openai chat reply":

  test "a successful completion becomes a chat.completion":
    let reply = chatReply(Body, stubComplete("olá"), "donkey/default", 100,
                          id = "chatcmpl-test")
    check reply.status == "200 OK"
    let node = parseJson(reply.body)
    check node["id"].getStr() == "chatcmpl-test"
    check node["choices"][0]["message"]["content"].getStr() == "olá"
    check node["usage"]["total_tokens"].getInt() == 10

  test "a malformed request is a 400":
    let reply = chatReply("not json", stubComplete("x"), "m", 100)
    check reply.status == "400 Bad Request"
    check parseJson(reply.body)["error"]["message"].getStr().contains("JSON")

  test "an unsupported shape is a 400":
    let reply = chatReply(
      """{"messages":[{"role":"user","content":"oi"}],"stream":true}""",
      stubComplete("x"), "m", 100)
    check reply.status == "400 Bad Request"
    check parseJson(reply.body)["error"]["message"].getStr().contains("streaming")

  test "a provider failure is a 502":
    let reply = chatReply(Body, failingComplete(), "m", 100)
    check reply.status == "502 Bad Gateway"
    check parseJson(reply.body)["error"]["message"].getStr() == "provider down"

  test "a missing backend is a 503":
    let reply = chatReply(Body, nil, "m", 100)
    check reply.status == "503 Service Unavailable"
    check parseJson(reply.body)["error"]["type"].getStr() == "server_error"
