## US-002 — non-streaming `POST /v1/chat/completions` with the agent turn loop.
##
## The dispatch, authorization and clock are fakes: no provider, no network,
## no real sleep. Content is only the terminal event; partials and tool
## notices never become content.

import std/[json, strutils, unittest]
import chronos
import results
import donkey/core/types
import donkey/core/tooling/tool_loop
import donkey/domain/message
import donkey/domain/gateway/identity_pure
import donkey/domain/gateway/chat_response
import donkey/app/chat_bridge
import donkey/app/agent_chat_runtime

# ── fake clock ────────────────────────────────────────────────────────────────

var fakeNowMs: int64 = 1_000

proc fakeNowFn(): int64 {.gcsafe, raises: [].} =
  fakeNowMs

proc fakeNapFn(ms: int) {.gcsafe, raises: [].} =
  fakeNowMs += int64(ms)

proc fakeEpochSec(): int64 {.gcsafe, raises: [].} =
  1_700_000_000

proc completed[T](value: T): Future[T] {.raises: [].} =
  ## An already-finished future: the fakes answer at once, with no real wait.
  result = newFuture[T]("fake")
  result.complete(value)

proc fakeAsyncNap(ms: int): Future[void] {.gcsafe, raises: [].} =
  ## Advances the fake clock instead of sleeping.
  fakeNowMs += int64(ms)
  result = newFuture[void]("fake nap")
  result.complete()

# ── fake dispatch / authorize ─────────────────────────────────────────────────

type DispatchMode = enum
  dmNothing
  dmFinal
  dmPartialThenFinal
  dmToolThenFinal
  dmTwoPartialsThenFinal
  dmPartialThenError
  dmHugeFinal
  dmCumulativePartials
  dmTokenEchoFinal        ## the terminal carries the inbound turn token
  dmWrongTokenFinal       ## a terminal from another generation
  dmManyPartials          ## more partial deltas than a stream may send, no terminal
  dmApprovalThenFinal     ## an approval request (channel text with buttons), then the answer
  dmEditorRequestThenFinal ## a request for the editor (E10.5), then the answer

var fakeBridge {.threadvar.}: ChatBridge
var dispatched {.threadvar.}: seq[InboundMessage]
var dispatchMode = dmNothing
var finalText {.threadvar.}: string
var authVerdict = avAllowed

