# Metrics

The daemon exports Prometheus metrics when `DONKEY_METRICS_PORT` is set:

```sh
DONKEY_METRICS_PORT=9464          # off when unset
DONKEY_METRICS_BIND=127.0.0.1     # default; labels carry provider, channel and tool names
curl -s http://127.0.0.1:9464/metrics
```

The exporter runs on its own threads, so a busy daemon still answers scrapes.
Every label set is capped at 64 values; the rest is counted under `_other`.

| Metric | Type | Labels | What |
|---|---|---|---|
| `donkey_turns_total` | counter | channel, kind, outcome | agent turns; `kind` is user, schedule, heartbeat…; `outcome` is `error` when the turn ended on a provider error |
| `donkey_turn_duration_ms` | histogram | channel | turn duration |
| `donkey_tool_calls_total` | counter | tool, outcome | tool calls; `error` when the tool returned an error |
| `donkey_tool_duration_ms` | histogram | tool | tool call duration (approval waits included) |
| `donkey_provider_latency_ms` | histogram | provider | one completion, streamed or not |
| `donkey_provider_errors_total` | counter | provider | failed completions |
| `donkey_provider_tokens_total` | counter | provider, direction | tokens the provider reported (`input`/`output`) |
| `donkey_inbound_messages_total` | counter | channel | user messages received |
| `donkey_outbound_messages_total` | counter | channel | messages delivered |
| `donkey_outbound_failures_total` | counter | channel | deliveries that failed |
| `donkey_webhook_failures_total` | counter | server | webhook processing failures |
| `donkey_reminder_failures_total` | counter | reason | reminder delivery failures |
| `donkey_schedule_runs_total` | counter | outcome | scheduled runs handed to a session (`sent`/`failed`) |
| `donkey_schedule_missed_total` | counter | — | scheduled occurrences that did not run |
| `donkey_sessions_active` | gauge | — | sessions with a running agent |
| `donkey_start_time_seconds` | gauge | — | daemon start, Unix seconds |
| `donkey_build_info` | gauge | version | always 1 |

Histogram buckets (ms): 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000,
60000, 120000, 300000, +Inf.

Useful queries:

```promql
sum by (channel) (rate(donkey_turns_total{outcome="error"}[1h]))
  / sum by (channel) (rate(donkey_turns_total[1h]))           # turn error rate
histogram_quantile(0.95, sum by (le, provider) (rate(donkey_provider_latency_ms_bucket[15m])))
sum by (provider) (increase(donkey_provider_tokens_total[1d]))  # tokens per day
topk(5, sum by (tool) (rate(donkey_tool_calls_total{outcome="error"}[1h])))
```

## Traces

The metrics are totals. A trace is one turn's account, written when traces
are on:

```sh
DONKEY_TRACES=on            # off when unset
DONKEY_TRACES_DAYS=14       # days kept; default 14
```

Each agent turn appends one JSON line to `{home}/state/traces/YYYY-MM-DD.jsonl`
(UTC days; the files are readable only by the daemon's user, and the first
line of a new day removes the days past the retention):

```json
{"ts":1800000000000,"duration_ms":2310,"user":"<uuid>","channel":"telegram",
 "kind":"user","session":"s-12","provider":"openrouter","streamed":true,
 "tools":[{"name":"session_search","outcome":"output"}],
 "tokens":{"input":1830,"output":212},"outcome":"ok"}
```

`agent_provider` appears when a named agent with its own provider answered.
`outcome` is `ok`, `provider_error` or `stopped`; a tool's `outcome` is the
status its result reported (`output`, `usage_error`, `operational_error`…) or
`none` when no result came back. Nothing the person or the agent said is in a
trace: no message, tool input or tool output.

Export with the CLI, oldest first:

```sh
donkey ctl traces                       # everything kept
donkey ctl traces --since 24h           # or 7d, 2w, YYYY-MM-DD
donkey ctl traces --user <uuid> --since 7d
```
