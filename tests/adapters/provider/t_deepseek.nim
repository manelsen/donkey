## t_deepseek.nim — tests for adapters/provider/deepseek.nim
##
## Tests cover pure helpers and non-network functionality.
## Live HTTP tests require a valid DeepSeek API key and are skipped in CI.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/adapters/provider/deepseek
import donkey/domain/message

# ── caps ───────────────────────────────────────────────────────────────────────

suite "deepseek caps":
  test "reports correct provider name":
    let a = newDeepSeekAdapter("test-key", model = "deepseek-chat")
    let c = caps(a)
    check c.name == "deepseek/deepseek-chat"

  test "advertises streaming and tool calling":
    let a = newDeepSeekAdapter("test-key")
    let c = caps(a)
    check c.streaming == true
    check c.toolCalling == true
    check c.nativeTools.len == 0

  test "reports max context tokens":
    let a = newDeepSeekAdapter("test-key")
    let c = caps(a)
    check c.maxContextTokens == 64_000

# ── SSE parsing ────────────────────────────────────────────────────────────────

suite "deepseek parseDeepSeekSseLine":
  test "parses token line":
    let line = "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":1}}"
    let result = parseDeepSeekSseLine(line)
    check result.isOk
    let chunk = result.get()
    check chunk.token == "hello"
    check chunk.inputTokens == 10
    check chunk.outputTokens == 1

  test "parses [DONE] as terminal":
    let line = "data: [DONE]"
    let result = parseDeepSeekSseLine(line)
    check result.isOk
    check result.get().done == true

  test "skips empty line":
    let result = parseDeepSeekSseLine("")
    check result.isOk
    check result.get().token == ""

  test "skips non-data line":
    let result = parseDeepSeekSseLine("not a data line")
    check result.isOk
    check result.get().token == ""

  test "handles usage-only final chunk":
    let line = "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"
    let result = parseDeepSeekSseLine(line)
    check result.isOk
    let chunk = result.get()
    check chunk.inputTokens == 10
    check chunk.outputTokens == 5
    check chunk.token == ""

  test "returns error for malformed JSON":
    let line = "data: {invalid json"
    let result = parseDeepSeekSseLine(line)
    check result.isErr

# ── Response parsing ───────────────────────────────────────────────────────────

suite "deepseek parseDeepSeekResponse":
  test "parses basic response":
    let json = parseJson("""
    {
      "choices": [{
        "message": {
          "role": "assistant",
          "content": "Hello, world!"
        }
      }],
      "usage": {"prompt_tokens": 5, "completion_tokens": 6}
    }
    """)
    let result = parseDeepSeekResponse(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "Hello, world!"
    check resp.inputTokens == 5
    check resp.outputTokens == 6

  test "extracts content ignoring reasoning field":
    ## DeepSeek returns reasoning chain-of-thought that should NOT be in text
    let json = parseJson("""
    {
      "choices": [{
        "message": {
          "role": "assistant",
          "content": "The answer is 42.",
          "reasoning": "Let me think step by step... 1+1=2... therefore 42."
        }
      }],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5}
    }
    """)
    let result = parseDeepSeekResponse(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "The answer is 42."
    check resp.outputTokens == 5
    ## reasoning field is NOT in text

  test "parses tool calls":
    let json = parseJson("""
    {
      "choices": [{
        "message": {
          "role": "assistant",
          "content": "I need to search for that.",
          "tool_calls": [{
            "id": "call_123",
            "type": "function",
            "function": {
              "name": "web_search",
              "arguments": "{\"query\": \"latest news\"}"
            }
          }]
        }
      }],
      "usage": {"prompt_tokens": 20, "completion_tokens": 15}
    }
    """)
    let result = parseDeepSeekResponse(json)
    check result.isOk
    let resp = result.get()
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_123"
    check resp.toolCalls[0].name == "web_search"
    check resp.toolCalls[0].inputJson == "{\"query\": \"latest news\"}"

  test "returns error when no choices":
    let json = parseJson("""{"choices": []}""")
    let result = parseDeepSeekResponse(json)
    check result.isErr

  test "returns error when choices is not array":
    let json = parseJson("""{"choices": "not an array"}""")
    let result = parseDeepSeekResponse(json)
    check result.isErr

# ── Constructor ────────────────────────────────────────────────────────────────

suite "deepseek newDeepSeekAdapter":
  test "defaults to deepseek-chat":
    let a = newDeepSeekAdapter("key123")
    check a.model == "deepseek-chat"
    check a.apiKey == "key123"
    check a.endpoint == ""

  test "accepts custom model and endpoint":
    let a = newDeepSeekAdapter("key456", model = "deepseek-coder", endpoint = "https://test.local/v1")
    check a.model == "deepseek-coder"
    check a.apiKey == "key456"
    check a.endpoint == "https://test.local/v1"

# ── adapter object ─────────────────────────────────────────────────────────────

suite "deepseek adapter fields":
  test "apiKey field is accessible":
    let a = DeepSeekAdapter(apiKey: "secret", model: "deepseek-chat", endpoint: "")
    check a.apiKey == "secret"
    check a.model == "deepseek-chat"