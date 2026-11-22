## The IPC server answers `status` and `logs` from the providers it was
## started with, over a real Unix socket.

import std/[json, os, strutils, unittest]
import chronos
import chronos/transports/stream
import donkey/app/ipc_server
import donkey/ports/ipc

proc request(sockPath, line: string): Future[string] {.async.} =
  let transport = await connect(initTAddress(sockPath))
  defer: await transport.closeWait()
  discard await transport.write(line & "\n")
  return await transport.readLine(sep = "\n")

proc runTests*() =
  suite "ipc server":
    test "status and logs come from the providers given at start":
      let sockPath = getTempDir() / ("donkey_ipc_" & $getCurrentProcessId() & ".sock")
      defer: removeFile(sockPath)
      let statusFn: StatusProvider = proc(): DaemonStatus {.gcsafe, raises: [].} =
        DaemonStatus(uptimeSec: 42, sessionCount: 3)
      let logFn: LogProvider = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].} =
        @[IpcLogEntry(level: "info", msg: "asked for " & $n)]
      startIpcServer(sockPath, statusFn, logFn)
      let status = parseJson(waitFor request(sockPath, """{"cmd":"status"}"""))
      check status["ok"].getBool
      check status["data"]["uptimeSec"].getInt == 42
      check status["data"]["sessionCount"].getInt == 3
      let logs = waitFor request(sockPath, """{"cmd":"logs","n":7}""")
      check "asked for 7" in logs
      let unknown = parseJson(waitFor request(sockPath, """{"cmd":"nope"}"""))
      check not unknown["ok"].getBool

when isMainModule:
  runTests()
