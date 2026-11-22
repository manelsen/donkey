## metrics — structured counters for operational failures (US-012).
##
## Lightweight, thread-safe, gcsafe. No chronos dependency.
## The HTTP server wrapper lives in metrics_server.nim.

import std/[locks, tables, strformat]

type
  MetricsRegistry* = object
    latencyCounts*:      Table[string, int]        # provider -> number of samples
    latencySums*:        Table[string, float]      # provider -> sum of samples
    errors*:             Table[string, int]        # provider -> count
    outboundFailures*:   Table[string, int]        # channel -> count
    webhookFailures*:    Table[string, int]        # server type -> count
    reminderFailures*:   Table[string, int]        # reason -> count

var gMetrics: MetricsRegistry
var gMetricsLock: Lock
var gMetricsReady: bool = false
initLock(gMetricsLock)  ## module init: before any thread can record

template withMetrics(body: untyped) =
  ## The one way to touch the registry, from any thread.
  ## gcsafe: gMetrics and gMetricsReady are only read or written here, under gMetricsLock; keys and counts are copied in and out
  {.cast(gcsafe).}:
    acquire(gMetricsLock)
    try:
      body
    finally:
      release(gMetricsLock)

proc metricsSnapshot*(): MetricsRegistry {.gcsafe, raises: [].} =
  ## A copy of the registry, taken under the lock.
  withMetrics:
    result = gMetrics

proc initMetrics*() {.gcsafe, raises: [].} =
  ## Initializes (or resets) the metrics registry.
  withMetrics:
    gMetrics.latencyCounts = initTable[string, int]()
    gMetrics.latencySums = initTable[string, float]()
    gMetrics.errors = initTable[string, int]()
    gMetrics.outboundFailures = initTable[string, int]()
    gMetrics.webhookFailures = initTable[string, int]()
    gMetrics.reminderFailures = initTable[string, int]()
    gMetricsReady = true

# ── Provider metrics (called from async context) ─────────────────────────────

proc recordLatency*(provider: string; ms: float) {.gcsafe.} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.latencyCounts[provider] =
      gMetrics.latencyCounts.getOrDefault(provider) + 1
    gMetrics.latencySums[provider] =
      gMetrics.latencySums.getOrDefault(provider) + ms

proc recordError*(provider: string) {.gcsafe.} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.errors[provider] = gMetrics.errors.getOrDefault(provider) + 1

# ── Operational failure counters (US-012) ────────────────────────────────────
#    Thread-safe, gcsafe — callable from any thread.

proc recordOutboundFailure*(channel, reason: string) {.gcsafe, raises: [].} =
  ## Records an outbound send failure for metrics/observability.
  ## Key: channel (e.g. "qq", "tg", "fs", "wc").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.outboundFailures[channel] = gMetrics.outboundFailures.getOrDefault(channel) + 1

proc recordWebhookFailure*(serverType, reason: string) {.gcsafe, raises: [].} =
  ## Records a webhook processing failure for metrics/observability.
  ## Key: server type (e.g. "wechat", "qq", "wecom").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.webhookFailures[serverType] = gMetrics.webhookFailures.getOrDefault(serverType) + 1

proc webhookFailureCount*(serverType: string): int {.gcsafe, raises: [].} =
  ## Current failure count for one webhook server type (0 if never seen).
  withMetrics:
    if not gMetricsReady: return 0
    result = gMetrics.webhookFailures.getOrDefault(serverType)

proc recordReminderFailure*(reason: string) {.gcsafe, raises: [].} =
  ## Records a reminder delivery failure for metrics/observability.
  ## Key: reason string (e.g. "delivery timeout").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.reminderFailures[reason] = gMetrics.reminderFailures.getOrDefault(reason) + 1

# ── Rendering ─────────────────────────────────────────────────────────────────

func escapeLabel(value: string): string =
  ## Escapes a Prometheus label value (backslash, quote, newline).
  for c in value:
    case c
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    else: result.add(c)

proc renderMetrics*(): string {.gcsafe.} =
  ## Renders metrics in Prometheus exposition format.
  withMetrics:
    if not gMetricsReady:
      return ""
    var res = "# HELP donkey_provider_latency_ms_sum Sum of provider completion latency samples in milliseconds\n"
    res.add("# TYPE donkey_provider_latency_ms_sum counter\n")
    res.add("# HELP donkey_provider_latency_ms_count Number of provider latency samples\n")
    res.add("# TYPE donkey_provider_latency_ms_count counter\n")
    for prov, count in gMetrics.latencyCounts:
      if count > 0:
        let total = gMetrics.latencySums.getOrDefault(prov)
        res.add(&"donkey_provider_latency_ms_sum{{provider=\"{escapeLabel(prov)}\"}} {total}\n")
        res.add(&"donkey_provider_latency_ms_count{{provider=\"{escapeLabel(prov)}\"}} {count}\n")

    res.add("# HELP donkey_provider_errors_total Total error count per provider\n")
    res.add("# TYPE donkey_provider_errors_total counter\n")
    for prov, count in gMetrics.errors:
      res.add(&"donkey_provider_errors_total{{provider=\"{escapeLabel(prov)}\"}} {count}\n")

    # US-012: operational failure counters
    res.add("# HELP donkey_outbound_failures_total Outbound send failures by channel\n")
    res.add("# TYPE donkey_outbound_failures_total counter\n")
    for ch, count in gMetrics.outboundFailures:
      res.add(&"donkey_outbound_failures_total{{channel=\"{escapeLabel(ch)}\"}} {count}\n")

    res.add("# HELP donkey_webhook_failures_total Webhook processing failures by server type\n")
    res.add("# TYPE donkey_webhook_failures_total counter\n")
    for srv, count in gMetrics.webhookFailures:
      res.add(&"donkey_webhook_failures_total{{server=\"{escapeLabel(srv)}\"}} {count}\n")

    res.add("# HELP donkey_reminder_failures_total Reminder delivery failures by reason\n")
    res.add("# TYPE donkey_reminder_failures_total counter\n")
    for rsn, count in gMetrics.reminderFailures:
      res.add(&"donkey_reminder_failures_total{{reason=\"{escapeLabel(rsn)}\"}} {count}\n")

    result = res

