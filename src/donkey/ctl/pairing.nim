## ctl/pairing.nim — `donkey ctl pair` handlers.

import std/[os, strutils, times]
import ../core/types
import ../core/pipeops
import ../config/types
import ../adapters/memory/md_file
import ../adapters/identity/identity_resolver
import ../adapters/state/pairing_store

# ── ctl pairing commands ───────────────────────────────────────────────────────

proc ctlPairList*(store: PairingStore): Result[void, string] =
  let loaded = store.load()
  if loaded.isErr:
    return err(loaded.error)
  let requests = loaded.get()
  if requests.len == 0:
    echo "No pending pairing requests."
    return ok()
  echo "code\tchannel\trawId\texpires_in"
  for request in requests:
    let remaining = int(max(0.0, request.expiresAt - epochTime()))
    echo request.code & "\t" & $request.channel & "\t" &
         request.rawId & "\t" & $remaining & "s"
  ok()

proc ctlPairApprove*(cfg: DonkeyConfig; memory: MdFileAdapter;
                     store: PairingStore; code: string): Result[void, string] =
  var requests = ? store.load()
  let idx = findIndexByCode(requests, code.strip)
  if idx < 0:
    return err("pairing request not found or expired: " & code)
  let request = requests[idx]
  let resolver = newIdentityResolver(cfg.home / "identities.tsv")
  let userId = resolver.resolve(request.channel, request.rawId)
  ? memory.addDmAllowed(userId)
  requests.delete(idx)
  let saved = store.save(requests)
  if saved.isErr:
    echo "Access granted to " & $request.channel & " " & request.rawId &
         " -> " & $userId & ", but removing the pending request failed: " &
         saved.error & ". Run `donkey ctl pair reject " & request.code &
         "` to clean it up."
    return err("access granted; pending request cleanup failed")
  echo "Paired " & $request.channel & " " & request.rawId & " -> " & $userId
  ok()

proc ctlPairReject*(store: PairingStore; code: string): Result[void, string] =
  let removed = ? store.removeByCode(code.strip)
  if not removed:
    return err("pairing request not found or expired: " & code)
  echo "Pairing request " & code & " rejected."
  ok()
