## Streaming tool-call contract tests.

import std/[atomics, options, os, strutils, times, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/session_manager
import donkey/app/tool_loop_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/memory
import donkey/ports/provider

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

proc imageRejectingFactory(credential: string): StreamFn {.nimcall, gcsafe.} =
  imageRejectingStream

var
  gFactoryThread: Atomic[int]
  gSlowFinished:  Atomic[bool]

proc threadRecordingFactory(credential: string): StreamFn {.nimcall, gcsafe.} =
  ## Records where the provider closure is built.
  gFactoryThread.store(getThreadId())
  proc(req: CompletionRequest; onToken: proc(tok: string) {.gcsafe.}
      ): Result[CompletionResponse, string] {.gcsafe.} =
    onToken("oi")
    ok(CompletionResponse(text: "oi"))

proc slowFactory(credential: string): StreamFn {.nimcall, gcsafe.} =
  proc(req: CompletionRequest; onToken: proc(tok: string) {.gcsafe.}
      ): Result[CompletionResponse, string] {.gcsafe.} =
    onToken("comecei")
    os.sleep(1500)
    gSlowFinished.store(true)
    ok(CompletionResponse(text: "tarde demais"))

proc echoSpecRuntime(spec: ProviderSpec): ProviderBundle {.nimcall, gcsafe.} =
  ## Streams back which route it was built for, on the stream thread.
  let label = spec.providerName & "/" & spec.modelName
  ProviderBundle(streamFn: proc(req: CompletionRequest;
                                onToken: proc(tok: string) {.gcsafe.}
                               ): Result[CompletionResponse, string] {.gcsafe.} =
    onToken(label)
    ok(CompletionResponse(text: label)))

proc noStreamRuntime(spec: ProviderSpec): ProviderBundle {.nimcall, gcsafe.} =
  ProviderBundle()

proc failingRuntime(spec: ProviderSpec): ProviderBundle {.nimcall, gcsafe.} =
  ProviderBundle(streamFn: proc(req: CompletionRequest;
                                onToken: proc(tok: string) {.gcsafe.}
                               ): Result[CompletionResponse, string] {.gcsafe.} =
    err("HTTP 529 overloaded"))

proc routedTurn(route: ProviderSpec; runtime: ProviderRuntimeBuilder):
    Future[(ToolLoopRunResult, seq[OutboundMessage])] {.async.} =
  ## One turn with a tool available, a label that is not OpenRouter, and a
  ## stream route: the stream follows the route, not the label.
  let outbox = newAsyncQueue[OutboundMessage]()
  let logger = newLogger("test.stream.route", lvlError)
  var ctx = NativeCtx(uid: UserId("u-route"), channel: ckTelegram,
                      outbox: outbox, log: logger)
  var history = newHistory()
  history.addUser("oi")
  let routed: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string]
                               {.gcsafe, raises: [].} =
    ok(CompletionResponse(text: "from routing"))
  let streamRoute: StreamRouteFn = proc(req: CompletionRequest): Option[ProviderSpec]
                                       {.gcsafe, raises: [].} =
    some(route)
  let loop = await runToolLoop(
    outbox, newAsyncQueue[AgentMessage](), newAsyncQueue[AgentMessage](),
    MemoryRuntimePort(), routed, nil, StreamFactory(), ctx, newSessionState(),
    history, UserId("u-route"), ckTelegram, "", "msg-route", "sid-route",
    "system", "", @[ToolDescription(name: "calc", description: "d",
                                    schemaJson: """{"type":"object"}""")],
    "zai", false, false, false, logger, nil,
    streamRoute = streamRoute, providerRuntime = runtime)
  var sent: seq[OutboundMessage]
  while outbox.len > 0:
    sent.add(await outbox.get())
  return (loop, sent)

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
    StreamFactory(build: imageRejectingFactory), ctx, newSessionState(), history, UserId("u-stream"),
    ckTelegram, "", "msg-stream", "stream-id", "system", "", @[], "openrouter",
    true, false, false, logger, nil)


