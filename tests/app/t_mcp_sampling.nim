## MCP sampling in the daemon (PRD-roadmap E5.1-E5.3): a server's request,
## made in the middle of a person's tool call, is shown to that person, who
## approves it once, always for that server, or denies it; approved, it runs
## through the person's model without tools and within the daily cap.

import std/[json, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/approval_runtime
import donkey/app/mcp_sampling
import donkey/app/provider_executor
import donkey/adapters/state/approval_store
import donkey/adapters/state/standing_approvals
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/domain/tools/mcp_sampling_pure
import donkey/ports/tool

const Tmp = "/tmp/donkey_mcp_sampling_tests"
let testLog = newLogger("test.sampling", lvlError)

proc request(text = "2+2?"; maxTokens = 50): JsonNode =
  %* {"messages": [{"role": "user", "content": {"type": "text", "text": text}}],
      "maxTokens": maxTokens}

type Model = ref object
  calls: int
  lastReq: CompletionRequest

proc deps(m: Model; outbox: AsyncQueue[OutboundMessage]; cap = 10_000): SamplingDeps =
  SamplingDeps(
    outbox: outbox,
    completeFor: proc(userId: UserId): AsyncCompleteFn {.gcsafe.} =
      result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}:
          inc m.calls
          m.lastReq = req
        return ok(CompletionResponse(text: "4", inputTokens: 10, outputTokens: 5)),
    budget: new(SamplingBudget),
    dailyTokenCap: cap,
    maxTokensCap: 1_000,
    log: testLog)

proc fresh(tag: string) =
  removeDir(Tmp / tag)
  configureApprovalService(newApprovalStore(Tmp / tag / "approvals.json").toApprovalPort(),
    @[], timeoutSec = 10.0,
    standing = newStandingApprovals(Tmp / tag / "standing.json").toStandingPort())

proc press(outbox: AsyncQueue[OutboundMessage]; answer: string): Future[string] {.async.} =
  let card = await outbox.get()
  for row in card.keyboard:
    for (_, cb) in row:
      if cb.endsWith(":" & answer):
        discard tryHandleApprovalInput(card.userId, cb)
  return card.text

let call = ToolCall(id: "c1", name: "summarise", userId: "u1", channel: "telegram")

proc runTests*() =
  suite "mcp sampling — the handler":

    test "approved once, it runs the person's model without tools and answers":
      fresh("once")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let handler = samplingHandler("filesystem", serverIdentity("npx", @["fs"]), deps(m, outbox))
      let person = press(outbox, "allow")
      let r = waitFor handler("sampling/createMessage", request(), call)
      check "filesystem" in waitFor(person)
      check r.isOk
      check r.get["content"]["text"].getStr == "4"
      check m.calls == 1 and m.lastReq.tools.len == 0

    test "denied, the server gets an error and the model is not called":
      fresh("deny")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]), deps(m, outbox))
      let person = press(outbox, "deny")
      let r = waitFor handler("sampling/createMessage", request(), call)
      discard waitFor person
      check r.isErr and "declined" in r.error
      check m.calls == 0

    test "'always' stands for that server: the next request is not asked":
      fresh("always")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]), deps(m, outbox))
      let person = press(outbox, "always")
      check (waitFor handler("sampling/createMessage", request(), call)).isOk
      discard waitFor person
      check (waitFor handler("sampling/createMessage", request("3+3?"), call)).isOk
      check outbox.len == 0 and m.calls == 2
      ## another server with the same name is asked
      let other = samplingHandler("fs", serverIdentity("npx", @["other"]), deps(m, outbox))
      let person2 = press(outbox, "deny")
      check (waitFor other("sampling/createMessage", request(), call)).isErr
      discard waitFor person2

    test "without a person behind the call there is nobody to ask: refused":
      fresh("nobody")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]), deps(m, outbox))
      let r = waitFor handler("sampling/createMessage", request(), ToolCall())
      check r.isErr and outbox.len == 0 and m.calls == 0

    test "past the server's daily cap it is refused without asking":
      fresh("cap")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]),
                                    deps(m, outbox, cap = 40))
      let r = waitFor handler("sampling/createMessage", request(maxTokens = 50), call)
      check r.isErr and "daily" in r.error
      check outbox.len == 0 and m.calls == 0

    test "the cap counts what may be spent, the request's limit after capping":
      fresh("capped")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      ## asks for 50000, sent at most 1000 (maxTokensCap); 2000 a day fits it
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]),
                                    deps(m, outbox, cap = 2_000))
      let person = press(outbox, "allow")
      check (waitFor handler("sampling/createMessage", request(maxTokens = 50_000), call)).isOk
      discard waitFor person
      check m.lastReq.maxTokens == 1_000

    test "requests in flight hold their share of the cap, so the cap holds":
      fresh("race")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let m = Model()
      let d = deps(m, outbox, cap = 1_500)
      let handler = samplingHandler("fs", serverIdentity("npx", @["fs"]), d)
      ## the first waits for the person; the second comes meanwhile
      let first = handler("sampling/createMessage", request(maxTokens = 1_000), call)
      let second = waitFor handler("sampling/createMessage", request(maxTokens = 1_000), call)
      check second.isErr and "daily" in second.error
      let person = press(outbox, "deny")
      discard waitFor person
      check (waitFor first).isErr
      ## the denied request gave its share back
      let person2 = press(outbox, "allow")
      check (waitFor handler("sampling/createMessage", request(maxTokens = 1_000), call)).isOk
      discard waitFor person2

    test "other requests from the server are not supported":
      fresh("other")
      defer: resetApprovalService()
      let outbox = newAsyncQueue[OutboundMessage]()
      let handler = samplingHandler("fs", "id", deps(Model(), outbox))
      check (waitFor handler("roots/list", newJObject(), call)).isErr

when isMainModule:
  runTests()
