## Each dialect's response carries the cached tokens (E8.3), streamed or not.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/[openai_pure, openai_stream_pure, gemini_pure,
                                bedrock_pure, bedrock_stream_pure]
import donkey/adapters/provider/[openrouter, deepseek, zhipu]

const OpenAiBody = """{"choices":[{"message":{"role":"assistant","content":"oi"}}],
  "usage":{"prompt_tokens":3000,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":2048}}}"""

proc check2048(r: CompletionResponse): bool =
  r.inputTokens == 3000 and r.cacheReadTokens == 2048

proc runTests*() =
  suite "cached tokens in every dialect":

    test "OpenAI and the compat family":
      check parseResponseFrom(parseJson(OpenAiBody)).get.check2048

    test "OpenAI-style stream":
      var acc = initOpenAiStream()
      discard acc.feed("""data: {"choices":[{"delta":{"content":"oi"}}]}""")
      discard acc.feed("""data: {"choices":[],"usage":{"prompt_tokens":3000,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":2048}}}""")
      discard acc.feed("data: [DONE]")
      check acc.finish("x").get.check2048

    test "OpenRouter, with what it wrote":
      let j = parseJson("""{"choices":[{"message":{"role":"assistant","content":"oi"}}],
        "usage":{"prompt_tokens":3000,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":0,"cache_write_tokens":2900}}}""")
      let r = parseOpenRouterResponse(j).get
      check r.inputTokens == 3000 and r.cacheWriteTokens == 2900

    test "DeepSeek":
      let j = parseJson("""{"choices":[{"message":{"role":"assistant","content":"oi"}}],
        "usage":{"prompt_tokens":3000,"completion_tokens":5,"prompt_cache_hit_tokens":2048,"prompt_cache_miss_tokens":952}}""")
      check parseDeepSeekResponse(j).get.check2048

    test "Zhipu":
      check parseZhipuResponse(parseJson(OpenAiBody)).get.check2048

    test "Gemini":
      let j = parseJson("""{"candidates":[{"content":{"role":"model","parts":[{"text":"oi"}]}}],
        "usageMetadata":{"promptTokenCount":3000,"candidatesTokenCount":5,"cachedContentTokenCount":2048}}""")
      check parseGeminiResponse(j).get.check2048

    test "Bedrock Converse":
      let j = parseJson("""{"output":{"message":{"role":"assistant","content":[{"text":"oi"}]}},
        "stopReason":"end_turn","usage":{"inputTokens":952,"outputTokens":5,"cacheReadInputTokens":2048}}""")
      check parseConverseResponse(j).get.check2048

    test "Bedrock ConverseStream":
      let body =
        encodeEventMessage(@[(":event-type", "messageStart"), (":message-type", "event")], """{"role":"assistant"}""") &
        encodeEventMessage(@[(":event-type", "contentBlockDelta"), (":message-type", "event")], """{"contentBlockIndex":0,"delta":{"text":"oi"}}""") &
        encodeEventMessage(@[(":event-type", "messageStop"), (":message-type", "event")], """{"stopReason":"end_turn"}""") &
        encodeEventMessage(@[(":event-type", "metadata"), (":message-type", "event")],
          """{"usage":{"inputTokens":952,"outputTokens":5,"cacheReadInputTokens":2048,"cacheWriteInputTokens":0}}""")
      check converseStreamResponse(body, nil).get.check2048

proc runZeroInputTests*() =
  suite "cached tokens with no uncached input":
    test "Bedrock ConverseStream: metadata with only cached tokens":
      let body =
        encodeEventMessage(@[(":event-type", "messageStart"), (":message-type", "event")], """{"role":"assistant"}""") &
        encodeEventMessage(@[(":event-type", "messageStop"), (":message-type", "event")], """{"stopReason":"end_turn"}""") &
        encodeEventMessage(@[(":event-type", "metadata"), (":message-type", "event")],
          """{"usage":{"inputTokens":0,"outputTokens":5,"cacheReadInputTokens":2048}}""")
      let r = converseStreamResponse(body, nil).get
      check r.cacheReadTokens == 2048 and r.inputTokens == 2048

when isMainModule:
  runTests()
  runZeroInputTests()
