## ApprovalPort — persistence/decision boundary for the tool approval gate.
##
## Application code only sees these callbacks; the file-backed implementation
## lives in adapters/state/approval_store.nim.

import ../core/pipeops
import ../core/security/approval

type
  ApprovalStorePort* = object
    create*: proc(userId: string; channel: string; toolName, summary: string;
                  ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].}
    decide*: proc(id, userId: string; approved: bool;
                  admin: bool): Result[void, string] {.gcsafe, raises: [].}
    status*: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].}
    listPending*: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].}
