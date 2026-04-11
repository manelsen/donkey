## tui_handler.nim — TUI startup handler.
##
## Thin wrapper around runTui; extracted so the entrypoint delegates cleanly
## instead of containing the call inline.

import std/os
import ../tui/dashboard

proc dispatchTui*(sockPath: string): int =
  ## Opens the live TUI dashboard. Blocks until the user exits.
  ## Returns 0 on normal exit.
  runTui(sockPath)
  0
