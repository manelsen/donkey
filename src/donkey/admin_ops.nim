## admin_ops — administration operations shared by `donkey ctl` and the
## admin TUI (PRD-roadmap E6). Each one returns what happened, or why not,
## and prints nothing: `ctl` echoes the result, the TUI shows it in place.
## The same function behind both is what makes a TUI action do exactly what
## its `ctl` command does.

import std/[os, strutils]
import core/pipeops
import core/types
import config/types
import adapters/memory/md_file
import adapters/memory/dm_allowlist
import adapters/identity/identity_resolver
import adapters/state/pairing_store
import domain/message

proc setUserAccess*(memory: MdFileAdapter; uuid: string;
                    revoked: bool): Result[string, string] =
  ## The DM allowlist first: a failure must not leave Access changed without
  ## the matching allowlist entry.
  let userId = UserId(uuid)
  ? (if revoked: dmAllowlistOf(memory.paddocksDir).disallow(userId)
     else: dmAllowlistOf(memory.paddocksDir).allow(userId))
  if memory.hasProfile(userId):
    ? memory.updateUserField(userId, "Access", if revoked: "revoked" else: "active")
  ok((if revoked: "Revoked " else: "Restored ") & uuid)

proc approvePairing*(cfg: DonkeyConfig; memory: MdFileAdapter;
                     store: PairingStore; code: string): Result[string, string] =
  var requests = ? store.load()
  let idx = findIndexByCode(requests, code.strip)
  if idx < 0:
    return err("pairing request not found or expired: " & code)
  let request = requests[idx]
  let resolver = newIdentityResolver(cfg.home / "identities.tsv")
  let userId = resolver.resolve(request.channel, request.rawId)
  ? dmAllowlistOf(memory.paddocksDir).allow(userId)
  requests.delete(idx)
  let saved = store.save(requests)
  if saved.isErr:
    return err("Access granted to " & $request.channel & " " & request.rawId &
               " -> " & $userId & ", but removing the pending request failed: " &
               saved.error & ". Reject " & request.code & " to clean it up.")
  ok("Paired " & $request.channel & " " & request.rawId & " -> " & $userId)

proc rejectPairing*(store: PairingStore; code: string): Result[string, string] =
  let removed = ? store.removeByCode(code.strip)
  if not removed:
    return err("pairing request not found or expired: " & code)
  ok("Pairing request " & code & " rejected.")
