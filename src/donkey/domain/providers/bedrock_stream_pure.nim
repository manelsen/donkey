## bedrock_stream_pure.nim — Bedrock ConverseStream, without the SDK.
##
## ConverseStream answers with AWS's binary event-stream framing
## (application/vnd.amazon.eventstream). Each message is:
##
##   total length (4 bytes, big-endian) | headers length (4) |
##   prelude CRC32 (4, over the first 8 bytes) | headers | payload |
##   message CRC32 (4, over everything before it)
##
## A header is: name length (1), name, value type (1), value. Bedrock's
## headers that matter (`:event-type`, `:message-type`, `:exception-type`)
## are strings (type 7: a 2-byte length and the bytes); the other types are
## read past. A message that fails either checksum, or is cut short, is an
## error: corrupt bytes never become text.
##
## The events then become the response a non-streamed Converse call gives
## (bedrock_pure.parseConverseResponse): text deltas, tool calls whose input
## arrives in pieces, reasoning, usage from `metadata`. An `exception`
## message is an error; a stream without `messageStop` is truncated.
##
## `proc` where parseJson is used (ADR-007 allows it).

import std/[json, strutils, tables]
import ../../core/pipeops
import ../message

type
  EventMessage* = object
    headers*: seq[(string, string)]   ## string-valued headers only
    payload*: string

const PreludeBytes = 12

func crcTable(): array[256, uint32] =
  for i in 0 ..< 256:
    var c = uint32(i)
    for _ in 0 ..< 8:
      c = if (c and 1) != 0: 0xEDB88320'u32 xor (c shr 1) else: c shr 1
    result[i] = c

const CrcTableIeee = crcTable()

func crc32*(data: openArray[char]): uint32 =
  ## CRC-32 (IEEE 802.3), as the event-stream framing uses it.
  var c = 0xFFFFFFFF'u32
  for ch in data:
    c = CrcTableIeee[int((c xor uint32(ord(ch))) and 0xFF)] xor (c shr 8)
  c xor 0xFFFFFFFF'u32

func be32(s: string; at: int): uint32 =
  (uint32(ord(s[at])) shl 24) or (uint32(ord(s[at + 1])) shl 16) or
    (uint32(ord(s[at + 2])) shl 8) or uint32(ord(s[at + 3]))

func be16(s: string; at: int): int =
  (ord(s[at]) shl 8) or ord(s[at + 1])

func putBe32(s: var string; value: uint32) =
  s.add char((value shr 24) and 0xFF)
  s.add char((value shr 16) and 0xFF)
  s.add char((value shr 8) and 0xFF)
  s.add char(value and 0xFF)

func header*(m: EventMessage; name: string): string =
  for (key, value) in m.headers:
    if key == name: return value
  ""

func parseHeaders(s: string; first, last: int): Result[seq[(string, string)], string] =
  ## `s[first ..< last]` holds the headers.
  var headers: seq[(string, string)]
  var at = first
  while at < last:
    let nameLen = ord(s[at])
    inc at
    if at + nameLen + 1 > last:
      return err("event-stream header cut short")
    let name = s[at ..< at + nameLen]
    at += nameLen
    let kind = ord(s[at])
    inc at
    var size = 0
    case kind
    of 0, 1: size = 0                  ## bool true / false
    of 2: size = 1                     ## byte
    of 3: size = 2                     ## short
    of 4: size = 4                     ## int
    of 5, 8: size = 8                  ## long, timestamp
    of 9: size = 16                    ## uuid
    of 6, 7:                           ## byte array, string
      if at + 2 > last:
        return err("event-stream header cut short")
      let valueLen = be16(s, at)
      at += 2
      if at + valueLen > last:
        return err("event-stream header cut short")
      if kind == 7:
        headers.add((name, s[at ..< at + valueLen]))
      at += valueLen
      continue
    else:
      return err("event-stream header of unknown type " & $kind)
    if at + size > last:
      return err("event-stream header cut short")
    at += size
  ok(headers)

