## Anthropic's Messages stream, read into the same response as a
## non-streamed call: text blocks, tool_use blocks with their JSON input
## assembled from `input_json_delta`, usage, and an `error` event or a cut
## stream as an error.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/providers/anthropic_stream_pure

proc feedAll(lines: openArray[string]): (AnthropicStream, seq[string], Result[void, string]) =
  var acc = initAnthropicStream()
  var tokens: seq[string]
  for line in lines:
    let tok = acc.feed(line)
    if tok.isErr:
      return (acc, tokens, Result[void, string].err(tok.error))
    if tok.get.len > 0: tokens.add tok.get
    if acc.done: break
  (acc, tokens, Result[void, string].ok())

const
  start = """data: {"type":"message_start","message":{"usage":{"input_tokens":20,"output_tokens":1}}}"""
  stop  = """data: {"type":"message_stop"}"""

proc runTests*() =
  suite "Anthropic stream":

    test "text arrives token by token, with usage":
      let (acc, tokens, fed) = feedAll([
        "event: message_start", start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Ol"}}""",
        """data: {"type":"ping"}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"á"}}""",
        """data: {"type":"content_block_stop","index":0}""",
        """data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}""",
        stop])
      check fed.isOk
      check tokens == @["Ol", "á"]
      let r = acc.finish("Anthropic").get
      check r.text == "Olá"
      check r.inputTokens == 20 and r.outputTokens == 7

    test "cached tokens from message_start, input as the whole prompt (E8.3)":
      let (acc, _, fed) = feedAll([
        """data: {"type":"message_start","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":3000,"cache_creation_input_tokens":500,"output_tokens":1}}}""",
        """data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}""",
        stop])
      check fed.isOk
      let r = acc.finish("Anthropic").get
      check r.inputTokens == 3520 and r.cacheReadTokens == 3000 and r.cacheWriteTokens == 500

    test "a message_delta with only cached tokens still counts them":
      let (acc, _, fed) = feedAll([
        start,
        """data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":0,"cache_read_input_tokens":4000,"output_tokens":7}}""",
        stop])
      check fed.isOk
      let r = acc.finish("Anthropic").get
      check r.cacheReadTokens == 4000 and r.inputTokens == 4000

    test "a thinking block is assembled with its signature, to be sent back":
      let (acc, tokens, fed) = feedAll([
        start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"vou "}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"buscar"}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-1"}}""",
        """data: {"type":"content_block_stop","index":0}""",
        """data: {"type":"content_block_start","index":1,"content_block":{"type":"redacted_thinking","data":"opaque"}}""",
        """data: {"type":"content_block_stop","index":1}""",
        """data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"oi"}}""",
        """data: {"type":"content_block_stop","index":2}""",
        stop])
      check fed.isOk
      check tokens == @["oi"]                 ## reasoning is never streamed as answer text
      let r = acc.finish("Anthropic").get
      check r.text == "oi" and r.reasoning == "vou buscar"
      check parseJson(r.replayBlocks) == parseJson("""[{"type":"thinking","thinking":"vou buscar","signature":"sig-1"},{"type":"redacted_thinking","data":"opaque"}]""")

    test "a tool_use block comes back with its input assembled":
      let (acc, tokens, _) = feedAll([
        start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Vou ler."}}""",
        """data: {"type":"content_block_stop","index":0}""",
        """data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}""",
        """data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"pa"}}""",
        """data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"th\":\"a.md\"}"}}""",
        """data: {"type":"content_block_stop","index":1}""",
        stop])
      check tokens == @["Vou ler."]
      let r = acc.finish("Anthropic").get
      check r.text == "Vou ler."
      check r.toolCalls.len == 1
      check r.toolCalls[0].id == "toolu_1"
      check r.toolCalls[0].name == "read_file"
      check r.toolCalls[0].inputJson == """{"path":"a.md"}"""

    test "a tool call without arguments has {} as input":
      let (acc, _, _) = feedAll([
        start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"current_time","input":{}}}""",
        """data: {"type":"content_block_stop","index":0}""",
        stop])
      check acc.finish("Anthropic").get.toolCalls[0].inputJson == "{}"

    test "separate text blocks are joined by a newline, as in a full response":
      let (acc, tokens, _) = feedAll([
        start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"um"}}""",
        """data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"dois"}}""",
        stop])
      check acc.finish("Anthropic").get.text == "um\ndois"
      check tokens.join("") == "um\ndois"

    test "thinking is not shown as text":
      let (acc, tokens, _) = feedAll([
        start,
        """data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}""",
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}""",
        """data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}""",
        """data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"ok"}}""",
        stop])
      check tokens == @["ok"]
      check acc.finish("Anthropic").get.text == "ok"

    test "an error event is an error":
      let (_, _, fed) = feedAll([
        start,
        """data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"""])
      check fed.isErr
      check "Overloaded" in fed.error

    test "a stream cut before message_stop is an error, not a short answer":
      let (acc, _, _) = feedAll([
        start,
        """data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"meio"}}"""])
      check acc.finish("Anthropic").isErr

    test "a body that is not SSE is an error":
      let (acc, _, _) = feedAll(["<html>", "Bad gateway"])
      let r = acc.finish("Anthropic")
      check r.isErr
      check "Bad gateway" in r.error

    test "a malformed event is an error":
      var acc = initAnthropicStream()
      check acc.feed("data: {nope").isErr

when isMainModule:
  runTests()
