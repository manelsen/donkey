## MCP sampling, the pure half (PRD-roadmap E5.1, E5.3): a server's
## `sampling/createMessage` request read, turned into a model request without
## tools, answered in MCP's shape, summarised for the person's approval, and
## counted against a daily token cap per server.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/tools/mcp_sampling_pure

proc request(maxTokens = 200; system = ""): JsonNode =
  result = %* {"messages": [
      {"role": "user", "content": {"type": "text", "text": "Resuma este texto: abc"}},
      {"role": "assistant", "content": {"type": "text", "text": "Qual texto?"}},
      {"role": "user", "content": {"type": "text", "text": "O de cima."}}],
    "maxTokens": maxTokens,
    "modelPreferences": {"hints": [{"name": "claude"}]}}
  if system.len > 0:
    result["systemPrompt"] = %system

proc runTests*() =
  suite "mcp sampling — the request":

    test "messages, system prompt and the token limit are read":
      let r = parseSamplingRequest(request(system = "Seja breve.")).get
      check r.messages.len == 3
      check r.messages[0].role == "user" and r.messages[1].role == "assistant"
      check r.messages[2].text == "O de cima."
      check r.systemPrompt == "Seja breve."
      check r.maxTokens == 200

    test "only text is sampled; anything else is refused with a reason":
      var img = request()
      img["messages"][0]["content"] = %* {"type": "image", "data": "x", "mimeType": "image/png"}
      check parseSamplingRequest(img).error.contains("text")
      check parseSamplingRequest(%* {"messages": []}).isErr
      check parseSamplingRequest(%* {"maxTokens": 5}).isErr
      var bad = request()
      bad["messages"][0]["role"] = %"system"
      check parseSamplingRequest(bad).isErr

    test "the model request has no tools and a capped token limit":
      let r = parseSamplingRequest(request(maxTokens = 50_000, system = "S")).get
      let req = toCompletionRequest(r, maxTokensCap = 1_000)
      check req.maxTokens == 1_000
      check req.tools.len == 0
      check req.system.contains("S")
      check req.messages.len == 3

    test "the answer has MCP's shape":
      let j = samplingResult("4", model = "gpt-x")
      check j["role"].getStr == "assistant"
      check j["content"]["type"].getStr == "text"
      check j["content"]["text"].getStr == "4"
      check j["model"].getStr == "gpt-x"
      check j["stopReason"].getStr == "endTurn"

  suite "mcp sampling — what the person is shown":

    test "the summary names the server and quotes the request, clipped":
      let r = parseSamplingRequest(request()).get
      let s = approvalSummary("filesystem", r)
      check "filesystem" in s
      check "O de cima." in s
      check "200" in s
      var long = request()
      long["messages"][2]["content"]["text"] = %("palavra ".repeat(200))
      check approvalSummary("x", parseSamplingRequest(long).get).len < 700

    test "a server is known by its command and arguments, not its name":
      check serverIdentity("npx", @["-y", "srv"]) == serverIdentity("npx", @["-y", "srv"])
      check serverIdentity("npx", @["-y", "srv"]) != serverIdentity("npx", @["-y", "other"])
      check samplingApprovalKey(serverIdentity("npx", @["a"])).startsWith("sampling:")

  suite "mcp sampling — the daily cap":

    test "a request fits until the server's tokens for the day run out":
      var b = SamplingBudget(dailyCap: 1_000)
      check b.allows("srv", 600, dayMs = 0)
      b.spend("srv", 600, dayMs = 0)
      check not b.allows("srv", 600, dayMs = 0)
      check b.allows("other", 600, dayMs = 0)
      check b.allows("srv", 600, dayMs = 86_400_000)   ## a new day

when isMainModule:
  runTests()
