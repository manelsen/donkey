import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/approval_runtime
import donkey/app/session_manager
import donkey/core/commands/command_routing
import donkey/adapters/state/approval_store
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/approval
import donkey/core/types
import donkey/domain/message
import donkey/ports/approval

const ApprovalRuntimeTmp = "/tmp/donkey_approval_runtime_tests"
let approvalLog = newLogger("test.approval", lvlError)

proc runTests*() =
  suite "approval runtime":

    test "policy defaults and opt-out":
      check "bash" in parseApprovalTools("")
      check "edit_file" in parseApprovalTools("")
      check "execute_code" in parseApprovalTools("")
      check parseApprovalTools("none").len == 0
      check parseApprovalTools("bash, rm ,bash") == @["bash", "rm"]

    test "wildcard policy covers native, MCP and skill tools":
      configureApprovalService(ApprovalStorePort(), @["*"])
      defer: resetApprovalService()
      check requiresApproval("bash")
      check requiresApproval("mcp_github_create_issue")
      check requiresApproval(currentApprovalService(), "some_skill_tool")

    test "MCP input summaries are full or rejected":
      check approvalInputSummary("""{"query":"x"}""") == """{"query":"x"}"""
      check approvalInputSummary(repeat("x", 1600)).len == 0

    test "chat commands decide and poll":
      removeDir(ApprovalRuntimeTmp / "chat")
      let store = newApprovalStore(ApprovalRuntimeTmp / "chat" / "approvals.json")
      configureApprovalService(store.toApprovalPort(), @["bash"])
      defer: resetApprovalService()

      let request = store.create("u1", "telegram", "bash", "rm -rf x", 60_000, epochMs()).get()
      let wrong = tryHandleApprovalInput(UserId("u2"), "/approve " & request.id)
      check wrong.isSome
      check "another user" in wrong.get()
      check store.status(request.id).get() == apsPending

      let approved = tryHandleApprovalInput(UserId("u1"), "/approve " & request.id)
      check approved.isSome
      check approved.get().contains("Aprovado")
      check store.status(request.id).get() == apsApproved

    test "poll lists pending requests":
      removeDir(ApprovalRuntimeTmp / "poll")
      let store = newApprovalStore(ApprovalRuntimeTmp / "poll" / "approvals.json")
      configureApprovalService(store.toApprovalPort(), @["bash"])
      defer: resetApprovalService()

      let request = store.create("u1", "telegram", "bash", "ls", 60_000, epochMs()).get()
      let poll = tryHandleApprovalInput(UserId("u1"), "/poll")
      check poll.isSome
      check request.id in poll.get()

    test "inline callback data approves":
      removeDir(ApprovalRuntimeTmp / "callback")
      let store = newApprovalStore(ApprovalRuntimeTmp / "callback" / "approvals.json")
      configureApprovalService(store.toApprovalPort(), @["bash"])
      defer: resetApprovalService()

      let request = store.create("u1", "slack", "bash", "ls", 60_000, epochMs()).get()
      let reply = tryHandleApprovalInput(
        UserId("u1"), approvalCallbackData(request.id, true))
      check reply.isSome
      check store.status(request.id).get() == apsApproved

    test "requestAndWait returns approved and emits a message":
      var statusCalls = 0
      let fake = ApprovalStorePort(
        create: proc(userId: string; channel: string; toolName, summary: string;
                     ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
          ok(ApprovalRequest(id: "abcdefgh", userId: userId, channel: channel,
                             toolName: toolName, summary: summary,
                             createdAtMs: 0, expiresAtMs: 60_000,
                             status: apsPending)),
        status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
          {.cast(gcsafe).}:
            inc statusCalls
          ok(apsApproved),
        decide: proc(id, userId: string; approved: bool;
                     admin: bool): Result[void, string] {.gcsafe, raises: [].} =
          ok(),
        listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
          ok(newSeq[ApprovalRequest]()),
      )
      configureApprovalService(fake, @["bash"])
      defer: resetApprovalService()

      let outbox = newAsyncQueue[OutboundMessage](4)
      let decision = waitFor requestAndWait(
        currentApprovalService(), UserId("u1"), ckTelegram, outbox,
        "bash", "ls", approvalLog)
      check decision == adApproved
      check outbox.len == 1
      check statusCalls >= 1

    test "requestAndWait aborts before creating when stop is requested":
      var created = 0
      let fake = ApprovalStorePort(
        create: proc(userId: string; channel: string; toolName, summary: string;
                     ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
          {.cast(gcsafe).}:
            inc created
          err("must not be called"),
        status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
          err("must not be called"),
        decide: proc(id, userId: string; approved: bool;
                     admin: bool): Result[void, string] {.gcsafe, raises: [].} =
          ok(),
        listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
          err("must not be called"),
      )
      configureApprovalService(fake, @["bash"])
      defer: resetApprovalService()

      let outbox = newAsyncQueue[OutboundMessage](4)
      let stopCheck = proc(): bool {.gcsafe, raises: [].} = true
      let decision = waitFor requestAndWait(
        currentApprovalService(), UserId("u1"), ckTelegram, outbox,
        "bash", "ls", approvalLog, shouldStop = stopCheck)
      check decision == adDenied
      check created == 0
      check outbox.len == 0

    test "cancelPendingApprovals denies every pending request for the user":
      var denied = 0
      let fake = ApprovalStorePort(
        create: proc(userId: string; channel: string; toolName, summary: string;
                     ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
          err("must not be called"),
        status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
          err("must not be called"),
        decide: proc(id, userId: string; approved: bool;
                     admin: bool): Result[void, string] {.gcsafe, raises: [].} =
          {.cast(gcsafe).}:
            if not approved:
              inc denied
          ok(),
        listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
          ok(@[
            ApprovalRequest(id: "a1", userId: userId, channel: "telegram",
                            toolName: "bash", summary: "ls", createdAtMs: 0,
                            expiresAtMs: 60_000, status: apsPending),
            ApprovalRequest(id: "a2", userId: userId, channel: "telegram",
                            toolName: "bash", summary: "pwd", createdAtMs: 0,
                            expiresAtMs: 60_000, status: apsPending),
          ]),
      )
      configureApprovalService(fake, @["bash"])
      defer: resetApprovalService()
      cancelPendingApprovals(UserId("u1"))
      check denied == 2

    test "turn interrupt policy is reusable by channels":
      check interruptsTurn(cmdStop)
      check interruptsTurn(cmdNew)
      check interruptsTurn(cmdRestart)
      check interruptsTurn(cmdReset)
      check not interruptsTurn(cmdDebug)
      check not interruptsTurn(cmdCompact)

      var denied = 0
      let fake = ApprovalStorePort(
        create: proc(userId: string; channel: string; toolName, summary: string;
                     ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
          err("must not be called"),
        status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
          err("must not be called"),
        decide: proc(id, userId: string; approved: bool;
                     admin: bool): Result[void, string] {.gcsafe, raises: [].} =
          {.cast(gcsafe).}:
            if not approved:
              inc denied
          ok(),
        listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
          ok(@[ApprovalRequest(id: "i1", userId: userId, channel: "telegram",
                               toolName: "bash", summary: "ls", createdAtMs: 0,
                               expiresAtMs: 60_000, status: apsPending)]),
      )
      configureApprovalService(fake, @["bash"])
      defer: resetApprovalService()
      var sm: SessionManager
      sm.init()
      let before = currentUserInterrupt("interrupt-user")
      requestTurnInterrupt(sm, UserId("interrupt-user"))
      check isUserStoppedSince("interrupt-user", before)
      check denied == 1
      ## A turn that starts after the interrupt records the new counter and is
      ## not stopped by it.
      let after = currentUserInterrupt("interrupt-user")
      check not isUserStoppedSince("interrupt-user", after)

when isMainModule:
  runTests()
