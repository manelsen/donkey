## Bedrock ConverseStream: AWS's binary event-stream framing (a prelude with
## its own CRC32, typed headers, the payload, a CRC32 of the whole frame),
## then the Converse events read into the response a non-streamed call gives.
## A frame that fails a checksum, or a cut stream, is an error, never text.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/providers/bedrock_stream_pure

proc event(kind: string; payload: JsonNode): string =
  encodeEventMessage(@[(":event-type", kind), (":message-type", "event"),
                       (":content-type", "application/json")], $payload)

proc exception(kind, message: string): string =
  encodeEventMessage(@[(":exception-type", kind), (":message-type", "exception"),
                       (":content-type", "application/json")],
                     $ %* {"message": message})

proc stream(events: varargs[string]): string =
  for e in events: result.add e

proc runTests*() =
  suite "AWS event-stream framing":

    test "CRC32 matches the standard check value":
      check crc32("123456789") == 0xCBF43926'u32
      check crc32("") == 0'u32

    test "a frame round-trips with its headers and payload":
      let frame = encodeEventMessage(@[(":event-type", "messageStart")], "{\"role\":\"assistant\"}")
      ## prelude: total length, headers length, prelude CRC
      check frame.len == 12 + (1 + 11 + 1 + 2 + 12) + 20 + 4
      let messages = decodeEventStream(frame).get
      check messages.len == 1
      check messages[0].header(":event-type") == "messageStart"
      check messages[0].payload == "{\"role\":\"assistant\"}"

    test "several frames in one body":
      let body = stream(event("messageStart", %* {"role": "assistant"}),
                        event("messageStop", %* {"stopReason": "end_turn"}))
      check decodeEventStream(body).get.len == 2

    test "a damaged payload fails the message checksum":
      var frame = encodeEventMessage(@[(":event-type", "x")], "hello")
      frame[frame.len - 6] = 'j'
      let r = decodeEventStream(frame)
      check r.isErr
      check "checksum" in r.error

    test "a damaged prelude fails the prelude checksum":
      var frame = encodeEventMessage(@[(":event-type", "x")], "hello")
      frame[5] = char(ord(frame[5]) xor 1)
      check decodeEventStream(frame).isErr

    test "a frame cut short is an error":
      let frame = encodeEventMessage(@[(":event-type", "x")], "hello")
      check decodeEventStream(frame[0 ..< frame.len - 3]).isErr
      check decodeEventStream(frame[0 ..< 7]).isErr

    test "headers of other types are skipped, string ones kept":
      ## type 0 (bool true) has no value; type 4 (int32) has four bytes.
      var headers = ""
      headers.add char(5); headers.add "flag!"; headers.add char(0)
      headers.add char(3); headers.add "num"; headers.add char(4)
      headers.add "\x00\x00\x00\x2A"
      headers.add char(11); headers.add ":event-type"; headers.add char(7)
      headers.add "\x00\x04ping"
      let frame = rawEventMessage(headers, "{}")
      let m = decodeEventStream(frame).get
      check m[0].header(":event-type") == "ping"

  suite "ConverseStream events":

    test "text, a tool call and usage come back as one response":
      let body = stream(
        event("messageStart", %* {"role": "assistant"}),
        event("contentBlockDelta", %* {"contentBlockIndex": 0, "delta": {"text": "Ol"}}),
        event("contentBlockDelta", %* {"contentBlockIndex": 0, "delta": {"text": "á"}}),
        event("contentBlockStop", %* {"contentBlockIndex": 0}),
        event("contentBlockStart", %* {"contentBlockIndex": 1,
          "start": {"toolUse": {"toolUseId": "tooluse_1", "name": "calc"}}}),
        event("contentBlockDelta", %* {"contentBlockIndex": 1,
          "delta": {"toolUse": {"input": "{\"x\":"}}}),
        event("contentBlockDelta", %* {"contentBlockIndex": 1,
          "delta": {"toolUse": {"input": "1}"}}}),
        event("contentBlockStop", %* {"contentBlockIndex": 1}),
        event("messageStop", %* {"stopReason": "tool_use"}),
        event("metadata", %* {"usage": {"inputTokens": 30, "outputTokens": 9}}))
      var tokens: seq[string]
      let r = converseStreamResponse(body, proc(tok: string) {.gcsafe.} =
        {.cast(gcsafe).}: tokens.add tok).get
      check tokens == @["Ol", "á"]
      check r.text == "Olá"
      check r.toolCalls.len == 1
      check r.toolCalls[0].id == "tooluse_1"
      check r.toolCalls[0].name == "calc"
      check r.toolCalls[0].inputJson == """{"x":1}"""
      check r.inputTokens == 30 and r.outputTokens == 9

    test "reasoning is kept apart from the text":
      let body = stream(
        event("messageStart", %* {"role": "assistant"}),
        event("contentBlockDelta", %* {"contentBlockIndex": 0,
          "delta": {"reasoningContent": {"text": "pensando"}}}),
        event("contentBlockDelta", %* {"contentBlockIndex": 1, "delta": {"text": "ok"}}),
        event("messageStop", %* {"stopReason": "end_turn"}))
      let r = converseStreamResponse(body, nil).get
      check r.text == "ok"
      check r.reasoning == "pensando"

    test "an exception frame is an error with its type":
      let body = stream(event("messageStart", %* {"role": "assistant"}),
                        exception("throttlingException", "Too many requests"))
      let r = converseStreamResponse(body, nil)
      check r.isErr
      check "throttlingException" in r.error
      check "Too many requests" in r.error

    test "a stream without messageStop is truncated, not a short answer":
      let body = stream(event("messageStart", %* {"role": "assistant"}),
                        event("contentBlockDelta", %* {"contentBlockIndex": 0,
                          "delta": {"text": "meio"}}))
      check converseStreamResponse(body, nil).isErr

    test "tool input for a block that never started is an error, not dropped":
      let body = stream(
        event("messageStart", %* {"role": "assistant"}),
        event("contentBlockDelta", %* {"contentBlockIndex": 3,
          "delta": {"toolUse": {"input": "{}"}}}),
        event("messageStop", %* {"stopReason": "tool_use"}))
      let r = converseStreamResponse(body, nil)
      check r.isErr
      check "block 3" in r.error

    test "a body that is not an event stream is an error":
      check converseStreamResponse("""{"message":"The security token is invalid"}""", nil).isErr

when isMainModule:
  runTests()
