## metrics_server — Prometheus-style HTTP metrics exporter (Chronos based).
##
## Thin HTTP wrapper around the core metrics module.
## Delegates all recording to metrics.nim (gcsafe, thread-safe).

import chronos, chronos/apps/http/httpserver
import ./metrics

export metrics  # re-export initMetrics*, record*, renderMetrics*, gMetrics

proc startMetricsServer*(address: string, port: int) {.async.} =
  proc handler(req: HttpRequestRef): Future[HttpResponseRef] {.async.} =
    if req.requestUri.path == "/metrics":
      return await req.respond(Http200, renderMetrics(),
                               [("Content-Type", "text/plain; version=0.0.4")])
    else:
      return await req.respond(Http404, "Not Found")

  let server = HttpServerRef.new(initTAddress(address, port), handler).valueOr:
    return

  server.start()
  await server.join()
