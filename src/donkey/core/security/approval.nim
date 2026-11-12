## approval — pure types and parsing for the tool approval gate.
##
## Approval requests are created before a risky native tool executes. The user
## can approve or deny through an inline callback (`approval:<id>:allow|deny`),
## a chat command (`/approve <id>` / `/deny <id>`) or the `ctl` CLI.

import std/[options, strutils]

type
  ApprovalStatus* = enum
    apsPending  = "pending"
    apsApproved = "approved"
    apsDenied   = "denied"
    apsExpired  = "expired"

  ApprovalRequest* = object
    id*:          string
    userId*:      string
    channel*:     string
    toolName*:    string
    summary*:     string
    createdAtMs*: int64
    expiresAtMs*: int64
    status*:      ApprovalStatus

  ApprovalDecision* = enum
    adApproved
    adDenied
    adTimeout

const
  ApprovalIdLength* = 8
  ApprovalTerminalRetentionMs* = 3_600_000'i64 ## keep decisions for 1 hour

func isValidApprovalId*(id: string): bool =
  if id.len != ApprovalIdLength:
    return false
  for c in id:
    if c notin {'a'..'z', '0'..'9'}:
      return false
  true

func approvalCallbackData*(id: string; approved: bool): string =
  "approval:" & id & (if approved: ":allow" else: ":deny")

func parseApprovalCallback*(data: string): Option[tuple[id: string; approved: bool]] =
  let parts = data.strip.split(':')
  if parts.len != 3 or parts[0] != "approval":
    return none(tuple[id: string; approved: bool])
  if not isValidApprovalId(parts[1]):
    return none(tuple[id: string; approved: bool])
  case parts[2]
  of "allow": some((id: parts[1], approved: true))
  of "deny":  some((id: parts[1], approved: false))
  else:       none(tuple[id: string; approved: bool])

func parseApprovalCommand*(text: string): Option[tuple[id: string; approved: bool]] =
  let parts = text.strip.splitWhitespace()
  if parts.len != 2:
    return none(tuple[id: string; approved: bool])
  if not isValidApprovalId(parts[1]):
    return none(tuple[id: string; approved: bool])
  case parts[0]
  of "/approve": some((id: parts[1], approved: true))
  of "/deny":    some((id: parts[1], approved: false))
  else:          none(tuple[id: string; approved: bool])

func isPollCommand*(text: string): bool =
  text.strip == "/poll"

func isExpired*(request: ApprovalRequest; nowMs: int64): bool =
  request.status == apsPending and nowMs >= request.expiresAtMs

func parseStatus*(raw: string): Option[ApprovalStatus] =
  case raw
  of "pending":  some(apsPending)
  of "approved": some(apsApproved)
  of "denied":   some(apsDenied)
  of "expired":  some(apsExpired)
  else:          none(ApprovalStatus)
