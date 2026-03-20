## IPC server — Chronos async Unix socket for daemon status queries.
##
## Socket path: $DONKEY_HOME/{SockFileName}
##
## Protocol (newline-terminated JSON, one request/response per connection):
##   {"cmd":"status"}       → {"ok":true,"data":{DaemonStatus}}
##   {"cmd":"logs","n":50}  → {"ok":true,"data":[IpcLogEntry,...]}
##
## runIpcServer is called once from startDaemon. gStatusFn and gLogFn must
## be set before calling; they are read on every incoming connection.

import std/[json, os]
import chronos
import chronos/transports/stream
import ../adapters/ipc/types

type
  StatusProvider* = proc(): DaemonStatus {.gcsafe, raises: [].}
  LogProvider*    = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].}

## Module-level state avoids GC-safety issues with callback closures.
var gStatusFn: StatusProvider
var gLogFn:    LogProvider

proc callStatus(): DaemonStatus {.gcsafe, raises: [].} =
  {.cast(gcsafe).}: result = gStatusFn()

proc callLogs(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].} =
  {.cast(gcsafe).}: result = gLogFn(n)

proc handleConn(server: StreamServer;
                transport: StreamTransport) {.async: (raises: []).} =
  try:
    let line = await transport.readLine(sep = "\n")
    if line.len == 0:
      transport.close()
      return
    let req = parseJson(line)
    let cmd = req{"cmd"}.getStr()
    var resp: JsonNode
    case cmd
    of "status":
      resp = %*{"ok": true, "data": callStatus().toJson()}
    of "logs":
      let n = req{"n"}.getInt(50)
      var arr = newJArray()
      for e in callLogs(n): arr.add(e.toJson())
      resp = %*{"ok": true, "data": arr}
    else:
      resp = %*{"ok": false, "error": "unknown command: " & cmd}
    discard await transport.write($resp & "\n")
  except Exception:
    discard
  transport.close()

proc startIpcServer*(sockPath:  string;
                     statusFn:  StatusProvider;
                     logFn:     LogProvider) =
  ## Sets up the Unix socket server synchronously. The accept loop runs
  ## inside the Chronos event loop automatically after server.start().
  gStatusFn = statusFn
  gLogFn    = logFn

  ## Remove stale socket from a previous run.
  if fileExists(sockPath):
    removeFile(sockPath)

  let server = createStreamServer(initTAddress(sockPath), handleConn)
  server.start()
