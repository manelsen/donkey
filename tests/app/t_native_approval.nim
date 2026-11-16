import std/[options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/adapters/filesystem/fs_adapter
import donkey/app/approval_runtime
import donkey/app/session_state
import donkey/app/session_manager
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
      fs: newFsAdapter(),
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
      fs: newFsAdapter(),
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

    let markerName = "donkey_execute_code_denied_" & $getCurrentProcessId()
    let marker = "/tmp" / markerName
    removeFile(marker)
    defer: removeFile(marker)
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smOci,
    )
    let call = ToolCallRequest(
      id: "t3",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"touch """ & markerName & """"}""",
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
    let markerName = "donkey_execute_code_store_fail_" & $getCurrentProcessId()
    let marker = "/tmp" / markerName
    removeFile(marker)
    defer: removeFile(marker)
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smOci,
    )
    let call = ToolCallRequest(
      id: "t6",
      name: "execute_code",
      inputJson: """{"language":"shell","code":"touch """ & markerName & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "denied" in res.text
    check not fileExists(marker)

  test "execute_code approval summary shows language and code":
    putEnv("DONKEY_CODE_TIMEOUT_SEC", "30")
    defer: delEnv("DONKEY_CODE_TIMEOUT_SEC")
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
      fs: newFsAdapter(),
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
    check "timeout=30s" in captured
    check "echo hello" in captured
    check "requires sandbox.mode" in res.text

  test "execute_code wasm approval shows the module path, not code":
    var captured = ""
    let approveStore = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          captured = summary
        ok(ApprovalRequest(id: "code0003", userId: userId, channel: channel,
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
      fs: newFsAdapter(),
      paddockDir: "/tmp",
      sandboxMode: cfgTypes.smWasm,
    )
    let call = ToolCallRequest(
      id: "t7",
      name: "execute_code",
      inputJson: """{"language":"wasm","code":"not the module","wasm_path":"missing.wasm"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "wasm_path=missing.wasm" in captured
    check "not the module" notin captured

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
      fs: newFsAdapter(),
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

suite "large file write approval summary":

  test "summary mode approves a large fs_write with path, bytes and sha1":
    putEnv("DONKEY_APPROVAL_LARGE_WRITES", "summary")
    defer: delEnv("DONKEY_APPROVAL_LARGE_WRITES")
    let root = "/tmp/donkey_large_write_approval"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)

    var created = 0
    var captured = ""
    let store = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          inc created
          captured = summary
        ok(ApprovalRequest(id: "bigwrite", userId: userId, channel: channel,
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
    configureApprovalService(store, @["fs_write"])
    defer: resetApprovalService()

    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: root,
    )
    let payload = repeat("x", 2600)
    let call = ToolCallRequest(
      id: "t8",
      name: "fs_write",
      inputJson: """{"path":"big.md","format":"text","mode":"replace","content":"""" & payload & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOutput
    check created == 1
    check "path=big.md" in captured
    check "bytes=2600" in captured
    check "sha1=" in captured
    check fileExists(root / "big.md")

  test "reject mode still blocks a large fs_write":
    delEnv("DONKEY_APPROVAL_LARGE_WRITES")
    var created = 0
    let store = ApprovalStorePort(
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
    configureApprovalService(store, @["fs_write"])
    defer: resetApprovalService()

    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: "/tmp",
    )
    let payload = repeat("x", 2600)
    let call = ToolCallRequest(
      id: "t9",
      name: "fs_write",
      inputJson: """{"path":"big.md","format":"text","mode":"replace","content":"""" & payload & """"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "too large" in res.text
    check created == 0

  test "summary uses the serialized lines content, not getStr":
    putEnv("DONKEY_APPROVAL_LARGE_WRITES", "summary")
    defer: delEnv("DONKEY_APPROVAL_LARGE_WRITES")
    let root = "/tmp/donkey_large_write_lines"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)

    var captured = ""
    let store = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          captured = summary
        ok(ApprovalRequest(id: "lineswrite", userId: userId, channel: channel,
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
    configureApprovalService(store, @["fs_write"])
    defer: resetApprovalService()

    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: root,
    )
    var items = newSeq[string]()
    for _ in 0 ..< 300:
      items.add("\"linha de teste\"")
    let call = ToolCallRequest(
      id: "t10",
      name: "fs_write",
      inputJson: """{"path":"big.txt","format":"lines","mode":"replace","content":[""" &
        items.join(",") & "]}",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOutput
    check "format=lines" in captured
    check "bytes=4500" in captured
    check "bytes=0" notin captured
    check fileExists(root / "big.txt")


suite "native stop request":

  test "a pending stop aborts before approval":
    var created = 0
    let store = ApprovalStorePort(
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
    configureApprovalService(store, @["bash"])
    defer: resetApprovalService()

    let stoppedUser = "u1"
    requestUserStop(stoppedUser)
    defer: clearUserStop(stoppedUser)
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      outbox: outbox,
      approval: currentApprovalService(),
      log: nativeApprovalLog,
      fs: newFsAdapter(),
      paddockDir: "/tmp",
      stopGeneration: currentSessionStopGeneration(),
    )
    let call = ToolCallRequest(
      id: "stop1",
      name: "bash",
      inputJson: """{"command":"touch /tmp/donkey_stop_should_not_exist"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check "stopping" in res.text
    check created == 0
    check not fileExists("/tmp/donkey_stop_should_not_exist")