func decodeEventStream*(body: string): Result[seq[EventMessage], string] =
  ## Every message in `body`, or the first framing error.
  var messages: seq[EventMessage]
  var at = 0
  while at < body.len:
    if body.len - at < PreludeBytes + 4:
      return err("event-stream message cut short")
    let total = int(be32(body, at))
    let headersLen = int(be32(body, at + 4))
    if crc32(body.toOpenArray(at, at + 7)) != be32(body, at + 8):
      return err("event-stream prelude checksum mismatch")
    if total < PreludeBytes + 4 or headersLen > total - PreludeBytes - 4:
      return err("event-stream message has impossible lengths")
    if at + total > body.len:
      return err("event-stream message cut short")
    if crc32(body.toOpenArray(at, at + total - 5)) != be32(body, at + total - 4):
      return err("event-stream message checksum mismatch")
    let headersStart = at + PreludeBytes
    let payloadStart = headersStart + headersLen
    let headers = ? parseHeaders(body, headersStart, payloadStart)
    messages.add EventMessage(headers: headers,
                              payload: body[payloadStart ..< at + total - 4])
    at += total
  ok(messages)

func rawEventMessage*(headerBytes, payload: string): string =
  ## One framed message from already-encoded headers (tests build frames
  ## with this; the framing is the documented one).
  let total = uint32(PreludeBytes + headerBytes.len + payload.len + 4)
  var prelude = ""
  prelude.putBe32(total)
  prelude.putBe32(uint32(headerBytes.len))
  result = prelude
  result.putBe32(crc32(prelude))
  result.add headerBytes
  result.add payload
  result.putBe32(crc32(result))

func encodeEventMessage*(headers: openArray[(string, string)]; payload: string): string =
  ## A framed message with string headers.
  var headerBytes = ""
  for (name, value) in headers:
    headerBytes.add char(name.len)
    headerBytes.add name
    headerBytes.add char(7)
    headerBytes.add char((value.len shr 8) and 0xFF)
    headerBytes.add char(value.len and 0xFF)
    headerBytes.add value
  rawEventMessage(headerBytes, payload)

proc converseStreamResponse*(body: string;
                             onToken: proc(tok: string) {.gcsafe.}
                            ): Result[CompletionResponse, string] =
  ## Reads a whole ConverseStream body; `onToken` (may be nil) gets each text
  ## delta in order.
  let messages = decodeEventStream(body).valueOr:
    ## An error before the stream starts comes back as plain JSON.
    try:
      let j = parseJson(body)
      let detail = j{"message"}.getStr(j{"Message"}.getStr(""))
      if detail.len > 0:
        return err("Bedrock: " & detail)
    except CatchableError:
      discard
    return err("Bedrock stream: " & error)
  var resp = CompletionResponse()
  var tools = initTable[int, ToolCallRequest]()
  var order: seq[int]
  var stopped = false
  for m in messages:
    if m.header(":message-type") == "exception":
      var detail = m.payload
      try: detail = parseJson(m.payload){"message"}.getStr(m.payload)
      except CatchableError: discard
      return err("Bedrock " & m.header(":exception-type") & ": " & detail)
    let j =
      try: parseJson(if m.payload.len > 0: m.payload else: "{}")
      except CatchableError as e: return err("Bedrock stream event: " & e.msg)
    let index = j{"contentBlockIndex"}.getInt(0)
    case m.header(":event-type")
    of "contentBlockStart":
      let use = j{"start"}{"toolUse"}
      if not use.isNil:
        tools[index] = ToolCallRequest(id: use{"toolUseId"}.getStr(""),
                                       name: use{"name"}.getStr(""))
        order.add index
    of "contentBlockDelta":
      let delta = j{"delta"}
      if delta.isNil: continue
      if delta.hasKey("text"):
        let token = delta["text"].getStr("")
        resp.text.add token
        if token.len > 0 and onToken != nil:
          onToken(token)
      elif delta.hasKey("toolUse"):
        if index in tools:
          tools[index].inputJson.add delta["toolUse"]{"input"}.getStr("")
      elif delta.hasKey("reasoningContent"):
        resp.reasoning.add delta["reasoningContent"]{"text"}.getStr("")
    of "messageStop":
      stopped = true
    of "metadata":
      resp.inputTokens = j{"usage"}{"inputTokens"}.getInt(resp.inputTokens)
      resp.outputTokens = j{"usage"}{"outputTokens"}.getInt(resp.outputTokens)
    else:
      discard
  if not stopped:
    return err("Bedrock stream ended without messageStop (truncated)")
  for index in order:
    var call = tools[index]
    if call.name.len == 0: continue
    if call.inputJson.strip.len == 0: call.inputJson = "{}"
    resp.toolCalls.add call
  ok(resp)
