import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/approval_runtime
import donkey/app/session_state
import donkey/config/types as cfgTypes
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

  test "oversized approval action is blocked instead of truncated":
    var created = 0
    let dummyStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          inc created
        err("must not be called"),
      status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
        err("must not be called"),
    )
    configureApprovalService(dummyStore, @["edit_file"])
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
    let longEdits = repeat("x", 1600)
    let call = ToolCallRequest(
      id: "t2",
      name: "edit_file",
      inputJson: """{"path":"/tmp/x","edits":[{"op":"replace","text":"""" & longEdits & """"}]}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "too large" in res.text
    check created == 0

  test "execute_code is denied before any sandbox work":
    let denyStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        ok(ApprovalRequest(id: "code0001", userId: userId, channel: channel,
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
    configureApprovalService(denyStore, @["execute_code"])
    defer: resetApprovalService()

    let marker = "/tmp/donkey_execute_code_denied_" & $getCurrentProcessId()
    removeFile(marker)
    defer: removeFile(marker)
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smOci,
    )
    let call = ToolCallRequest(
      id: "t3",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"touch """ & marker & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "denied" in res.text
    check not fileExists(marker)

  test "execute_code approval store failure is fail-closed":
    let failingStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        err("store unavailable"),
      status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
        err("must not be called"),
    )
    configureApprovalService(failingStore, @["execute_code"])
    defer: resetApprovalService()
    let marker = "/tmp/donkey_execute_code_store_fail_" & $getCurrentProcessId()
    removeFile(marker)
    defer: removeFile(marker)
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smOci,
    )
    let call = ToolCallRequest(
      id: "t6",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"touch """ & marker & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "denied" in res.text
    check not fileExists(marker)

  test "execute_code approval summary shows language and code":
    var captured = ""
    let approveStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          captured = summary
        ok(ApprovalRequest(id: "code0002", userId: userId, channel: channel,
                           toolName: toolName, summary: summary,
                           createdAtMs: 0, expiresAtMs: 60_000,
                           status: apsPending)),
      status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
        ok(apsApproved),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        ok(),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
        ok(newSeq[ApprovalRequest]()),
    )
    configureApprovalService(approveStore, @["execute_code"])
    defer: resetApprovalService()

    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smNone,
    )
    let call = ToolCallRequest(
      id: "t4",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"echo hello"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "language=shell" in captured
    check "echo hello" in captured
    check "requires sandbox.mode" in res.text

  test "oversized execute_code source is blocked before approval":
    var created = 0
    let dummyStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          inc created
        err("must not be called"),
      status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        err("must not be called"),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
        err("must not be called"),
    )
    configureApprovalService(dummyStore, @["execute_code"])
    defer: resetApprovalService()
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smOci,
    )
    let call = ToolCallRequest(
      id: "t5",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"""" & repeat("x", 1600) & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "too large" in res.text
    check created == 0
