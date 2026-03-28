import std/unittest
import std/strutils
import donkey/core/types
import donkey/core/security/dm_policy

suite "DM Security":

  test "DmPolicy has correct variants":
    check DmPolicyOpen == DmPolicyOpen
    check DmPolicyPairing == DmPolicyPairing
    check DmPolicyAllowlist == DmPolicyAllowlist

  test "isAllowedDm returns true for Open policy":
    let state = DmSecurityState(policy: DmPolicyOpen)
    check isAllowedDm(state, UserId("user123"))

  test "isAllowedDm checks allowlist":
    let state = DmSecurityState(
      policy: DmPolicyAllowlist,
      allowlist: @[UserId("allowed1"), UserId("allowed2")]
    )
    check isAllowedDm(state, UserId("allowed1")) == true
    check isAllowedDm(state, UserId("allowed2")) == true
    check isAllowedDm(state, UserId("blocked1")) == false

  test "isAllowedDm returns true for empty allowlist (legacy compat)":
    let state = DmSecurityState(policy: DmPolicyAllowlist)
    check isAllowedDm(state, UserId("anyone")) == true

  test "addToAllowlist adds user":
    var state = DmSecurityState(
      policy: DmPolicyAllowlist,
      allowlist: @[]
    )
    addToAllowlist(state, UserId("newuser"))
    check state.allowlist.contains(UserId("newuser"))

  test "removeFromAllowlist removes user":
    var state = DmSecurityState(
      policy: DmPolicyAllowlist,
      allowlist: @[UserId("user1"), UserId("user2")]
    )
    removeFromAllowlist(state, UserId("user1"))
    check state.allowlist.len == 1
    check state.allowlist.contains(UserId("user2"))

  test "newPairingState generates code":
    let state = newPairingState()
    check state.code.len == 6
    check strutils.allCharsInSet(state.code, {'0'..'9'})
    check isValid(state) == true

  test "validatePairingCode returns true for correct code":
    let pairing = newPairingState()
    check validatePairingCode(pairing, pairing.code) == true

  test "validatePairingCode returns false for wrong code":
    let pairing = newPairingState()
    check validatePairingCode(pairing, "000000") == false

  test "pairing expires after max attempts":
    var pairing = newPairingState()
    pairing.attempts = MaxPairingAttempts
    check isValid(pairing) == false
