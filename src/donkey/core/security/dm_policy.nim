## dm_policy — Pure DM security policy helpers.
##
## Implements DM access control with three modes:
## - Open: anyone can DM
## - Pairing: users must complete pairing flow first
## - Allowlist: only whitelisted users can DM
##
## Pairing flow:
## 1. User sends /pair to get a 6-digit code
## 2. Admin approves and shares code with user
## 3. User sends /pair <code> to complete pairing
## 4. User is added to allowlist

import std/[strutils, times, random]
import ../../core/types

type
  DmPolicy* = enum
    DmPolicyOpen      ## Anyone can DM
    DmPolicyPairing   ## Users must complete pairing flow
    DmPolicyAllowlist ## Only whitelisted users can DM

  DmSecurityState* = object
    policy*:    DmPolicy
    allowlist*: seq[UserId]  ## Empty = all allowed (legacy compat)

  PairingState* = object
    code*:      string         ## 6-digit numeric code
    createdAt*: float          ## Unix timestamp
    attempts*:  int            ## Failed attempt count
    expiresAt*: float          ## Unix timestamp when expires

const
  PairingCodeLength* = 6
  PairingExpirySeconds* = 300.0  ## 5 minutes
  MaxPairingAttempts* = 3

func isAllowedDm*(state: DmSecurityState; userId: UserId): bool =
  ## Returns true if the user is allowed to DM based on policy.
  case state.policy
  of DmPolicyOpen:
    true
  of DmPolicyAllowlist:
    if state.allowlist.len == 0:
      true
    else:
      state.allowlist.contains(userId)
  of DmPolicyPairing:
    state.allowlist.contains(userId)

func addToAllowlist*(state: var DmSecurityState; userId: UserId) =
  ## Adds a user to the allowlist if not already present.
  if not state.allowlist.contains(userId):
    state.allowlist.add(userId)

func removeFromAllowlist*(state: var DmSecurityState; userId: UserId) =
  ## Removes a user from the allowlist.
  let idx = state.allowlist.find(userId)
  if idx >= 0:
    state.allowlist.delete(idx)

proc isValidByAttemptsAndExpiry*(attempts: int; expiresAt: float): bool =
  let now = epochTime()
  attempts < MaxPairingAttempts and now < expiresAt

proc newPairingState*(): PairingState =
  randomize()
  var code = ""
  for i in 0 ..< PairingCodeLength:
    code.add($(rand(9)))
  let now = epochTime()
  PairingState(
    code: code,
    createdAt: now,
    attempts: 0,
    expiresAt: now + PairingExpirySeconds,
  )

proc isValid*(pairing: PairingState): bool =
  isValidByAttemptsAndExpiry(pairing.attempts, pairing.expiresAt)

proc validatePairingCode*(pairing: PairingState; input: string): bool =
  if not isValidByAttemptsAndExpiry(pairing.attempts, pairing.expiresAt):
    return false
  pairing.code == input.strip()

proc recordFailedAttempt*(pairing: var PairingState) =
  inc pairing.attempts

func `$`*(policy: DmPolicy): string =
  case policy
  of DmPolicyOpen: "open"
  of DmPolicyPairing: "pairing"
  of DmPolicyAllowlist: "allowlist"
