## t_openai.nim — tests for adapters/provider/openai.nim
##
## Tests cover pure helpers and non-network functionality.
## Live HTTP tests require a valid OpenAI API key and are skipped in CI.

import std/unittest
import donkey/core/pipeops
import donkey/adapters/provider/openai

# ── caps ───────────────────────────────────────────────────────────────────────

suite "openai caps":
  test "reports correct provider name":
    let a = newOpenAIAdapter("test-key", model = "gpt-4o")
    let c = caps(a)
    check c.name == "openai/gpt-4o"
    check a.displayName == "OpenAI"

  test "supports custom providerName such as Groq":
    let a = newOpenAIAdapter("test-key", model = "llama-3.3-70b-versatile", providerName = "Groq")
    let c = caps(a)
    check c.name == "groq/llama-3.3-70b-versatile"
    check a.displayName == "Groq"

  test "advertises streaming and tool calling":
    let a = newOpenAIAdapter("test-key")
    let c = caps(a)
    check c.streaming == true
    check c.toolCalling == true
    check c.nativeTools.len == 0

# ── SSE parsing ────────────────────────────────────────────────────────────────

suite "openai parseOpenAISseLine":
  test "parses token line":
    let line = "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":1}}"
    let result = parseOpenAISseLine(line)
    check result.isOk
    let chunk = result.get()
    check chunk.token == "hello"
    check chunk.inputTokens == 10
    check chunk.outputTokens == 1

  test "parses [DONE] as terminal":
    let line = "data: [DONE]"
    let result = parseOpenAISseLine(line)
    check result.isOk
    check result.get().done == true

  test "skips empty line":
    let result = parseOpenAISseLine("")
    check result.isOk
    check result.get().token == ""

  test "skips non-data line":
    let result = parseOpenAISseLine("not a data line")
    check result.isOk
    check result.get().token == ""

  test "handles usage-only final chunk":
    let line = "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"
    let result = parseOpenAISseLine(line)
    check result.isOk
    let chunk = result.get()
    check chunk.inputTokens == 10
    check chunk.outputTokens == 5
    check chunk.token == ""

  test "returns error for malformed JSON":
    let line = "data: {invalid json"
    let result = parseOpenAISseLine(line)
    check result.isErr

# ── constructor ────────────────────────────────────────────────────────────────

suite "openai newOpenAIAdapter":
  test "defaults to gpt-6.1-sol":
    let a = newOpenAIAdapter("key123")
    check a.model == "gpt-6.1-sol"
    check a.apiKey == "key123"
    check a.endpoint == ""

  test "accepts custom model and endpoint":
    let a = newOpenAIAdapter("key456", model = "gpt-4", endpoint = "https://test.local/v1")
    check a.model == "gpt-4"
    check a.apiKey == "key456"
    check a.endpoint == "https://test.local/v1"

# ── adapter object ─────────────────────────────────────────────────────────────

suite "openai adapter fields":
  test "apiKey field is accessible":
    let a = OpenAIAdapter(apiKey: "secret", model: "gpt-3.5", endpoint: "")
    check a.apiKey == "secret"
    check a.model == "gpt-3.5"