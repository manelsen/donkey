## daemon_start_handler.nim — Daemon startup handler.
##
## Logs the daemon start banner. The actual startDaemon proc remains in the
## entrypoint (it depends on all the daemon types defined there); main() calls
## this handler first, then invokes startDaemon directly.

import ../core/log
import ../core/app_meta
import ../config/types

const Version* = AppVersion

proc logDaemonStart*(log: Logger; cfg: DonkeyConfig) =
  log.info(AppSlug & " " & Version & " starting")
  log.info("home: " & cfg.home)
