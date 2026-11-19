## ctl/sessions.nim — `donkey ctl session` handlers.

import ../core/types
import ../app/session_manager

# ── ctl session commands ───────────────────────────────────────────────────────

proc ctlSessionList*(sm: SessionManager; uuid: string) =
  ## Sessions are in-memory only; for an external CLI this shows nothing.
  let uid = UserId(uuid)
  var found = false
  for (userId, channels) in sm.listSessions():
    if userId == uid:
      found = true
      echo "Session for " & uuid & ":"
      for (kind, rawId) in channels:
        echo "  " & $kind & " : " & rawId
  if not found:
    echo "No active session for " & uuid