proc deliverToBridge(userId: UserId; text: string; kind = rkFinalAnswer;
                     partial = false; tool = ToolCallNotice();
                     inputTokens = 0; outputTokens = 0;
                     token = 0'u64) {.gcsafe.} =
  discard fakeBridge.deliver(OutboundMessage(
    userId:  userId,
    text:    text,
    replyKind: kind,
    isPartial: partial,
    toolCall: tool,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    bridgeToken: token,
  ))

proc fakeDispatch(msg: InboundMessage) {.gcsafe.} =
  dispatched.add(msg)
  case dispatchMode
  of dmNothing:
    discard
  of dmManyPartials:
    for i in 0 ..< MaxSseChunksPerTurn + 10:
      deliverToBridge(msg.userId, "[" & $i & "]", rkFinalAnswer, partial = true)
  of dmFinal:
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                               inputTokens = 11, outputTokens = 7)
  of dmPartialThenFinal:
    deliverToBridge(msg.userId, "parcial", rkFinalAnswer,
                               partial = true, inputTokens = 3, outputTokens = 2)
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                               inputTokens = 11, outputTokens = 7)
  of dmToolThenFinal:
    deliverToBridge(msg.userId, "🔧 fs_read", rkToolNotice,
                               partial = true,
                               tool = ToolCallNotice(phase: "start",
                                 name: "fs_read", id: "c1"))
    deliverToBridge(msg.userId, "✅ 1 tool call(s)", rkToolNotice,
                               tool = ToolCallNotice(phase: "done"))
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                               inputTokens = 11, outputTokens = 7)
  of dmEditorRequestThenFinal:
    discard fakeBridge.deliver(OutboundMessage(userId: msg.userId, replyKind: rkChannel,
      bridgeToken: msg.bridgeToken,
      editorRequest: """{"id":"ef-1","method":"fs/read_text_file","params":{"path":"a.nim"}}"""))
    deliverToBridge(msg.userId, finalText, rkFinalAnswer, token = msg.bridgeToken)
  of dmApprovalThenFinal:
    discard fakeBridge.deliver(OutboundMessage(userId: msg.userId, replyKind: rkChannel,
      text: "Aprovação necessária: bash", bridgeToken: msg.bridgeToken,
      keyboard: @[@[("✅ Aprovar", "approval:abc:allow"), ("❌ Negar", "approval:abc:deny")]]))
    discard fakeBridge.deliver(OutboundMessage(userId: msg.userId, replyKind: rkChannel,
      text: "chatter", bridgeToken: msg.bridgeToken))
    deliverToBridge(msg.userId, finalText, rkFinalAnswer, token = msg.bridgeToken)
  of dmTwoPartialsThenFinal:
    deliverToBridge(msg.userId, "Olá, ", rkFinalAnswer,
                               partial = true, inputTokens = 3, outputTokens = 2)
    deliverToBridge(msg.userId, "mundo", rkFinalAnswer,
                               partial = true, inputTokens = 5, outputTokens = 3)
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                               inputTokens = 11, outputTokens = 7)
  of dmCumulativePartials:
    ## What the tool loop actually emits: each partial is the full text so far.
    deliverToBridge(msg.userId, "Olá, ", rkFinalAnswer,
                    partial = true, inputTokens = 3, outputTokens = 2)
    deliverToBridge(msg.userId, "Olá, mundo", rkFinalAnswer,
                    partial = true, inputTokens = 5, outputTokens = 3)
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                    inputTokens = 11, outputTokens = 7)
  of dmHugeFinal:
    deliverToBridge(msg.userId,
                    repeat('x', MaxTurnBufferBytes + 64), rkFinalAnswer,
                    inputTokens = 11, outputTokens = 7)
  of dmPartialThenError:
    deliverToBridge(msg.userId, "parcial", rkFinalAnswer,
                               partial = true, inputTokens = 3, outputTokens = 2)
    discard fakeBridge.fail(msg.userId,
                            "provider key sk-secret-123 failed")
  of dmTokenEchoFinal:
    ## The real orchestrator copies the token onto every outbox message; the
    ## fake does the same so the bridge sees the registration token.
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                    inputTokens = 11, outputTokens = 7,
                    token = msg.bridgeToken)
  of dmWrongTokenFinal:
    ## A reply produced by another generation of the same user.
    deliverToBridge(msg.userId, finalText, rkFinalAnswer,
                    inputTokens = 11, outputTokens = 7,
                    token = msg.bridgeToken + 1)

