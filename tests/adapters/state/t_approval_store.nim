import std/[options, os, unittest]
import donkey/adapters/state/approval_store
import donkey/core/pipeops
import donkey/core/security/approval

const ApprovalTmp = "/tmp/donkey_approval_store_tests"

suite "ApprovalStore":

  test "create, list and approve a request":
    removeDir(ApprovalTmp / "approve")
    let store = newApprovalStore(ApprovalTmp / "approve" / "approvals.json")
    let created = store.create("u1", "telegram", "bash", "rm -rf x", 60_000, 1000)
    check created.isOk
    let request = created.get()
    check request.status == apsPending
    check isValidApprovalId(request.id)
    check store.listPending("u1", 1000).get().len == 1
    check store.listPending("u2", 1000).get().len == 0

    check store.decide(request.id, "u1", true, nowMs = 1000).isOk
    check store.status(request.id, 1000).get() == apsApproved
    check store.listPending("u1", 1000).get().len == 0

  test "a different user cannot decide":
    removeDir(ApprovalTmp / "owner")
    let store = newApprovalStore(ApprovalTmp / "owner" / "approvals.json")
    let request = store.create("owner", "slack", "bash", "ls", 60_000, 1000).get()
    check store.decide(request.id, "intruder", true, nowMs = 1000).isErr
    check store.status(request.id, 1000).get() == apsPending

  test "admin decision bypasses ownership":
    removeDir(ApprovalTmp / "admin")
    let store = newApprovalStore(ApprovalTmp / "admin" / "approvals.json")
    let request = store.create("owner", "slack", "bash", "ls", 60_000, 1000).get()
    check store.decide(request.id, "", false, admin = true, nowMs = 1000).isOk
    check store.status(request.id, 1000).get() == apsDenied

  test "expired pending requests are pruned":
    removeDir(ApprovalTmp / "expiry")
    let store = newApprovalStore(ApprovalTmp / "expiry" / "approvals.json")
    let request = store.create("u1", "telegram", "bash", "ls", 1_000, 1000).get()
    check store.listPending("u1", 500).get().len == 1
    check store.listPending("u1", 3000).get().len == 0
    check store.status(request.id, 3000).isErr

  test "persists across store instances":
    removeDir(ApprovalTmp / "persist")
    let path = ApprovalTmp / "persist" / "approvals.json"
    let request = newApprovalStore(path).create("u1", "telegram", "bash", "ls", 60_000, 1000).get()
    let reopened = newApprovalStore(path)
    check reopened.listPending("u1", 1000).get().len == 1
    check reopened.decide(request.id, "u1", true, nowMs = 1000).isOk
    check newApprovalStore(path).status(request.id, 1000).get() == apsApproved

  test "caps pending requests per user":
    removeDir(ApprovalTmp / "cap")
    let store = newApprovalStore(ApprovalTmp / "cap" / "approvals.json")
    for i in 0 ..< MaxPendingPerUser:
      check store.create("u1", "telegram", "bash", "cmd" & $i, 60_000, 1000 + i).isOk
    check store.create("u1", "telegram", "bash", "overflow", 60_000, 2000).isErr
