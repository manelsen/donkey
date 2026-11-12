import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/approval_runtime
import donkey/adapters/state/approval_store
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/approval
import donkey/core/types
import donkey/domain/message
import donkey/ports/approval

const ApprovalRuntimeTmp = "/tmp/donkey_approval_runtime_tests"
let approvalLog = newLogger("test.approval", lvlError)

suite "approval runtime":

  test "policy defaults and opt-out":
    check "bash" in parseApprovalTools("")
    check "edit_file" in parseApprovalTools("")
    check parseApprovalTools("none").len == 0
    check parseApprovalTools("bash, rm ,bash") == @["bash", "rm"]

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
