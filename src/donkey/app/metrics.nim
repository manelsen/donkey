## metrics — structured counters for operational failures (US-012).
##
## Lightweight, thread-safe, gcsafe. No chronos dependency.
## The HTTP server wrapper lives in metrics_server.nim.

import std/[locks, strformat]
import ../infra/fixed
export fixed  ## callers read the counters (len, hasKey, [])

const
  MetricKeys = 64      ## keys per counter; the rest is counted under "_other"
  MetricKeyBytes = 64  ## provider, channel, server or reason name

type
  Counter = FixedTable[MetricKeys, MetricKeyBytes, int]

  MetricsRegistry* = object
    ## Plain values (no GC memory): any thread records under gMetricsLock
    ## with no cast.
    latencyCounts*:      Counter                                           # provider -> number of samples
    latencySums*:        FixedTable[MetricKeys, MetricKeyBytes, float]     # provider -> sum of samples
    errors*:             Counter        # provider -> count
    outboundFailures*:   Counter        # channel -> count
    webhookFailures*:    Counter        # server type -> count
    reminderFailures*:   Counter        # reason -> count

var gMetrics: MetricsRegistry
var gMetricsLock: Lock
var gMetricsReady: bool = false
initLock(gMetricsLock)  ## module init: before any thread can record

template withMetrics(body: untyped) =
  ## The one way to touch the registry, from any thread.
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
    gMetrics = MetricsRegistry()
    gMetricsReady = true

# ── Provider metrics (called from async context) ─────────────────────────────

proc recordLatency*(provider: string; ms: float) {.gcsafe.} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.latencyCounts.inc(provider, 1)
    gMetrics.latencySums.inc(provider, ms)

proc recordError*(provider: string) {.gcsafe.} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.errors.inc(provider, 1)

# ── Operational failure counters (US-012) ────────────────────────────────────
#    Thread-safe, gcsafe — callable from any thread.

proc recordOutboundFailure*(channel, reason: string) {.gcsafe, raises: [].} =
  ## Records an outbound send failure for metrics/observability.
  ## Key: channel (e.g. "qq", "tg", "fs", "wc").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.outboundFailures.inc(channel, 1)

proc recordWebhookFailure*(serverType, reason: string) {.gcsafe, raises: [].} =
  ## Records a webhook processing failure for metrics/observability.
  ## Key: server type (e.g. "wechat", "qq", "wecom").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.webhookFailures.inc(serverType, 1)

proc webhookFailureCount*(serverType: string): int {.gcsafe, raises: [].} =
  ## Current failure count for one webhook server type (0 if never seen).
  withMetrics:
    if not gMetricsReady: return 0
    result = gMetrics.webhookFailures.get(serverType)

proc recordReminderFailure*(reason: string) {.gcsafe, raises: [].} =
  ## Records a reminder delivery failure for metrics/observability.
  ## Key: reason string (e.g. "delivery timeout").
  withMetrics:
    if not gMetricsReady: return
    gMetrics.reminderFailures.inc(reason, 1)

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
        let total = gMetrics.latencySums.get(prov)
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

