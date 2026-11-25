## The OpenAI SSE dialect, read once for every provider that speaks it
## (OpenRouter, OpenAI, DeepSeek, the compat family): text, reasoning, usage
## and tool calls assembled from their deltas, with a cut or non-SSE stream
## reported as an error, never as a finished answer.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/providers/openai_stream_pure

proc feedAll(lines: openArray[string]): (OpenAiStream, seq[string]) =
  var acc = initOpenAiStream()
  var tokens: seq[string]
  for line in lines:
    let tok = acc.feed(line).get
    if tok.len > 0: tokens.add tok
    if acc.done: break
  (acc, tokens)

proc runTests*() =
  suite "OpenAI SSE stream":

    test "text arrives token by token, with usage and reasoning":
      let (acc, tokens) = feedAll([
        """data: {"choices":[{"delta":{"reasoning":"pensando"}}]}""",
        """data: {"choices":[{"delta":{"content":"Ol"}}]}""",
        "",
        """data: {"choices":[{"delta":{"content":"á"}}]}""",
        """data: {"choices":[{"delta":{}}],"usage":{"prompt_tokens":12,"completion_tokens":5}}""",
        "data: [DONE]"])
      check tokens == @["Ol", "á"]
      let r = acc.finish("test").get
      check r.text == "Olá"
      check r.reasoning == "pensando"
      check r.inputTokens == 12 and r.outputTokens == 5
      check r.toolCalls.len == 0

    test "reasoning_content counts as reasoning (DeepSeek, Qwen)":
      let (acc, _) = feedAll([
        """data: {"choices":[{"delta":{"reasoning_content":"r1"}}]}""",
        "data: [DONE]"])
      check acc.finish("test").get.reasoning == "r1"

    test "a tool call is assembled from its deltas":
      let (acc, tokens) = feedAll([
        """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"pa"}}]}}]}""",
        """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"a.md\"}"}}]}}]}""",
        "data: [DONE]"])
      check tokens.len == 0
      let calls = acc.finish("test").get.toolCalls
      check calls.len == 1
      check calls[0].id == "call_1"
      check calls[0].name == "read_file"
      check calls[0].inputJson == """{"path":"a.md"}"""

    test "parallel tool calls keep their order; empty arguments become {}":
      let (acc, _) = feedAll([
        """data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"calc","arguments":""}}]}}]}""",
        """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"current_time","arguments":""}}]}}]}""",
        """data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\"x\":1}"}}]}}]}""",
        "data: [DONE]"])
      let calls = acc.finish("test").get.toolCalls
      check calls.len == 2
      check calls[0].id == "b" and calls[0].inputJson == """{"x":1}"""
      check calls[1].id == "a" and calls[1].inputJson == "{}"

    test "deltas without an index: a new id starts a call, none continues the last":
      ## Some compat backends omit `index`; defaulting it to 0 would merge
      ## parallel calls into one.
      let (acc, _) = feedAll([
        """data: {"choices":[{"delta":{"tool_calls":[{"id":"a","function":{"name":"calc","arguments":"{\"x\":"}}]}}]}""",
        """data: {"choices":[{"delta":{"tool_calls":[{"function":{"arguments":"1}"}}]}}]}""",
        """data: {"choices":[{"delta":{"tool_calls":[{"id":"b","function":{"name":"current_time","arguments":"{}"}}]}}]}""",
        "data: [DONE]"])
      let calls = acc.finish("test").get.toolCalls
      check calls.len == 2
      check calls[0].id == "a" and calls[0].inputJson == """{"x":1}"""
      check calls[1].id == "b" and calls[1].name == "current_time"

    test "a tool call that never got a name is dropped":
      let (acc, _) = feedAll([
        """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"x","function":{"arguments":"{}"}}]}}]}""",
        "data: [DONE]"])
      check acc.finish("test").get.toolCalls.len == 0

    test "a Gemini thought signature rides along with its call":
      let (acc, _) = feedAll([
        """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"g","function":{"name":"calc","arguments":"{}"},"extra_content":{"google":{"thought_signature":"sig=="}}}]}}]}""",
        "data: [DONE]"])
      check acc.finish("test").get.toolCalls[0].signature == "sig=="

    test "comments and heartbeats are skipped":
      let (acc, tokens) = feedAll([
        ": OPENROUTER PROCESSING",
        "data:",
        """data: {"choices":[{"delta":{"content":"x"}}]}""",
        "data: [DONE]"])
      check tokens == @["x"]
      check acc.finish("test").isOk

    test "a malformed data line is an error":
      var acc = initOpenAiStream()
      check acc.feed("data: {not json").isErr

    test "a stream cut before [DONE] is an error, not a short answer":
      let (acc, _) = feedAll(["""data: {"choices":[{"delta":{"content":"meio"}}]}"""])
      let r = acc.finish("test")
      check r.isErr
      check "truncated" in r.error

    test "a body that is not SSE is an error with a short diagnostic":
      let (acc, _) = feedAll(["<html>", "Bad gateway", "</html>"])
      let r = acc.finish("test")
      check r.isErr
      check "Bad gateway" in r.error

    test "only [DONE] is a legitimate empty answer":
      let (acc, _) = feedAll(["data: [DONE]"])
      check acc.finish("test").get.text == ""

when isMainModule:
  runTests()
