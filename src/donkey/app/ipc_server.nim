## IPC server — Chronos async Unix socket for daemon status queries.
##
## Socket path: $DONKEY_HOME/{SockFileName}
##
## Protocol (newline-terminated JSON, one request/response per connection):
##   {"cmd":"status"}       → {"ok":true,"data":{DaemonStatus}}
##   {"cmd":"logs","n":50}  → {"ok":true,"data":[IpcLogEntry,...]}
##
## startIpcServer is called once from startDaemon. The connection handler
## closes over the two providers: the server runs on the Chronos event loop
## of the calling thread, so no global state and no cross-thread access.

import std/json
import chronos
import chronos/transports/stream
import ../ports/ipc
import ../ports/fs

type
  StatusProvider* = proc(): DaemonStatus {.gcsafe, raises: [].}
  LogProvider*    = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].}

proc handleConn(statusFn: StatusProvider; logFn: LogProvider;
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
      resp = %*{"ok": true, "data": statusFn().toJson()}
    of "logs":
      let n = req{"n"}.getInt(50)
      var arr = newJArray()
      for e in logFn(n): arr.add(e.toJson())
      resp = %*{"ok": true, "data": arr}
    else:
      resp = %*{"ok": false, "error": "unknown command: " & cmd}
    discard await transport.write($resp & "\n")
  except CatchableError:
    discard
  transport.close()

proc startIpcServer*(fs:        FsRuntimePort;
                     sockPath:  string;
                     statusFn:  StatusProvider;
                     logFn:     LogProvider) {.gcsafe.} =
  ## Sets up the Unix socket server synchronously. The accept loop runs
  ## inside the Chronos event loop automatically after server.start().
  proc onConnection(server: StreamServer;
                    transport: StreamTransport) {.async: (raises: []).} =
    await handleConn(statusFn, logFn, transport)

  ## Remove stale socket from a previous run.
  ## A socket counts as a file for the port; a failure surfaces as the bind's.
  if fs.entryKind(sockPath) == fekFile:
    discard fs.remove(sockPath, false)

  let server = createStreamServer(initTAddress(sockPath), onConnection)
  server.start()