proc fakeAuthorize(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
  discard userId
  authVerdict

proc resetFakes() =
  fakeNowMs = 1_000
  fakeBridge = newChatBridge(fakeNowFn, fakeNapFn)
  dispatched = @[]
  dispatchMode = dmNothing
  finalText = ""
  authVerdict = avAllowed

func bodyFor(user, text: string): string =
  $(%* {
    "user": user,
    "messages": [%* {"role": "user", "content": text}],
  })

proc run(body: string; tokenConfigured = true;
         timeoutMs = 50): AgentChatReply =
  waitFor runAgentChat(body, fakeBridge, fakeDispatch, fakeAuthorize,
                       tokenConfigured = tokenConfigured, now = fakeEpochSec,
                       timeoutMs = timeoutMs, model = "donkey/test",
                       nap = fakeAsyncNap)

proc contentOf(body: string): string =
  let node = parseJson(body)
  node{"choices"}[0]{"message"}{"content"}.getStr()

# ── SSE fakes ─────────────────────────────────────────────────────────────────

var
  sseChunks {.threadvar.}: seq[string]
  sseOpened:        bool
  sseAcquireCalls:  int
  sseReleaseCalls:  int
  sseAcquireAllowed = true
  sseFailAt:        int  ## 0 = never fail; N = fail on the Nth sent chunk

proc sseSend(chunk: string): Future[bool] {.gcsafe, raises: [].} =
  sseChunks.add(chunk)
  completed(not (sseFailAt > 0 and sseChunks.len >= sseFailAt))

proc sseOpen(): Future[bool] {.gcsafe, raises: [].} =
  sseOpened = true
  completed(true)

proc sseAcquire(): bool {.gcsafe, raises: [].} =
  inc sseAcquireCalls
  sseAcquireAllowed

proc sseRelease() {.gcsafe, raises: [].} =
  inc sseReleaseCalls

proc resetStream() =
  resetFakes()
  sseChunks = @[]
  sseOpened = false
  sseAcquireCalls = 0
  sseReleaseCalls = 0
  sseAcquireAllowed = true
  sseFailAt = 0

proc runStream(body: string; timeoutMs = 5_000): AgentStreamResult =
  waitFor runAgentStream(
    body             = body,
    bridge           = fakeBridge,
    dispatch         = fakeDispatch,
    authorize        = fakeAuthorize,
    tokenConfigured  = true,
    now              = fakeEpochSec,
    openStream       = sseOpen,
    send             = sseSend,
    acquireSlot      = sseAcquire,
    releaseSlot      = sseRelease,
    streamNow        = fakeNowFn,
    streamNap        = fakeAsyncNap,
    timeoutMs        = timeoutMs,
    model            = "donkey/test",
  )

proc streamNodes(): seq[JsonNode] =
  ## Parses every `data:` payload except the `[DONE]` terminator.
  for chunk in sseChunks:
    if chunk == sseDone():
      continue
    if chunk.startsWith("data: ") and chunk.endsWith("\n\n"):
      let payload = chunk["data: ".len ..< chunk.len - 2]
      result.add(parseJson(payload))

proc doneCount(): int =
  for chunk in sseChunks:
    if chunk == sseDone():
      inc result

proc streamedContent(): string =
  for node in streamNodes():
    result.add(node{"choices"}[0]{"delta"}{"content"}.getStr(""))

# ── success path ──────────────────────────────────────────────────────────────

proc runTests*() =
  suite "runAgentChat success":

    test "dispatches the turn and returns chat.completion with usage":
      resetFakes()
      dispatchMode = dmFinal
      finalText = "olá do agente"

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 200

      let node = parseJson(reply.body)
      check node{"object"}.getStr() == "chat.completion"
      check node{"model"}.getStr() == "donkey/test"
      check node{"created"}.getBiggestInt() == 1_700_000_000
      check node{"choices"}.len == 1
      check node{"choices"}[0]{"message"}{"role"}.getStr() == "assistant"
      check contentOf(reply.body) == "olá do agente"
      check node{"usage"}{"prompt_tokens"}.getInt() == 11
      check node{"usage"}{"completion_tokens"}.getInt() == 7
      check node{"usage"}{"total_tokens"}.getInt() == 18

      check dispatched.len == 1
      check dispatched[0].userId == UserId("api:alice")
      check dispatched[0].channel == ckCli
      check dispatched[0].channelId == "api:alice"
      check dispatched[0].text == "oi"
      check fakeBridge.pendingCount == 0

    test "a paired agent's turn runs as the person it was paired with (E13.4)":
      resetFakes()
      dispatchMode = dmFinal
      finalText = "feito"
      let reply = waitFor runAgentChat(
        body = bodyFor("a2a", "oi"), bridge = fakeBridge, dispatch = fakeDispatch,
        authorize = fakeAuthorize, tokenConfigured = true, now = fakeEpochSec,
        timeoutMs = 5_000, model = "donkey/test", nap = fakeAsyncNap,
        asUser = UserId("u-ana"))
      check reply.status == 200 and contentOf(reply.body) == "feito"
      check dispatched.len == 1 and dispatched[0].userId == UserId("u-ana")
      check dispatched[0].channelId == "a2a"   ## not the person's id as a channel

    test "two users dispatch distinct UserIds":
      resetFakes()
      dispatchMode = dmFinal
      finalText = "ok"

      check run(bodyFor("alice", "a")).status == 200
      check run(bodyFor("bob", "b")).status == 200
      check dispatched.len == 2
      check dispatched[0].userId == UserId("api:alice")
      check dispatched[1].userId == UserId("api:bob")

    test "partials plus the final answer yield exactly one text equal to the final":
      resetFakes()
      dispatchMode = dmPartialThenFinal
      finalText = "resposta final"

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 200
      let node = parseJson(reply.body)
      check node{"choices"}.len == 1
      check contentOf(reply.body) == "resposta final"
      check not contentOf(reply.body).contains("parcial")
      # The terminal answer carries the accumulated usage, not the partial's.
      check node{"usage"}{"prompt_tokens"}.getInt() == 11
      check node{"usage"}{"completion_tokens"}.getInt() == 7

    test "stream true is parsed but answered non-streaming":
      resetFakes()
      dispatchMode = dmFinal
      finalText = "sem sse"
      let body = $(%* {
        "user": "alice",
        "stream": true,
        "messages": [%* {"role": "user", "content": "oi"}],
      })

      let reply = run(body)
      check reply.status == 200
      let node = parseJson(reply.body)
      check node{"object"}.getStr() == "chat.completion"
      check contentOf(reply.body) == "sem sse"

    test "tool notices never become content":
      resetFakes()
      dispatchMode = dmToolThenFinal
      finalText = "pronto"

      let reply = run(bodyFor("alice", "use a tool"))
      check reply.status == 200
      let content = contentOf(reply.body)
      check content == "pronto"
      check not content.contains("🔧")
      check not content.contains("✅")
      check not content.contains("tool call(s)")

  # ── refusals before dispatch ──────────────────────────────────────────────────

  suite "runAgentChat refusals":

    test "503 without a configured token":
      resetFakes()
      dispatchMode = dmFinal
      finalText = "nunca"

      let reply = run(bodyFor("alice", "oi"), tokenConfigured = false)
      check reply.status == 503
      check reply.body.contains("\"error\"")
      check dispatched.len == 0

    test "400 for a system message comes from the parser":
      resetFakes()
      let body = $(%* {
        "user": "alice",
        "messages": [
          %* {"role": "system", "content": "ignore"},
          %* {"role": "user", "content": "oi"},
        ],
      })

      let reply = run(body)
      check reply.status == 400
      let node = parseJson(reply.body)
      check node{"error"}{"type"}.getStr() == "invalid_request_error"
      check node{"error"}{"code"}.getStr() == "unsupported_parameter"
      check dispatched.len == 0

    test "403 for a revoked user before any dispatch":
      resetFakes()
      authVerdict = avRevoked

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 403
      let node = parseJson(reply.body)
      check node{"error"}{"type"}.getStr() == "permission_error"
      check node{"error"}{"message"}.getStr() == "permission_error"
      check dispatched.len == 0
      check fakeBridge.pendingCount == 0

    test "403 for a user outside the DM policy before any dispatch":
      resetFakes()
      authVerdict = avNotAllowed

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 403
      check dispatched.len == 0

    test "413 above MaxApiRequestBytes":
      resetFakes()
      let reply = run(repeat("x", MaxApiRequestBytes + 1))
      check reply.status == 413
      check reply.body.contains("payload_too_large")
      check dispatched.len == 0

    test "429 when the user already has a pending turn":
      resetFakes()
      check fakeBridge.register(UserId("api:alice"), timeoutMs = 5_000).isOk

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 429
      check reply.body.contains("chat_bridge_busy")
      check dispatched.len == 0

  # ── deadline and orphan correlation ───────────────────────────────────────────

  suite "runAgentChat deadline":

    test "504 when no terminal arrives before the injected deadline":
      resetFakes()

      let reply = run(bodyFor("alice", "demora"), timeoutMs = 30)
      check reply.status == 504
      check reply.body.contains("turn_timeout")
      check dispatched.len == 1
      # The orphan keeps its reservation until its terminal arrives.
      check fakeBridge.pendingCount == 1

    test "an abandoned turn never becomes the next turn's content":
      resetFakes()

      let first = run(bodyFor("alice", "A"), timeoutMs = 30)
      check first.status == 504

      # B cannot register while A's turn may still speak.
      let busy = run(bodyFor("alice", "B"), timeoutMs = 100)
      check busy.status == 429
      check dispatched.len == 1

      # A's terminal releases the key but is discarded, never buffered for B.
      let uid = UserId("api:alice")
      check not fakeBridge.deliver(OutboundMessage(
        userId: uid, text: "fim do A", replyKind: rkFinalAnswer))

      dispatchMode = dmFinal
      finalText = "fim do B"
      let second = run(bodyFor("alice", "B"), timeoutMs = 100)
      check second.status == 200
      check contentOf(second.body) == "fim do B"
      check not contentOf(second.body).contains("fim do A")
      check dispatched.len == 2

    test "a turn error closes with 502 and is redacted":
      resetFakes()
      # A dispatch that fails the turn instead of answering it.
      proc failDispatch(msg: InboundMessage) {.gcsafe.} =
        dispatched.add(msg)
        discard fakeBridge.fail(msg.userId, "provider key sk-secret-123 failed")

      let reply = waitFor runAgentChat(bodyFor("alice", "oi"), fakeBridge,
                                       failDispatch, fakeAuthorize,
                                       tokenConfigured = true,
                                       now = fakeEpochSec, timeoutMs = 100,
                                       model = "donkey/test", nap = fakeAsyncNap)
      check reply.status == 502
      check not reply.body.contains("sk-secret-123")
      check reply.body.contains("[redacted]")

  # ── per-turn token end to end ─────────────────────────────────────────────────

  suite "runAgentChat per-turn token":

    test "the dispatched turn carries the registration token and closes it":
      resetFakes()
      dispatchMode = dmTokenEchoFinal
      finalText = "eco do turno"

      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 200
      check contentOf(reply.body) == "eco do turno"
      check dispatched.len == 1
      ## First registration on a fresh bridge.
      check dispatched[0].bridgeToken == 1'u64
      check fakeBridge.pendingCount == 0

    test "a reply from another generation cannot close the turn":
      resetFakes()
      dispatchMode = dmWrongTokenFinal
      finalText = "de outro turno"

      let reply = run(bodyFor("alice", "oi"))
      ## The terminal was discarded, so the turn ran to its deadline.
      check reply.status == 504
      check dispatched.len == 1
      check dispatched[0].bridgeToken == 1'u64
      check fakeBridge.pendingCount == 1

  # ── usage accumulation primitives ─────────────────────────────────────────────

  suite "UsageTotals":

    test "addUsage sums every round":
      var usage = UsageTotals()
      usage = usage.addUsage(10, 2)
      usage = addUsage(3, 4, usage)
      check usage.inputTokens == 13
      check usage.outputTokens == 6

    test "a round's cached tokens are summed too (E8.3)":
      var usage = UsageTotals()
      usage = usage.addUsage(CompletionResponse(inputTokens: 3000, outputTokens: 5,
                                                cacheReadTokens: 2048, cacheWriteTokens: 100))
      usage = usage.addUsage(CompletionResponse(inputTokens: 3100, outputTokens: 7,
                                                cacheReadTokens: 2900))
      check usage.inputTokens == 6100 and usage.outputTokens == 12
      check usage.cacheReadTokens == 4948 and usage.cacheWriteTokens == 100

    test "a fresh tool loop state starts at zero":
      let state = newToolLoopState(@[])
      check state.usage.inputTokens == 0
      check state.usage.outputTokens == 0

  # ── streaming (US-003) ────────────────────────────────────────────────────────

  suite "cumulative partials":

    test "cumulative snapshots reach the client as deltas, not duplicates":
      resetStream()
      dispatchMode = dmCumulativePartials
      finalText = "Olá, mundo"
      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      let nodes = streamNodes()
      var content = ""
      for node in nodes:
        let delta = node["choices"][0]["delta"]
        if delta.hasKey("content"):
          content.add(delta["content"].getStr())
      check content == "Olá, mundo"

  suite "truncation":

    test "a final over the buffer cap reports finish_reason length":
      resetFakes()
      dispatchMode = dmHugeFinal
      let reply = run(bodyFor("alice", "oi"))
      check reply.status == 200
      check parseJson(reply.body)["choices"][0]["finish_reason"].getStr() == "length"

    test "the SSE final chunk reports finish_reason length":
      resetStream()
      dispatchMode = dmHugeFinal
      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      let nodes = streamNodes()
      check nodes[^1]["choices"][0]["finish_reason"].getStr() == "length"

  suite "runAgentStream SSE":

    test "a request for the editor reaches the stream as donkey_editor_request (E10.5)":
      resetStream()
      dispatchMode = dmEditorRequestThenFinal
      finalText = "li"
      check runStream(bodyFor("alice", "oi")).outcome == asCompleted
      var asked: seq[JsonNode]
      for n in streamNodes():
        let a = n{"choices"}{0}{"delta"}{"donkey_editor_request"}
        if not a.isNil: asked.add a
      check asked == @[%* {"id": "ef-1", "method": "fs/read_text_file", "params": {"path": "a.nim"}}]

    test "an approval request reaches the stream as donkey_approval; other chatter does not (E10.4)":
      resetStream()
      dispatchMode = dmApprovalThenFinal
      finalText = "feito"
      check runStream(bodyFor("alice", "oi")).outcome == asCompleted
      var approvals: seq[JsonNode]
      for n in streamNodes():
        let a = n{"choices"}{0}{"delta"}{"donkey_approval"}
        if not a.isNil: approvals.add a
      check approvals.len == 1
      check approvals[0] == %* {"text": "Aprovação necessária: bash", "options": [
        {"label": "✅ Aprovar", "callback": "approval:abc:allow"},
        {"label": "❌ Negar", "callback": "approval:abc:deny"}]}
      check "chatter" notin sseChunks.join

    test "an editor's stream runs as the person it was paired with (E10.2)":
      resetStream()
      dispatchMode = dmFinal
      finalText = "oi, Ana"
      let result = waitFor runAgentStream(
        body = bodyFor("editor", "oi"), bridge = fakeBridge, dispatch = fakeDispatch,
        authorize = fakeAuthorize, tokenConfigured = true, now = fakeEpochSec,
        openStream = sseOpen, send = sseSend, acquireSlot = sseAcquire,
        releaseSlot = sseRelease, streamNow = fakeNowFn, streamNap = fakeAsyncNap,
        timeoutMs = 5_000, model = "donkey/test", asUser = UserId("u-ana"))
      check result.outcome == asCompleted
      check dispatched.len == 1 and dispatched[0].userId == UserId("u-ana")
      check dispatched[0].channelId == "editor"   ## not the person's id as a channel
      check dispatched[0].bridgeToken != 0
      check doneCount() == 1

    test "a stream cut by the chunk limit on partials releases the user's turn":
      ## No terminal ever arrives: the stream closes with `length`, and the
      ## bridge must not keep the turn reserved for a reader that left.
      resetStream()
      dispatchMode = dmManyPartials
      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      check doneCount() == 1
      check streamNodes()[^1]{"choices"}[0]{"finish_reason"}.getStr() == "length"
      ## The turn was abandoned, not left pending: its late terminal is
      ## discarded and frees the user, who can start a new turn.
      deliverToBridge(UserId("api:alice"), "late answer", rkFinalAnswer)
      check fakeBridge.register(UserId("api:alice"), timeoutMs = 1_000).isOk

    test "emits role, one content chunk per partial, a final stop and one [DONE]":
      resetStream()
      dispatchMode = dmTwoPartialsThenFinal
      finalText = "Olá, mundo"

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      check sseOpened
      check sseChunks.len == 5
      check doneCount() == 1
      check sseChunks[^1] == sseDone()

      let nodes = streamNodes()
      check nodes.len == 4
      check nodes[0]["object"].getStr() == "chat.completion.chunk"
      check nodes[0]["choices"][0]["delta"]["role"].getStr() == "assistant"
      check nodes[1]["choices"][0]["delta"]["content"].getStr() == "Olá, "
      check nodes[2]["choices"][0]["delta"]["content"].getStr() == "mundo"
      check nodes[3]["choices"][0]["finish_reason"].getStr() == "stop"
      check nodes[3]["usage"]["prompt_tokens"].getInt() == 11
      check nodes[3]["usage"]["completion_tokens"].getInt() == 7

    test "two partials plus the final yield one answer, not the final twice":
      resetStream()
      dispatchMode = dmTwoPartialsThenFinal
      finalText = "Olá, mundo"

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      check streamedContent() == "Olá, mundo"
      check streamedContent() != "Olá, mundoOlá, mundo"
      let nodes = streamNodes()
      check not nodes[^1]["choices"][0]["delta"].hasKey("content")

    test "a tool notice never appears as delta.content":
      resetStream()
      dispatchMode = dmToolThenFinal
      finalText = "pronto"

      let result = runStream(bodyFor("alice", "use a tool"))
      check result.outcome == asCompleted

      var sawToolCall = false
      let content = streamedContent()
      for node in streamNodes():
        let delta = node["choices"][0]["delta"]
        if delta.hasKey("tool_calls"):
          sawToolCall = true
          check not delta.hasKey("content")
      check sawToolCall
      check content == "pronto"
      check not content.contains("🔧")
      check not content.contains("✅")
      check not content.contains("tool call(s)")

    test "stream false keeps the existing single JSON path":
      resetStream()
      dispatchMode = dmFinal
      finalText = "sem sse"
      let body = $(%* {
        "user": "alice",
        "stream": false,
        "messages": [%* {"role": "user", "content": "oi"}],
      })

      check not agentChatStreamRequested(body)
      check not agentChatStreamRequested(bodyFor("alice", "oi"))

      let reply = run(body)
      check reply.status == 200
      check parseJson(reply.body){"object"}.getStr() == "chat.completion"
      check contentOf(reply.body) == "sem sse"
      check sseChunks.len == 0

    test "an error after the first byte emits an error event and no [DONE]":
      resetStream()
      dispatchMode = dmPartialThenError

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asErrored
      check sseOpened
      check sseChunks.len == 3
      check doneCount() == 0

      let nodes = streamNodes()
      check nodes.len == 3
      check nodes[0]["choices"][0]["delta"]["role"].getStr() == "assistant"
      check nodes[1]["choices"][0]["delta"]["content"].getStr() == "parcial"
      check nodes[2]["error"]["code"].getStr() == "turn_error"
      for chunk in sseChunks:
        check not chunk.contains("sk-secret-123")

    test "the SSE slot is released after a completed stream":
      resetStream()
      dispatchMode = dmFinal
      finalText = "ok"

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asCompleted
      check sseAcquireCalls == 1
      check sseReleaseCalls == 1
      check fakeBridge.pendingCount == 0

    test "the SSE slot is released when the client aborts":
      resetStream()
      dispatchMode = dmTwoPartialsThenFinal
      finalText = "Olá, mundo"
      sseFailAt = 2  # role chunk succeeds, the first content chunk fails

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asClientGone
      check sseReleaseCalls == 1
      check fakeBridge.pendingCount == 0  # the finished turn was already drained

    test "the SSE slot is released on the deadline":
      resetStream()
      dispatchMode = dmNothing

      let result = runStream(bodyFor("alice", "demora"), timeoutMs = 30)
      check result.outcome == asErrored
      check sseOpened
      check sseReleaseCalls == 1
      check doneCount() == 0
      check streamNodes()[^1]["error"]["code"].getStr() == "turn_timeout"

    test "a full SSE budget is refused before dispatch":
      resetStream()
      sseAcquireAllowed = false

      let result = runStream(bodyFor("alice", "oi"))
      check result.outcome == asPreflightError
      check result.reply.status == 429
      check dispatched.len == 0
      check sseReleaseCalls == 0
      check sseChunks.len == 0

when isMainModule:
  runTests()
