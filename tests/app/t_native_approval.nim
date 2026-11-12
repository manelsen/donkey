import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/approval_runtime
import donkey/app/session_state
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/approval
import donkey/core/types
import donkey/domain/message
import donkey/ports/approval

let nativeApprovalLog = newLogger("test.native.approval", lvlError)

suite "native tool approval gate":

  test "denied risky tool never executes":
    let denyStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        ok(ApprovalRequest(id: "abcdefgh", userId: userId, channel: channel,
                           toolName: toolName, summary: summary,
                           createdAtMs: 0, expiresAtMs: 60_000,
                           status: apsPending)),
      status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
        ok(apsDenied),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        ok(),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
        ok(newSeq[ApprovalRequest]()),
    )
    configureApprovalService(denyStore, @["bash"])
    defer: resetApprovalService()

    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      paddockDir: "/tmp",
    )
    let call = ToolCallRequest(
      id: "t1",
      name: "bash",
      inputJson: """{"command":"touch /tmp/donkey_approval_should_not_exist"}""",
    )
    let res = waitFor executeNativeTool(
      call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "denied" in res.text
    check not fileExists("/tmp/donkey_approval_should_not_exist")
    check outbox.len == 1
