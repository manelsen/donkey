## US-002 — non-streaming `POST /v1/chat/completions` with the agent turn loop.
##
## The dispatch, authorization and clock are fakes: no provider, no network,
## no real sleep. Content is only the terminal event; partials and tool
## notices never become content.

import std/[json, strutils, unittest]
import results
import donkey/core/types
import donkey/core/tooling/tool_loop
import donkey/domain/message
import donkey/domain/gateway/identity_pure
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

# ── fake dispatch / authorize ─────────────────────────────────────────────────

type DispatchMode = enum
  dmNothing
  dmFinal
  dmPartialThenFinal
  dmToolThenFinal

var fakeBridge {.threadvar.}: ChatBridge
var dispatched {.threadvar.}: seq[InboundMessage]
var dispatchMode = dmNothing
var finalText {.threadvar.}: string
var authVerdict = avAllowed

proc deliverToBridge(userId: UserId; text: string; kind = rkFinalAnswer;
                     partial = false; tool = ToolCallNotice();
                     inputTokens = 0; outputTokens = 0) {.gcsafe.} =
  discard fakeBridge.deliver(OutboundMessage(
    userId:  userId,
    text:    text,
    replyKind: kind,
    isPartial: partial,
    toolCall: tool,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
  ))

proc fakeDispatch(msg: InboundMessage) {.gcsafe.} =
  dispatched.add(msg)
  case dispatchMode
  of dmNothing:
    discard
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
  runAgentChat(body, fakeBridge, fakeDispatch, fakeAuthorize,
               tokenConfigured = tokenConfigured, now = fakeEpochSec,
               timeoutMs = timeoutMs, model = "donkey/test")

proc contentOf(body: string): string =
  let node = parseJson(body)
  node{"choices"}[0]{"message"}{"content"}.getStr()

# ── success path ──────────────────────────────────────────────────────────────

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

    let reply = runAgentChat(bodyFor("alice", "oi"), fakeBridge, failDispatch,
                             fakeAuthorize, tokenConfigured = true,
                             now = fakeEpochSec, timeoutMs = 100,
                             model = "donkey/test")
    check reply.status == 502
    check not reply.body.contains("sk-secret-123")
    check reply.body.contains("[redacted]")

# ── usage accumulation primitives ─────────────────────────────────────────────

suite "UsageTotals":

  test "addUsage sums every round":
    var usage = UsageTotals()
    usage = usage.addUsage(10, 2)
    usage = addUsage(3, 4, usage)
    check usage.inputTokens == 13
    check usage.outputTokens == 6

  test "a fresh tool loop state starts at zero":
    let state = newToolLoopState(@[])
    check state.usage.inputTokens == 0
    check state.usage.outputTokens == 0
