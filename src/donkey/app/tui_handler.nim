## tui_handler.nim — TUI startup handler.
##
## Thin wrapper around runTui; extracted so the entrypoint delegates cleanly
## instead of containing the call inline.

import ../config/environment
import ../tui/dashboard

proc dispatchTui*(sockPath: string; env: Environment): int =
  ## Opens the live TUI dashboard. Blocks until the user exits.
  ## Returns 0 on normal exit.
  runTui(sockPath, env)
  0
