## metrics — structured counters for operational failures (US-012).
##
## Lightweight, thread-safe, gcsafe. No chronos dependency.
## The HTTP server wrapper lives in metrics_server.nim.

import std/[locks, tables, strformat]

type
  MetricsRegistry* = object
    latencies*:          Table[string, seq[float]] # provider -> latencies
    errors*:             Table[string, int]        # provider -> count
    outboundFailures*:   Table[string, int]        # channel -> count
    webhookFailures*:    Table[string, int]        # server type -> count
    reminderFailures*:   Table[string, int]        # reason -> count

var gMetrics*: MetricsRegistry
var gMetricsLock*: Lock
var gMetricsReady: bool = false

proc initMetrics*() {.gcsafe, raises: [].} =
  ## Initializes the metrics registry. Call once at startup.
  {.cast(gcsafe).}:
    initLock(gMetricsLock)
    gMetrics.latencies = initTable[string, seq[float]]()
    gMetrics.errors = initTable[string, int]()
    gMetrics.outboundFailures = initTable[string, int]()
    gMetrics.webhookFailures = initTable[string, int]()
    gMetrics.reminderFailures = initTable[string, int]()
    gMetricsReady = true

# ── Provider metrics (called from async context) ─────────────────────────────

proc recordLatency*(provider: string; ms: float) {.gcsafe.} =
  {.cast(gcsafe).}:
    if not gMetricsReady: return
    acquire(gMetricsLock)
    try:
      if not gMetrics.latencies.hasKey(provider):
        gMetrics.latencies[provider] = @[]
      gMetrics.latencies[provider].add(ms)
    finally:
      release(gMetricsLock)

proc recordError*(provider: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    if not gMetricsReady: return
    acquire(gMetricsLock)
    try:
      gMetrics.errors[provider] = gMetrics.errors.getOrDefault(provider) + 1
    finally:
      release(gMetricsLock)

# ── Operational failure counters (US-012) ────────────────────────────────────
#    Thread-safe, gcsafe — callable from webhook threads and .cast(gcsafe) blocks.

proc recordOutboundFailure*(channel, reason: string) {.gcsafe, raises: [].} =
  ## Records an outbound send failure for metrics/observability.
  ## Key: channel (e.g. "qq", "tg", "fs", "wc").
  {.cast(gcsafe).}:
    if not gMetricsReady: return
    acquire(gMetricsLock)
    try:
      gMetrics.outboundFailures[channel] = gMetrics.outboundFailures.getOrDefault(channel) + 1
    finally:
      release(gMetricsLock)

proc recordWebhookFailure*(serverType, reason: string) {.gcsafe, raises: [].} =
  ## Records a webhook processing failure for metrics/observability.
  ## Key: server type (e.g. "wechat", "qq", "wecom").
  {.cast(gcsafe).}:
    if not gMetricsReady: return
    acquire(gMetricsLock)
    try:
      gMetrics.webhookFailures[serverType] = gMetrics.webhookFailures.getOrDefault(serverType) + 1
    finally:
      release(gMetricsLock)

proc recordReminderFailure*(reason: string) {.gcsafe, raises: [].} =
  ## Records a reminder delivery failure for metrics/observability.
  ## Key: reason string (e.g. "delivery timeout").
  {.cast(gcsafe).}:
    if not gMetricsReady: return
    acquire(gMetricsLock)
    try:
      gMetrics.reminderFailures[reason] = gMetrics.reminderFailures.getOrDefault(reason) + 1
    finally:
      release(gMetricsLock)

# ── Rendering ─────────────────────────────────────────────────────────────────

proc renderMetrics*(): string =
  ## Renders metrics in Prometheus exposition format.
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

  # US-012: operational failure counters
  res.add("# HELP donkey_outbound_failures_total Outbound send failures by channel\n")
  res.add("# TYPE donkey_outbound_failures_total counter\n")
  for ch, count in gMetrics.outboundFailures:
    res.add(&"donkey_outbound_failures_total{{channel=\"{ch}\"}} {count}\n")

  res.add("# HELP donkey_webhook_failures_total Webhook processing failures by server type\n")
  res.add("# TYPE donkey_webhook_failures_total counter\n")
  for srv, count in gMetrics.webhookFailures:
    res.add(&"donkey_webhook_failures_total{{server=\"{srv}\"}} {count}\n")

  res.add("# HELP donkey_reminder_failures_total Reminder delivery failures by reason\n")
  res.add("# TYPE donkey_reminder_failures_total counter\n")
  for rsn, count in gMetrics.reminderFailures:
    res.add(&"donkey_reminder_failures_total{{reason=\"{rsn}\"}} {count}\n")

  res
