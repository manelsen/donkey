## Streaming tool-call contract tests.

import std/[atomics, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/tool_loop_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/memory
import donkey/ports/provider

suite "streamToOutbox — tool calls":

  test "returns tool calls and does not emit a fake final text":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      onToken("partial")
      ok(CompletionResponse(
        text: "partial",
        toolCalls: @[ToolCallRequest(id: "call_1", name: "read_file", inputJson: "{}")],
      ))

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isOk
    check res.value.toolCalls.len == 1
    check res.value.toolCalls[0].name == "read_file"
    check outbox.len == 0

  test "provider error is returned instead of a fake final message":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      err("HTTP 500")

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isErr
    check "HTTP 500" in res.error
    check outbox.len == 0

  test "text-only stream still emits the final message":
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      onToken("hello")
      ok(CompletionResponse(text: "hello"))

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isOk
    check res.value.toolCalls.len == 0
    check outbox.len == 1
    let final = waitFor outbox.get()
    check final.text == "hello"
    check final.isPartial == false

  test "a negative provider usage never reaches the terminal as negative":
    ## The streamed terminal bypasses `finalizeNormalTurn`, so the raw
    ## provider values used to reach the 200 body unclamped.
    let fn: StreamFn = proc(req: CompletionRequest;
                            onToken: proc(tok: string) {.gcsafe.}
                           ): Result[CompletionResponse, string] {.gcsafe.} =
      onToken("hi")
      ok(CompletionResponse(text: "hi", inputTokens: -5, outputTokens: -7))

    let outbox = newAsyncQueue[OutboundMessage]()
    let res = waitFor streamToOutbox(
      fn, CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
    check res.isOk
    check outbox.len == 1
    let final = waitFor outbox.get()
    check final.inputTokens == 0
    check final.outputTokens == 0

# ── Turn-scoped retry in the streaming branch ────────────────────────────────
#
# OpenRouter streams the first round. A vision-less model refuses the inline
# image there too, so the retry cannot live only in the non-streaming path.

const DataPng = "data:image/png;base64,QUJD"

var
  gStreamCalls:     Atomic[int]
  gStreamNoteCalls: Atomic[int]

proc imageRejectingStream(req: CompletionRequest;
                          onToken: proc(tok: string) {.gcsafe.}):
                          Result[CompletionResponse, string]
                          {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    discard gStreamCalls.fetchAdd(1)
    for msg in req.messages:
      if msg.text.contains(InlineImageRemovedNote):
        discard gStreamNoteCalls.fetchAdd(1)
        break
    for msg in req.messages:
      if msg.imageUrl.startsWith("data:"):
        return err("400 invalid image_url: unsupported image content")
  {.cast(raises: []).}:
    onToken("texto ok")
  ok(CompletionResponse(text: "texto ok"))

proc runStreamingImageTurn():
    Future[ToolLoopRunResult] {.async.} =
  let outbox = newAsyncQueue[OutboundMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let toolOut = newAsyncQueue[AgentMessage]()
  let logger = newLogger("test.stream.retry", lvlError)
  var ctx = NativeCtx(
    uid: UserId("u-stream"),
    channel: ckTelegram,
    outbox: outbox,
    log: logger,
  )
  var history = newHistory()
  history.addUserWithImage("veja a foto", DataPng)
  result = await runToolLoop(
    outbox, toolInbox, toolOut, MemoryRuntimePort(), nil, nil,
    imageRejectingStream, ctx, newSessionState(), history, UserId("u-stream"),
    ckTelegram, "", "msg-stream", "stream-id", "system", "", @[], "openrouter",
    true, false, false, logger, nil)

suite "streamToOutbox — turn-scoped image retry":

  test "the streaming path retries once without the data URL":
    gStreamCalls.store(0)
    gStreamNoteCalls.store(0)

    let loop = waitFor runStreamingImageTurn()

    check loop.done
    check loop.imageRetryUsed
    check loop.finalText == "texto ok"
    check gStreamCalls.load() == 2
    check gStreamNoteCalls.load() == 1
    for msg in loop.history:
      check not msg.imageUrl.startsWith("data:")