proc runTests*() =
  suite "streaming follows the turn's route":

    test "a route whose stream carries tool calls streams, whatever the label":
      let (loop, sent) = waitFor routedTurn(
        ProviderSpec(providerName: "anthropic", modelName: "m"), echoSpecRuntime)
      check loop.wasStreamed
      check sent.len > 0
      check sent[^1].text == "anthropic/m"

    test "a route whose stream drops tool calls is not streamed with tools":
      let (loop, _) = waitFor routedTurn(
        ProviderSpec(providerName: "gemini", modelName: "g"), echoSpecRuntime)
      check not loop.wasStreamed
      check loop.finalText == "from routing"

    test "a stream that fails before showing anything falls back to routing":
      ## Routing can try the next provider; the turn must not end in an error.
      let (loop, sent) = waitFor routedTurn(
        ProviderSpec(providerName: "anthropic", modelName: "m"), failingRuntime)
      check not loop.providerFailed
      check loop.finalText == "from routing"
      for msg in sent:
        check msg.replyKind != rkTurnError

  suite "streamToOutbox — tool calls":

    test "returns tool calls and does not emit a fake final text":
      let build: StreamBuilder = proc(credential: string): StreamFn {.nimcall, gcsafe.} =
        proc(req: CompletionRequest;
             onToken: proc(tok: string) {.gcsafe.}
            ): Result[CompletionResponse, string] {.gcsafe.} =
          onToken("partial")
          ok(CompletionResponse(
            text: "partial",
            toolCalls: @[ToolCallRequest(id: "call_1", name: "read_file", inputJson: "{}")],
          ))

      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: build), CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
      check res.isOk
      check res.value.toolCalls.len == 1
      check res.value.toolCalls[0].name == "read_file"
      check outbox.len == 0

    test "a route's stream is built from its spec on the stream thread":
      let factory = routeStreamFactory(echoSpecRuntime,
        ProviderSpec(providerName: "anthropic", modelName: "claude-x", apiKey: "k"))
      check factory.available
      check factory.provider == "anthropic"
      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(factory, CompletionRequest(), outbox,
                                       UserId("u1"), ckTelegram, "", "sid")
      check res.get.text == "anthropic/claude-x"

    test "a route whose provider has no stream fails instead of hanging":
      let factory = routeStreamFactory(noStreamRuntime,
        ProviderSpec(providerName: "gemini", modelName: "g"))
      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(factory, CompletionRequest(), outbox,
                                       UserId("u1"), ckTelegram, "", "sid")
      check res.isErr

    test "provider error is returned instead of a fake final message":
      let build: StreamBuilder = proc(credential: string): StreamFn {.nimcall, gcsafe.} =
        proc(req: CompletionRequest;
             onToken: proc(tok: string) {.gcsafe.}
            ): Result[CompletionResponse, string] {.gcsafe.} =
          err("HTTP 500")

      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: build), CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
      check res.isErr
      check "HTTP 500" in res.error
      check outbox.len == 0

    test "text-only stream still emits the final message":
      let build: StreamBuilder = proc(credential: string): StreamFn {.nimcall, gcsafe.} =
        proc(req: CompletionRequest;
             onToken: proc(tok: string) {.gcsafe.}
            ): Result[CompletionResponse, string] {.gcsafe.} =
          onToken("hello")
          ok(CompletionResponse(text: "hello"))

      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: build), CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
      check res.isOk
      check res.value.toolCalls.len == 0
      check outbox.len == 1
      let final = waitFor outbox.get()
      check final.text == "hello"
      check final.isPartial == false

    test "a negative provider usage never reaches the terminal as negative":
      ## The streamed terminal bypasses `finalizeNormalTurn`, so the raw
      ## provider values used to reach the 200 body unclamped.
      let build: StreamBuilder = proc(credential: string): StreamFn {.nimcall, gcsafe.} =
        proc(req: CompletionRequest;
             onToken: proc(tok: string) {.gcsafe.}
            ): Result[CompletionResponse, string] {.gcsafe.} =
          onToken("hi")
          ok(CompletionResponse(text: "hi", inputTokens: -5, outputTokens: -7))

      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: build), CompletionRequest(), outbox, UserId("u1"), ckTelegram, "", "sid")
      check res.isOk
      check outbox.len == 1
      let final = waitFor outbox.get()
      check final.inputTokens == 0
      check final.outputTokens == 0

    test "the credential travels to the builder as plain data":
      ## The stream thread cannot read the loop's environment snapshot, so
      ## the API key is read on the loop and carried in the factory.
      let build: StreamBuilder = proc(credential: string): StreamFn {.nimcall, gcsafe.} =
        let key = credential
        result = proc(req: CompletionRequest;
                      onToken: proc(tok: string) {.gcsafe.}
                     ): Result[CompletionResponse, string] {.gcsafe.} =
          err("built with " & key)
      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: build, credential: "k-123"), CompletionRequest(),
        outbox, UserId("u1"), ckTelegram, "", "sid")
      check res.isErr
      check res.error == "built with k-123"

    test "the provider closure is built and dropped on the stream thread":
      ## ORC counts references without atomics: a closure built on the
      ## event loop and run on another thread is shared between two threads.
      gFactoryThread.store(0)
      let outbox = newAsyncQueue[OutboundMessage]()
      let res = waitFor streamToOutbox(
        StreamFactory(build: threadRecordingFactory), CompletionRequest(), outbox, UserId("u1"),
        ckTelegram, "", "sid")
      check res.isOk
      check gFactoryThread.load() != 0
      check gFactoryThread.load() != getThreadId()

    test "a stop returns at once instead of waiting for the provider":
      gSlowFinished.store(false)
      let outbox = newAsyncQueue[OutboundMessage]()
      let startedAt = epochTime()
      ## A generation other than the current one reads as "stop requested".
      let res = waitFor streamToOutbox(
        StreamFactory(build: slowFactory), CompletionRequest(), outbox, UserId("u1"), ckTelegram,
        "", "sid", stopGeneration = currentSessionStopGeneration() + 1)
      check res.isOk
      check epochTime() - startedAt < 1.0
      check not gSlowFinished.load()
      check liveStreams() == 1  ## still running, and still counted
      ## The thread is joined and freed in the background once the provider
      ## returns; only then does it stop counting.
      waitFor sleepAsync(chronos.milliseconds(2000))
      check gSlowFinished.load()
      check liveStreams() == 0

    test "abandoned streams count against a cap until they are reaped":
      ## A hung provider must not let stopped turns pile up threads.
      let outbox = newAsyncQueue[OutboundMessage]()
      let stopped = currentSessionStopGeneration() + 1
      for _ in 0 ..< MaxLiveStreams:
        check (waitFor streamToOutbox(StreamFactory(build: slowFactory), CompletionRequest(), outbox,
                 UserId("u1"), ckTelegram, "", "sid", stopGeneration = stopped)).isOk
      check liveStreams() == MaxLiveStreams
      check not streamSlotAvailable()
      let refused = waitFor streamToOutbox(
        StreamFactory(build: threadRecordingFactory), CompletionRequest(), outbox, UserId("u1"),
        ckTelegram, "", "sid")
      check refused.isErr
      check "saturated" in refused.error
      waitFor sleepAsync(chronos.milliseconds(2000))
      check liveStreams() == 0
      check streamSlotAvailable()

    test "a saturated turn with no completion function ends with an error":
      ## At the cap the loop does not stream; with no completion function to
      ## fall back on it must fail cleanly, not call a nil proc.
      let outbox = newAsyncQueue[OutboundMessage]()
      let stopped = currentSessionStopGeneration() + 1
      for _ in 0 ..< MaxLiveStreams:
        discard waitFor streamToOutbox(StreamFactory(build: slowFactory), CompletionRequest(), outbox,
          UserId("u1"), ckTelegram, "", "sid", stopGeneration = stopped)
      gStreamCalls.store(0)
      let loop = waitFor runStreamingImageTurn()
      check loop.done
      check gStreamCalls.load() == 0
      waitFor sleepAsync(chronos.milliseconds(2000))
      check liveStreams() == 0

  # ── Turn-scoped retry in the streaming branch ────────────────────────────────
  #
  # OpenRouter streams the first round. A vision-less model refuses the inline
  # image there too, so the retry cannot live only in the non-streaming path.

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

when isMainModule:
  runTests()
