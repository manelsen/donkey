## MiniMaxAdapter unit tests.
## No HTTP calls are made; tests cover JSON construction and response parsing.

import std/[json, unittest, strutils]
import results
import donkey/adapters/provider/minimax
import donkey/domain/message
import donkey/ports/provider

suite "MiniMaxAdapter construction":

  test "apiKey and model are stored":
    let a = newMiniMaxAdapter("MY_KEY", "abab6.5s-chat")
    check a.apiKey == "MY_KEY"
    check a.model  == "abab6.5s-chat"

suite "MiniMaxAdapter caps":

  test "declares minimax name":
    let a = newMiniMaxAdapter("k", model = "custom-m")
    check a.caps.name == "minimax/custom-m"

  test "streaming is false":
    check newMiniMaxAdapter("k").caps.streaming == false

  test "toolCalling is false":
    check newMiniMaxAdapter("k").caps.toolCalling == false

suite "MiniMaxAdapter buildBody":

  test "model is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k", model = "m1").buildBody(req)
    check body["model"].getStr() == "m1"

  test "system prompt maps to bot_setting":
    let req  = CompletionRequest(system: "You are a helpful assistant", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["bot_setting"][0]["content"].getStr() == "You are a helpful assistant"

  test "user message maps to sender_type USER":
    var h = newHistory()
    h.addUser("hello")
    let req  = CompletionRequest(system: "", messages: h)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["sender_type"].getStr() == "USER"
    check body["messages"][0]["text"].getStr() == "hello"

  test "assistant message maps to sender_type BOT":
    var h = newHistory()
    h.addAssistant("hi there")
    let req  = CompletionRequest(system: "", messages: h)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["sender_type"].getStr() == "BOT"
    check body["messages"][0]["text"].getStr() == "hi there"

  test "tokens_to_generate present when maxTokens set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["tokens_to_generate"].getInt() == 256

suite "MiniMaxAdapter parseResponse":

  test "extracts text from choices[0].messages[0].text":
    let j = %* {
      "choices": [{"messages": [{"sender_type": "BOT", "text": "Hello"}]}],
      "usage": {"prompt_tokens": 5, "completion_tokens": 3}
    }
    let resp = parseMiniMaxResponse(j).get()
    check resp.text         == "Hello"
    check resp.inputTokens  == 5
    check resp.outputTokens == 3

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"messages": [{"sender_type": "BOT", "text": "Hi"}]}]}
    let resp = parseMiniMaxResponse(j).get()
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "extracts reasoning_content":
    let j = %* {
      "choices": [{"messages": [{
        "sender_type": "BOT",
        "text": "Final answer",
        "reasoning_content": "Thinking process..."
      }]}]
    }
    let resp = parseMiniMaxResponse(j).get()
    check resp.text == "Final answer"
    check resp.reasoning == "Thinking process..."

  test "extracts reasoning_details":
    let j = %* {
      "choices": [{"messages": [{
        "sender_type": "BOT",
        "text": "Final answer",
        "reasoning_details": [{"text": "Step 1. "}, {"text": "Step 2."}]
      }]}]
    }
    let resp = parseMiniMaxResponse(j).get()
    check resp.text == "Final answer"
    check resp.reasoning == "Step 1. Step 2."

  test "handles OpenAI-compatible format (message.content)":
    let j = %* {
      "choices": [{"message": {"role": "assistant", "content": "Hello from v2"}}],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5}
    }
    let resp = parseMiniMaxResponse(j).get()
    check resp.text == "Hello from v2"
    check resp.inputTokens == 10

  test "returns error for base_resp error":
    let j = %* {
      "base_resp": {"status_code": 1000, "status_msg": "Invalid API key"}
    }
    let r = parseMiniMaxResponse(j)
    check r.isErr
    check "Invalid API key" in r.error

  test "returns error for top-level error field":
    let j = %* {
      "error": {"message": "Rate limit exceeded", "code": "rate_limit"}
    }
    let r = parseMiniMaxResponse(j)
    check r.isErr
    check "Rate limit exceeded" in r.error

  test "returns error for empty choices":
    let j = %* {"choices": []}
    let r = parseMiniMaxResponse(j)
    check r.isErr

  test "returns error for completely empty response":
    let j = %* {}
    let r = parseMiniMaxResponse(j)
    check r.isErr
