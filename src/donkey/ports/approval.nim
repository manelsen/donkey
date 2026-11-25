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
    lookup*: proc(id: string): Result[ApprovalRequest, string] {.gcsafe, raises: [].}

  StandingApprovalPort* = object
    ## Approvals that stand for a person and a key (an MCP server's sampling):
    ## granted by the "always" button, revoked by command (E5.2).
    has*:    proc(userId, key: string): bool {.gcsafe, raises: [].}
    grant*:  proc(userId, key: string): Result[void, string] {.gcsafe, raises: [].}
    revoke*: proc(userId, key: string): Result[void, string] {.gcsafe, raises: [].}
    list*:   proc(userId: string): seq[string] {.gcsafe, raises: [].}

func hasStanding*(p: StandingApprovalPort): bool =
  p.has != nil and p.grant != nil and p.revoke != nil and p.list != nil
