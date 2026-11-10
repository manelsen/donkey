## metrics_server — Prometheus-style HTTP metrics exporter.
##
## Runs in its own OS thread so provider/email blocking calls in the daemon
## cannot delay scrapes. The handler only reads the gcsafe metrics registry.

import std/[net, os, strutils, times]
import std/posix
import ../core/pipeops
import ../core/log
import ./metrics

export metrics  # re-export initMetrics*, record*, renderMetrics*, gMetrics

const
  MetricsMaxRequestLine = 8192
  MetricsClientTimeoutSec = 10
  MetricsMaxHeaderLines = 100
  MetricsConnectionDeadlineSec = 5
  MetricsWorkerCount = 4
  MetricsQueueDepth = 64

type MetricsServerArgs = object
  host: string
  port: int
  log:  Logger

type MetricsWorkerArg = object
  id: int
  log: Logger

var
  gMetricsThread {.global.}: Thread[MetricsServerArgs]
  gMetricsWorkers {.global.}: array[MetricsWorkerCount, Thread[MetricsWorkerArg]]
  gMetricsQueue {.global.}: Channel[SocketHandle]
  gMetricsThreadStarted = false
  gMetricsPoolStarted = false

proc applyMetricsClientTimeouts(sock: Socket; seconds: int = MetricsClientTimeoutSec) =
  var tv: Timeval
  tv.tv_sec = posix.Time(seconds)
  tv.tv_usec = Suseconds(0)
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO, addr tv, SockLen(sizeof(tv)))
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO, addr tv, SockLen(sizeof(tv)))

proc sendMetricsResponse(sock: Socket; status, contentType, body: string) =
  let response = "HTTP/1.1 " & status & "\r\n" &
                 "Content-Type: " & contentType & "\r\n" &
                 "Content-Length: " & $body.len & "\r\n" &
                 "Connection: close\r\n\r\n" & body
  try: sock.send(response) except CatchableError: discard

proc handleMetricsClient(client: Socket; log: Logger) =
  let deadline = times.now() + initDuration(seconds = MetricsConnectionDeadlineSec)
  var requestLine = ""
  try:
    requestLine = client.recvLine()
    if requestLine.len > MetricsMaxRequestLine:
      requestLine = requestLine[0 ..< MetricsMaxRequestLine]
    var headerLines = 0
    while headerLines < MetricsMaxHeaderLines and times.now() <= deadline:
      let line = client.recvLine()
      if line.strip.len == 0:
        break
      inc headerLines
  except CatchableError:
    discard

  let parts = requestLine.splitWhitespace()
  let path =
    if parts.len >= 2:
      let raw = parts[1]
      let qmark = raw.find('?')
      if qmark >= 0: raw[0 ..< qmark] else: raw
    else:
      ""
  if path == "/metrics":
    let body = renderMetrics()
    if body.len == 0:
      log.warn("metrics: /metrics requested before initMetrics()")
      sendMetricsResponse(client, "503 Service Unavailable", "text/plain", "metrics not initialized")
    else:
      sendMetricsResponse(client, "200 OK", "text/plain; version=0.0.4", body)
  else:
    sendMetricsResponse(client, "404 Not Found", "text/plain", "Not Found")

proc metricsWorker(arg: MetricsWorkerArg) {.thread.} =
  while true:
    let fd = gMetricsQueue.recv()
    if fd == SocketHandle(-1):
      break
    let client = newSocket(fd, buffered = true)
    try:
      applyMetricsClientTimeouts(client)
      handleMetricsClient(client, arg.log)
    finally:
      client.close()

proc startMetricsPool(log: Logger) =
  if gMetricsPoolStarted:
    return
  gMetricsPoolStarted = true
  gMetricsQueue.open(MetricsQueueDepth)
  for i in 0 ..< MetricsWorkerCount:
    createThread(gMetricsWorkers[i], metricsWorker, MetricsWorkerArg(id: i, log: log))

proc metricsServerThread(args: MetricsServerArgs) {.thread.} =
  discard pthread_detach(pthread_self())
  var server: Socket
  try:
    server = newSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(Port(args.port), args.host)
    server.listen()
  except CatchableError as exc:
    args.log.error("metrics: failed to bind " & args.host & ":" & $args.port & " — " & exc.msg)
    if server != nil:
      server.close()
    return

  args.log.info("metrics: listening on " & args.host & ":" & $args.port & "/metrics")
  while true:
    var client: Socket
    try:
      server.accept(client)
    except CatchableError as exc:
      args.log.error("metrics: accept failed — " & exc.msg)
      continue
    let fd = client.getFd
    if not gMetricsQueue.trySend(fd):
      sendMetricsResponse(client, "503 Service Unavailable", "text/plain", "metrics busy")
      client.close()

func parseMetricsPort*(raw: string): Result[int, string] =
  ## Pure conversion; keeps the daemon free of exception-driven control flow.
  try:
    let port = parseInt(raw)
    if port <= 0 or port > 65535:
      err("porta fora do intervalo 1..65535")
    else:
      ok(port)
  except ValueError:
    err("porta não numérica")

proc validateMetricsBind*(address: string; port: int): Result[string, string] =
  ## Rejects clearly invalid host strings; the bind itself is authoritative.
  if address.strip.len == 0 or ' ' in address:
    err("invalid bind address")
  else:
    ok(address)

proc startMetricsServer*(host: string; port: int; log: Logger) =
  if gMetricsThreadStarted:
    return
  gMetricsThreadStarted = true
  startMetricsPool(log)
  createThread(gMetricsThread, metricsServerThread,
               MetricsServerArgs(host: host, port: port, log: log))

proc startOptionalMetricsServer*(log: Logger) =
  ## Starts the Prometheus exporter only when explicitly configured.
  ## Default bind is loopback: metrics can contain provider/channel names.
  let portRaw = getEnv("DONKEY_METRICS_PORT").strip()
  if portRaw.len == 0:
    return
  let port = parseMetricsPort(portRaw).valueOr:
    log.warn("metrics: DONKEY_METRICS_PORT inválido (" & portRaw & ") — " & error)
    return
  let bindRaw = getEnv("DONKEY_METRICS_BIND").strip()
  let bindAddr = if bindRaw.len > 0: bindRaw else: "127.0.0.1"
  let host = validateMetricsBind(bindAddr, port).valueOr:
    log.warn("metrics: DONKEY_METRICS_BIND inválido (" & bindAddr & ") — " & error)
    return
  startMetricsServer(host, port, log)
