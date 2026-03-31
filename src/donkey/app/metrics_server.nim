## metrics_server — Prometheus-style HTTP metrics exporter (Chronos based).

import std/[tables, strformat]
import chronos, chronos/apps/http/httpserver
import ../core/log

type
  MetricsRegistry* = object
    latencies*: Table[string, seq[float]] # provider -> latencies
    errors*:    Table[string, int]        # provider -> count

var gMetrics*: MetricsRegistry
var gMetricsLock*: AsyncLock

proc initMetricsServer*() =
  gMetrics.latencies = initTable[string, seq[float]]()
  gMetrics.errors = initTable[string, int]()
  gMetricsLock = newAsyncLock()

proc recordLatency*(provider: string, ms: float) {.async.} =
  await gMetricsLock.acquire()
  try:
    if not gMetrics.latencies.hasKey(provider):
      gMetrics.latencies[provider] = @[]
    gMetrics.latencies[provider].add(ms)
  finally:
    gMetricsLock.release()

proc recordError*(provider: string) {.async.} =
  await gMetricsLock.acquire()
  try:
    gMetrics.errors[provider] = gMetrics.errors.getOrDefault(provider) + 1
  finally:
    gMetricsLock.release()

proc renderMetrics*(): string =
  var res = "# HELP donkey_provider_latency_ms Provider completion latency in milliseconds\n"
  res.add("# TYPE donkey_provider_latency_ms gauge\n")
  for prov, vals in gMetrics.latencies:
    if vals.len > 0:
      let avg = block:
        var s = 0.0
        for v in vals: s += v
        s / vals.len.float
      res.add(&"donkey_provider_latency_avg_ms{{provider=\"{prov}\"}} {avg}\n")
      res.add(&"donkey_provider_latency_count{{provider=\"{prov}\"}} {vals.len}\n")

  res.add("# HELP donkey_provider_errors_total Total error count per provider\n")
  res.add("# TYPE donkey_provider_errors_total counter\n")
  for prov, count in gMetrics.errors:
    res.add(&"donkey_provider_errors_total{{provider=\"{prov}\"}} {count}\n")
  res

proc startMetricsServer*(address: string, port: int) {.async.} =
  proc handler(req: RequestContext): Future[HttpResponseRef] {.async.} =
    if req.request.uri.path == "/metrics":
      return await req.respond(Http200, renderMetrics(), 
                               [("Content-Type", "text/plain; version=0.0.4")])
    else:
      return await req.respond(Http404, "Not Found")

  let server = HttpServerRef.new(initTAddress(address, port), handler).valueOr:
    return

  server.start()
  await server.join()
