## metrics — the daemon's counters, histograms and gauges, rendered in the
## Prometheus text format.
##
## What is measured: turns (per channel, kind and outcome, with duration),
## tool calls (per tool and outcome, with duration), provider latency
## (histogram), errors and tokens, inbound and delivered messages per channel,
## schedule runs and misses, active sessions, start time and build, and the
## operational failure counters (outbound, webhook, reminder).
##
## Lightweight, thread-safe, gcsafe. No chronos dependency. Every label set is
## a fixed table of at most 64 keys; the rest is counted under "_other", so a
## tool or provider name cannot grow memory. The HTTP server wrapper lives in
## metrics_server.nim.

import std/[locks, strformat, strutils]
import ../core/types
import ../infra/fixed
export fixed  ## callers read the counters (len, hasKey, [])

const
  MetricKeys = 64      ## keys per counter; the rest is counted under "_other"
  MetricKeyBytes = 64  ## provider, channel, server or reason name

  DurationBucketsMs* = [50.0, 100.0, 250.0, 500.0, 1_000.0, 2_500.0,
                        5_000.0, 10_000.0, 30_000.0, 60_000.0, 120_000.0,
                        300_000.0]
    ## Upper bounds of the duration histograms, in milliseconds; a sample
    ## above the last one is only in `+Inf`.
  KeySep = '\x1f'      ## joins two label values in one counter key

type
  Counter = FixedTable[MetricKeys, MetricKeyBytes, int]

  Histogram* = object
    buckets*: array[DurationBucketsMs.len, int]  ## per bucket, not cumulative
    sum*:     float
    count*:   int

  Histograms = FixedTable[MetricKeys, MetricKeyBytes, Histogram]

  MetricsRegistry* = object
    ## Plain values (no GC memory): any thread records under gMetricsLock
    ## with no cast.
    providerLatency*:    Histograms     # provider -> latency histogram
    errors*:             Counter        # provider -> count
    tokensIn*:           Counter        # provider -> input tokens
    tokensOut*:          Counter        # provider -> output tokens
    turnsOk*:            Counter        # channel␟kind -> turns that answered
    turnsError*:         Counter        # channel␟kind -> turns that failed
    turnDuration*:       Histograms     # channel -> turn duration
    toolOk*:             Counter        # tool -> calls that returned output
    toolError*:          Counter        # tool -> calls that returned an error
    toolDuration*:       Histograms     # tool -> call duration
    inbound*:            Counter        # channel -> messages received
    outboundSent*:       Counter        # channel -> messages delivered
    scheduleSent*:       int
    scheduleFailed*:     int
    scheduleMissed*:     int
    activeSessions*:     int
    startedAtMs*:        int64
    version*:            FixedText[MetricKeyBytes]
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

