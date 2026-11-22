## The HTTP gateway's socket side: binds, accepts, and hands each client to
## `app/http_gateway.serveGatewayConnection` as a `GatewayConnection` over a
## Chronos stream. Runs on the loop of the thread that starts it (the daemon's
## main loop); every read is bounded by the request deadline.

import std/strutils
import chronos
import chronos/transports/stream
import ../../core/pipeops
import ../../core/log
import ../../ports/gateway_connection
import ../../domain/gateway/identity_pure
import ../../app/chat_bridge
import ../../app/http_gateway

export http_gateway

type
  GatewayServer* = ref object
    ## A running gateway; `stopHttpGateway` closes it.
    server: StreamServer
    port*:  int

proc remaining(deadline: Moment): chronos.Duration =
  let left = deadline - Moment.now()
  if left > chronos.ZeroDuration: left else: chronos.ZeroDuration

proc streamConnection*(transport: StreamTransport): GatewayConnection =
  ## The port over one accepted stream. A read that misses the deadline is
  ## cancelled, so it cannot keep filling a buffer after the handler moved on.
  GatewayConnection(
    readLine: proc(limit: int; deadline: Moment):
                   Future[Result[string, string]] {.async: (raises: []).} =
      let reading = transport.readLine(limit = limit, sep = "\n")
      try:
        if not await reading.withTimeout(deadline.remaining):
          await reading.cancelAndWait()
          return err("request deadline exceeded")
        return ok(reading.read())
      except CancelledError:
        return err("request cancelled")
      except CatchableError as e:
        return err("connection closed or read failed: " & e.msg),
    readSome: proc(maxBytes: int; deadline: Moment): Future[string]
                  {.async: (raises: []).} =
      if maxBytes <= 0 or Moment.now() >= deadline:
        return ""
      var buf = newString(maxBytes)
      let reading = transport.readOnce(addr buf[0], maxBytes)
      try:
        if not await reading.withTimeout(deadline.remaining):
          await reading.cancelAndWait()
          return ""
        let n = reading.read()
        if n <= 0:
          return ""
        buf.setLen(n)
        return buf
      except CatchableError:
        return "",
    write: proc(data: string): Future[bool] {.async: (raises: []).} =
      try:
        discard await transport.write(data)
        return true
      except CancelledError:
        return false
      except CatchableError:
        return false,
    atEof: proc(): bool {.gcsafe, raises: [].} = transport.atEof)

proc gatewayBindAddress*(bindAddr: string; port: int):
    Result[TransportAddress, string] =
  ## The address to listen on. A literal IP (`127.0.0.1`, `::1`, `[::1]`) is
  ## used as it is; a host name such as `localhost` is resolved over IPv4,
  ## as the previous `std/net` socket did for any address without a colon.
  let host =
    if bindAddr.startsWith("[") and bindAddr.endsWith("]"): bindAddr[1 .. ^2]
    else: bindAddr
  try:
    return ok(initTAddress(host, Port(port)))
  except CatchableError:
    discard
  try:
    let resolved = resolveTAddress(host, Port(port), Domain.AF_INET)
    if resolved.len > 0:
      return ok(resolved[0])
    err("cannot resolve " & host)
  except CatchableError as e:
    err("cannot resolve " & host & ": " & e.msg)

proc startHttpGateway*(port: int;
                       statusFn: GatewayStatusFn;
                       logFn:    GatewayLogFn;
                       eventFn:  GatewayEventFn = nil;
                       inboundFn: GatewayInboundFn = nil;
                       sessionsFn: GatewaySessionsFn = nil;
                       providersFn: GatewayProvidersFn = nil;
                       sessionActionFn: GatewaySessionActionFn = nil;
                       bindAddr = "127.0.0.1";
                       authToken = "";
                       agentDispatchFn: GatewayAgentDispatchFn = nil;
                       authorizeFn: AuthorizeFn = nil;
                       chatBridge: ChatBridge = nil;
                       modelName = "";
                       agentTimeoutMs = 0;
                       log:       Logger = newLogger("http_gateway")
                      ): Result[GatewayServer, string] =
  ## Binds and starts the gateway on the calling thread's Chronos loop; the
  ## connections are served while that loop runs (the daemon's main loop).
  let ctx = ?newGatewayContext(
    statusFn, logFn, eventFn, inboundFn, sessionsFn, providersFn,
    sessionActionFn, authToken, agentDispatchFn, authorizeFn, chatBridge,
    modelName, agentTimeoutMs, log)

  proc onConnection(server: StreamServer; client: StreamTransport)
      {.async: (raises: []).} =
    try:
      await serveGatewayConnection(ctx, streamConnection(client))
    finally:
      await client.closeWait()

  let address = gatewayBindAddress(bindAddr, port).valueOr:
    let msg = "http_gateway: bind " & bindAddr & ":" & $port & " failed — " & error
    log.error(msg)
    return err(msg)
  try:
    let server = createStreamServer(address, onConnection, {ServerFlags.ReuseAddr})
    server.start()
    ok(GatewayServer(server: server, port: port))
  except CatchableError as e:
    let msg = "http_gateway: bind " & bindAddr & ":" & $port & " failed — " & e.msg
    log.error(msg)
    err(msg)

proc stopHttpGateway*(gateway: GatewayServer): Future[void] {.async: (raises: []).} =
  ## Stops accepting and closes the listening socket. Connections already
  ## being served finish on their own.
  if gateway == nil or gateway.server == nil:
    return
  try:
    gateway.server.stop()
  except CatchableError:
    discard
  await gateway.server.closeWait()
