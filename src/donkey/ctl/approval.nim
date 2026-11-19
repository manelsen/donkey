## ctl/approval.nim — `donkey ctl approval` handlers.

import ../core/pipeops
import ../adapters/state/approval_store

# ── ctl approval commands ──────────────────────────────────────────────────────

proc ctlApprovalList*(store: ApprovalStore; userId = ""): Result[void, string] =
  let pending = store.listPending(userId)
  if pending.isErr:
    return err(pending.error)
  if pending.get().len == 0:
    echo "No pending approvals."
    return ok()
  echo "id\tuser\ttool\tsummary\texpires_in"
  for request in pending.get():
    let remaining = int(max(0'i64, request.expiresAtMs - epochMs()) div 1000)
    echo request.id & "\t" & request.userId & "\t" & request.toolName & "\t" &
         request.summary & "\t" & $remaining & "s"
  ok()

proc ctlApprovalDecide*(store: ApprovalStore; id: string;
                        approved: bool): Result[void, string] =
  let res = store.decide(id, "", approved, admin = true)
  if res.isErr:
    return err(res.error)
  echo (if approved: "Approved " else: "Denied ") & id
  ok()