proc initMetrics*(startedAtMs = 0'i64; version = "") {.gcsafe, raises: [].} =
  ## Initializes (or resets) the metrics registry.
  withMetrics:
    gMetrics = MetricsRegistry(startedAtMs: startedAtMs,
                               version: toFixed[MetricKeyBytes](version))
    gMetricsReady = true

func channelLabel*(ch: ChannelKind): string =
  ## `telegram`, `discord`, `wecom`…: the label every channel metric uses.
  $ch

func observe*(h: var Histogram; value: float) =
  for i, bound in DurationBucketsMs:
    if value <= bound:
      inc h.buckets[i]
      break
  h.sum += value
  inc h.count

# ── Provider metrics (called from async context) ─────────────────────────────

proc recordLatency*(provider: string; ms: float) {.gcsafe.} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.providerLatency.mgetOrPut(provider).observe(ms)

proc recordTokens*(provider: string; input, output: int) {.gcsafe, raises: [].} =
  ## Tokens a provider reported for one completion; zeros are not recorded.
  withMetrics:
    if not gMetricsReady: return
    if input > 0: gMetrics.tokensIn.inc(provider, input)
    if output > 0: gMetrics.tokensOut.inc(provider, output)

# ── Turns, tools, traffic, schedules ─────────────────────────────────────────

proc recordTurn*(channel, kind: string; ms: float; ok: bool) {.gcsafe, raises: [].} =
  ## One agent turn: `kind` is user, schedule, heartbeat…; `ok` is false when
  ## the turn ended on a provider error instead of an answer.
  withMetrics:
    if not gMetricsReady: return
    let key = channel & KeySep & kind
    if ok: gMetrics.turnsOk.inc(key, 1) else: gMetrics.turnsError.inc(key, 1)
    gMetrics.turnDuration.mgetOrPut(channel).observe(ms)

proc recordToolCall*(tool: string; ms: float; ok: bool) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    if ok: gMetrics.toolOk.inc(tool, 1) else: gMetrics.toolError.inc(tool, 1)
    gMetrics.toolDuration.mgetOrPut(tool).observe(ms)

proc recordInbound*(channel: string) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.inbound.inc(channel, 1)

proc recordOutboundSent*(channel: string) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.outboundSent.inc(channel, 1)

proc recordScheduleRun*(sent: bool) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    if sent: inc gMetrics.scheduleSent else: inc gMetrics.scheduleFailed

proc recordScheduleMissed*(count: int) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    if count > 0: gMetrics.scheduleMissed += count

proc setActiveSessions*(count: int) {.gcsafe, raises: [].} =
  withMetrics:
    if not gMetricsReady: return
    gMetrics.activeSessions = count

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

proc family(res: var string; name, kind, help: string) =
  res.add("# HELP " & name & " " & help & "\n")
  res.add("# TYPE " & name & " " & kind & "\n")

func bucketLabel(bound: float): string =
  ## `50`, not `50.0`: the bounds are whole milliseconds.
  $int64(bound)

proc renderHistogram(res: var string; name, labels: string; h: Histogram) =
  var cumulative = 0
  for i, bound in DurationBucketsMs:
    cumulative += h.buckets[i]
    res.add(name & "_bucket{" & labels & ",le=\"" & bucketLabel(bound) & "\"} " &
            $cumulative & "\n")
  res.add(name & "_bucket{" & labels & ",le=\"+Inf\"} " & $h.count & "\n")
  res.add(name & "_sum{" & labels & "} " & $h.sum & "\n")
  res.add(name & "_count{" & labels & "} " & $h.count & "\n")

func splitKey(key: string): (string, string) =
  let at = key.find(KeySep)
  if at < 0: (key, "") else: (key[0 ..< at], key[at + 1 .. ^1])

proc renderMetrics*(): string {.gcsafe.} =
  ## Renders metrics in Prometheus exposition format.
  withMetrics:
    if not gMetricsReady:
      return ""
    var res = ""
    family(res, "donkey_provider_latency_ms", "histogram",
           "Provider completion latency in milliseconds")
    for prov, h in gMetrics.providerLatency:
      renderHistogram(res, "donkey_provider_latency_ms",
                      "provider=\"" & escapeLabel(prov) & "\"", h)

    family(res, "donkey_provider_errors_total", "counter",
           "Total error count per provider")
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

    family(res, "donkey_provider_tokens_total", "counter",
           "Tokens reported by the provider, per direction")
    for prov, n in gMetrics.tokensIn:
      res.add(&"donkey_provider_tokens_total{{provider=\"{escapeLabel(prov)}\",direction=\"input\"}} {n}\n")
    for prov, n in gMetrics.tokensOut:
      res.add(&"donkey_provider_tokens_total{{provider=\"{escapeLabel(prov)}\",direction=\"output\"}} {n}\n")

    family(res, "donkey_turns_total", "counter",
           "Agent turns per channel, kind and outcome")
    for (table, outcome) in [(gMetrics.turnsOk, "ok"), (gMetrics.turnsError, "error")]:
      for key, n in table:
        let (channel, kind) = splitKey(key)
        res.add(&"donkey_turns_total{{channel=\"{escapeLabel(channel)}\",kind=\"{escapeLabel(kind)}\",outcome=\"{outcome}\"}} {n}\n")
    family(res, "donkey_turn_duration_ms", "histogram",
           "Agent turn duration in milliseconds, per channel")
    for channel, h in gMetrics.turnDuration:
      renderHistogram(res, "donkey_turn_duration_ms",
                      "channel=\"" & escapeLabel(channel) & "\"", h)

    family(res, "donkey_tool_calls_total", "counter",
           "Tool calls per tool and outcome")
    for (table, outcome) in [(gMetrics.toolOk, "ok"), (gMetrics.toolError, "error")]:
      for tool, n in table:
        res.add(&"donkey_tool_calls_total{{tool=\"{escapeLabel(tool)}\",outcome=\"{outcome}\"}} {n}\n")
    family(res, "donkey_tool_duration_ms", "histogram",
           "Tool call duration in milliseconds, per tool")
    for tool, h in gMetrics.toolDuration:
      renderHistogram(res, "donkey_tool_duration_ms",
                      "tool=\"" & escapeLabel(tool) & "\"", h)

    family(res, "donkey_inbound_messages_total", "counter",
           "Messages received, per channel")
    for ch, n in gMetrics.inbound:
      res.add(&"donkey_inbound_messages_total{{channel=\"{escapeLabel(ch)}\"}} {n}\n")
    family(res, "donkey_outbound_messages_total", "counter",
           "Messages delivered, per channel")
    for ch, n in gMetrics.outboundSent:
      res.add(&"donkey_outbound_messages_total{{channel=\"{escapeLabel(ch)}\"}} {n}\n")

    family(res, "donkey_schedule_runs_total", "counter",
           "Scheduled job runs handed to a session, per outcome")
    res.add(&"donkey_schedule_runs_total{{outcome=\"sent\"}} {gMetrics.scheduleSent}\n")
    res.add(&"donkey_schedule_runs_total{{outcome=\"failed\"}} {gMetrics.scheduleFailed}\n")
    family(res, "donkey_schedule_missed_total", "counter",
           "Scheduled occurrences that did not run")
    res.add(&"donkey_schedule_missed_total {gMetrics.scheduleMissed}\n")

    family(res, "donkey_sessions_active", "gauge", "Sessions with a running agent")
    res.add(&"donkey_sessions_active {gMetrics.activeSessions}\n")
    if gMetrics.startedAtMs > 0:
      family(res, "donkey_start_time_seconds", "gauge",
             "When the daemon started, in Unix seconds")
      res.add(&"donkey_start_time_seconds {gMetrics.startedAtMs div 1000}\n")
    if ($gMetrics.version).len > 0:
      family(res, "donkey_build_info", "gauge", "The running build")
      res.add(&"donkey_build_info{{version=\"{escapeLabel($gMetrics.version)}\"}} 1\n")

    result = res

