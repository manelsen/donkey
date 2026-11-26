## tui_handler.nim — TUI startup handler.
##
## Thin wrapper around runTui; extracted so the entrypoint delegates cleanly
## instead of containing the call inline.

import ../config/environment
import ../config/types
import ../tui/dashboard

proc dispatchTui*(sockPath: string; env: Environment; cfg: DonkeyConfig): int =
  ## Opens the live TUI dashboard. Blocks until the user exits.
  ## Returns 0 on normal exit.
  runTui(sockPath, env, cfg)
  0
