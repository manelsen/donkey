## IPC client for donkey ctl commands.
##
## Uses blocking std/net — safe for CLI tools (no event loop needed).
## All procs return Result[T, string] — errors are never raised.

import std/[json, net, os, strutils]
import ../../core/pipeops
import ./types

proc expandSockPath*(path: string): string =
  if path.startsWith("~/"):
    getHomeDir().strip(chars = {'/'}, leading = false) & "/" & path[2..^1]
  else:
    path

proc ipcQuery*(sockPath: string; payload: JsonNode): Result[JsonNode, string] =
  ## Connects, sends JSON request, reads JSON response.
  let path = expandSockPath(sockPath)
  if not fileExists(path):
    return err("daemon not running (socket not found: " & path & ")")
  try:
    let sock = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
    defer: sock.close()
    sock.connectUnix(path)
    sock.send($payload & "\n")
    let line = sock.recvLine(timeout = 3000)
    if line.len == 0:
      return err("empty response from daemon")
    ok(parseJson(line))
  except Exception as e:
    err(e.msg)

proc queryStatus*(sockPath: string): Result[DaemonStatus, string] =
  let r = ? ipcQuery(sockPath, %*{"cmd": "status"})
  if not r{"ok"}.getBool(false):
    return err(r{"error"}.getStr("unknown error from daemon"))
  ok(fromJsonStatus(r{"data"}))

proc queryLogs*(sockPath: string; n: int = 50): Result[seq[IpcLogEntry], string] =
  let r = ? ipcQuery(sockPath, %*{"cmd": "logs", "n": n})
  if not r{"ok"}.getBool(false):
    return err(r{"error"}.getStr("unknown error from daemon"))
  var lines: seq[IpcLogEntry]
  for e in r{"data"}: lines.add(fromJsonLogEntry(e))
  ok(lines)
