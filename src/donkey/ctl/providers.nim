## ctl/providers.nim — `donkey ctl provider test` and `donkey ctl status`.

import std/os
import ../core/pipeops
import ../core/app_meta
import ../config/types
import ../domain/message
import ../ports/ipc
import ../ports/provider
import ../adapters/ipc/client as ipcClient

# ── ctl provider test ──────────────────────────────────────────────────────────

proc ctlProviderTest*(name: string;
                      buildCompleteFnRef: proc(preferencesMd: string): CompleteFn): Result[void, string] =
  let fn = buildCompleteFnRef("provider = \"" & name & "\"")
  var h = message.newHistory()
  h.addUser("ping")
  let req  = message.buildPrompt("Reply with one word: pong", h, "")
  let resp = fn(req)
  if resp.isOk:
    echo "OK — " & name & " responded: " & resp.value.text
    ok()
  else:
    echo "FAIL — " & name & ": " & resp.error
    err(resp.error)

# ── ctl memory commands ────────────────────────────────────────────────────────
## Delegated to multigraph_runtime (already has correct MAGMA-aware impls).

# ── ctl status ─────────────────────────────────────────────────────────────────

proc ctlStatus*(cfg: DonkeyConfig): Result[void, string] =
  let sockPath = cfg.home / SockFileName
  let sr = ipcClient.queryStatus(sockPath)
  if sr.isErr:
    return err(sr.error)
  let st = sr.value
  echo formatDaemonStatus(st)
  ok()
