## The metrics are recorded by the real paths: a tool call through
## `executeToolCall`, a streamed round and a failed turn through `runToolLoop`.

import std/unittest
import chronos
import chronos/asyncsync
import donkey/app/metrics
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/tool_loop_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/memory
import donkey/ports/provider

proc okStream(credential: string): StreamFn {.nimcall, gcsafe.} =
  proc(req: CompletionRequest; onToken: proc(tok: string) {.gcsafe.}
      ): Result[CompletionResponse, string] {.gcsafe.} =
    onToken("oi")
    ok(CompletionResponse(text: "oi", inputTokens: 40, outputTokens: 2))

proc failingStream(credential: string): StreamFn {.nimcall, gcsafe.} =
  proc(req: CompletionRequest; onToken: proc(tok: string) {.gcsafe.}
      ): Result[CompletionResponse, string] {.gcsafe.} =
    err("503 upstream down")

proc turn(factory: StreamFactory): Future[ToolLoopRunResult] {.async.} =
  let outbox = newAsyncQueue[OutboundMessage]()
  let logger = newLogger("test.metrics", lvlError)
  let ctx = NativeCtx(uid: UserId("u"), channel: ckTelegram, outbox: outbox, log: logger)
  var history = newHistory()
  history.addUser("olá")
  result = await runToolLoop(
    outbox, newAsyncQueue[AgentMessage](), newAsyncQueue[AgentMessage](),
    MemoryRuntimePort(), nil, nil, factory, ctx, newSessionState(), history,
    UserId("u"), ckTelegram, "", "m1", "s1", "system", "", @[], "openrouter",
    true, false, false, logger, nil)

proc runTests*() =
  suite "metrics — recorded by the real paths":

    test "a tool call is recorded per tool with its outcome":
      initMetrics()
      let outbox = newAsyncQueue[OutboundMessage]()
      let logger = newLogger("test.metrics", lvlError)
      let ctx = NativeCtx(uid: UserId("u"), channel: ckCli, outbox: outbox, log: logger)
      for (input, _) in [("""{"expression":"2+2"}""", true),
                         ("""{"expression":""}""", false)]:
        discard waitFor executeToolCall(
          outbox, newAsyncQueue[AgentMessage](), newAsyncQueue[AgentMessage](),
          ctx, newSessionState(), newHistory(), UserId("u"), ckCli, "m1", 1, 0,
          ToolCallRequest(id: "c", name: "calc", inputJson: input), "p", false, logger)
      let snap = metricsSnapshot()
      check snap.toolOk.get("calc") == 1
      check snap.toolError.get("calc") == 1
      check snap.toolDuration.get("calc").count == 2

    test "a streamed round records latency and tokens under the factory's provider":
      initMetrics()
      let loop = waitFor turn(StreamFactory(build: okStream, provider: "openrouter"))
      check loop.finalText == "oi"
      check not loop.providerFailed
      let snap = metricsSnapshot()
      check snap.providerLatency.get("openrouter").count == 1
      check snap.tokensIn.get("openrouter") == 40
      check snap.tokensOut.get("openrouter") == 2

    test "a provider error marks the turn failed and counts the error":
      initMetrics()
      let loop = waitFor turn(StreamFactory(build: failingStream, provider: "openrouter"))
      check loop.providerFailed
      check metricsSnapshot().errors.get("openrouter") == 1

    test "channel labels are the channel names":
      check channelLabel(ckTelegram) == "telegram"
      check channelLabel(ckWeCom) == "wecom"
      check channelLabel(ckCli) == "cli"

when isMainModule:
  runTests()
