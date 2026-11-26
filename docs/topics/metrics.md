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
| `donkey_provider_tokens_total` | counter | provider, direction | tokens the provider reported (`input`/`output`); `cache_read` and `cache_write` are the part of `input` served from and written to the prompt cache |
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
sum by (provider) (increase(donkey_provider_tokens_total{direction=~"input|output"}[1d]))  # tokens per day
sum by (provider) (rate(donkey_provider_tokens_total{direction="cache_read"}[1h]))
  / sum by (provider) (rate(donkey_provider_tokens_total{direction="input"}[1h]))  # prompt cache hit share
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
(next to the `paddocks` directory when that is configured elsewhere; UTC
days; the files are readable only by the daemon's user, and the first line
of a new day removes the days past the retention, so a shorter retention
takes effect the next day):

```json
{"ts":1800000000000,"duration_ms":2310,"user":"<uuid>","channel":"telegram",
 "kind":"user","session":"s-12","provider":"openrouter","streamed":true,
 "tools":[{"name":"session_search","outcome":"output"}],
 "tokens":{"input":1830,"output":212,"cache_read":1536,"cache_write":0},"outcome":"ok"}
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

### OpenTelemetry

The same account can go to an OpenTelemetry collector, as one span per turn,
over OTLP/HTTP with the JSON encoding. It is configured with the standard
variables, independently of `DONKEY_TRACES`:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.example:4318      # spans go to …/v1/traces
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://otel.example/x  # or this exact URL
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer%20<token>  # key=value pairs, URL-encoded
```

The span is `donkey.turn <kind>` for the `donkey` service, with the trace's
fields as attributes (`donkey.channel`, `donkey.provider`, `donkey.outcome`,
`gen_ai.usage.input_tokens`, `gen_ai.usage.cache_read_input_tokens`, …) and each tool call as an event with its
outcome; a turn that did not end `ok` (or `stopped`) is an error span. As with
the file, nothing that was said goes out. The export runs off the event loop
after the turn, only to the endpoint's host, so a slow or absent collector
never delays an answer; a failure is a warning in the log.

Traces are not replayable: they carry no content, by design, so a turn cannot
be re-run from one.

### Insights

The traces summed into a report: turns, tokens in and out (and the share of
the input served from the prompt cache, per provider, and a warning for a
provider whose large prompts never hit it; `donkey doctor` checks the same
over the last 7 days), the tools used most
and how often each failed, providers, channels and outcomes; for one person,
also the learned skills they loaded most.

```sh
donkey ctl insights --since 30d
donkey ctl insights --since 7d --user <uuid>
```

It reads the trace files, so it covers what was traced (`DONKEY_TRACES=on`).
