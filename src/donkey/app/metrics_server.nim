## metrics_server — Prometheus-style HTTP metrics exporter (Chronos based).
##
## Thin HTTP wrapper around the core metrics module.
## Delegates all recording to metrics.nim (gcsafe, thread-safe).

import std/[os, strutils]
import chronos, chronos/apps/http/httpserver
import ../core/pipeops
import ../core/log
import ./metrics

export metrics  # re-export initMetrics*, record*, renderMetrics*, gMetrics

proc startMetricsServer*(address: TransportAddress; label: string; port: int; log: Logger) {.async: (raises: []).} =
  proc handler(req: RequestFence): Future[HttpResponseRef] {.
      async: (raises: [CancelledError]).} =
    if req.isErr:
      return defaultResponse(req.error)
    let request = req.get()
    try:
      if request.uri.path == "/metrics":
        let body = renderMetrics()
        if body.len == 0:
          log.warn("metrics: /metrics requested before initMetrics()")
          return await request.respond(Http503, "metrics not initialized")
        var headers = HttpTable.init()
        headers.set("Content-Type", "text/plain; version=0.0.4")
        return await request.respond(Http200, body, headers)
      else:
        return await request.respond(Http404, "Not Found")
    except CancelledError as exc:
      raise exc
    except CatchableError as exc:
      log.warn("metrics: request failed — " & exc.msg)
      return defaultResponse()

  let server = HttpServerRef.new(address, handler).valueOr:
    log.error("metrics: failed to bind " & label & ":" & $port & " — " & error)
    return

  server.start()
  log.info("metrics: listening on " & label & ":" & $port & "/metrics")
  try:
    await server.join()
  except CancelledError:
    discard
  except CatchableError as exc:
    log.error("metrics: server stopped — " & exc.msg)

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

proc validateMetricsBind*(address: string; port: int): Result[TransportAddress, string] =
  ## Converts initTAddress's exception into a Result at the adapter boundary.
  try:
    ok(initTAddress(address, port))
  except TransportAddressError as exc:
    err(exc.msg)

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
  let address = validateMetricsBind(bindAddr, port).valueOr:
    log.warn("metrics: DONKEY_METRICS_BIND inválido (" & bindAddr & ") — " & error)
    return
  asyncSpawn startMetricsServer(address, bindAddr, port, log)
