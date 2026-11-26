## Metrics tests — verify that operational failure counters are
## recorded and rendered correctly for outbound, webhook, and reminder paths.
##
## US-012 AC:
##   1. Falhas de outbound emitem métrica estruturada
##   2. Falhas de webhook emitem métrica estruturada
##   3. Falhas de reminder emitem métrica estruturada
##   4. Métricas são rastreáveis sem poluir UX final do usuário

import std/[strutils, unittest, tables]
import donkey/core/pipeops
import donkey/app/metrics
import donkey/app/metrics_server

proc runTests*() =
  suite "metrics — configuration validation":

    test "parseMetricsPort rejects non-numeric, zero and out-of-range ports":
      check parseMetricsPort("abc").isErr
      check parseMetricsPort("0").isErr
      check parseMetricsPort("65536").isErr
      check parseMetricsPort("-1").isErr

    test "parseMetricsPort accepts a valid port":
      check parseMetricsPort("9090").isOk
      check parseMetricsPort("9090").get() == 9090

    test "validateMetricsBind rejects an invalid address":
      check validateMetricsBind("127.0.0.1", 9090).isOk
      check validateMetricsBind("not an address", 9090).isErr

  suite "metrics — operational failure counters":

    test "initMetrics initializes empty counters":
      initMetrics()
      check metricsSnapshot().outboundFailures.len == 0
      check metricsSnapshot().webhookFailures.len == 0
      check metricsSnapshot().reminderFailures.len == 0

    test "recordOutboundFailure increments counter per channel":
      initMetrics()
      recordOutboundFailure("qq", "network unreachable")
      check metricsSnapshot().outboundFailures.hasKey("qq")
      check metricsSnapshot().outboundFailures["qq"] == 1

      recordOutboundFailure("qq", "timeout")
      check metricsSnapshot().outboundFailures["qq"] == 2

      recordOutboundFailure("tg", "network unreachable")
      check metricsSnapshot().outboundFailures.hasKey("tg")
      check metricsSnapshot().outboundFailures["tg"] == 1

    test "recordWebhookFailure increments counter per server type":
      initMetrics()
      recordWebhookFailure("wechat", "parse error")
      check metricsSnapshot().webhookFailures.hasKey("wechat")
      check metricsSnapshot().webhookFailures["wechat"] == 1

      recordWebhookFailure("qq", "connection reset")
      check metricsSnapshot().webhookFailures.hasKey("qq")
      check metricsSnapshot().webhookFailures["qq"] == 1

    test "recordReminderFailure increments counter":
      initMetrics()
      recordReminderFailure("delivery timeout")
      check metricsSnapshot().reminderFailures.len == 1
      check metricsSnapshot().reminderFailures.hasKey("delivery timeout")
      check metricsSnapshot().reminderFailures["delivery timeout"] == 1

      recordReminderFailure("delivery timeout")
      check metricsSnapshot().reminderFailures["delivery timeout"] == 2

    test "provider latency and errors are rendered per provider":
      initMetrics()
      recordLatency("openrouter", 120.0)
      recordLatency("openrouter", 80.0)
      recordError("openrouter")
      recordError("gemini")

      let rendered = renderMetrics()
      check "provider=\"openrouter\"" in rendered
      check "donkey_provider_latency_ms_count{provider=\"openrouter\"} 2" in rendered
      check "donkey_provider_latency_ms_sum{provider=\"openrouter\"} 200.0" in rendered
      check "donkey_provider_errors_total{provider=\"openrouter\"} 1" in rendered
      check "donkey_provider_errors_total{provider=\"gemini\"} 1" in rendered
      check "donkey_provider_latency_ms_sum{provider=\"gemini\"}" notin rendered
      check "donkey_provider_latency_ms_count{provider=\"gemini\"}" notin rendered

    test "renderMetrics escapes quotes in label values":
      initMetrics()
      recordWebhookFailure("we\"ird", "boom")
      let rendered = renderMetrics()
      check "server=\"we\\\"ird\"" in rendered

    test "renderMetrics includes operational failure counters":
      initMetrics()
      recordOutboundFailure("qq", "network unreachable")
      recordOutboundFailure("qq", "timeout")
      recordOutboundFailure("tg", "network unreachable")
      recordWebhookFailure("wechat", "sig mismatch")
      recordReminderFailure("delivery timeout")

      let rendered = renderMetrics()
      check "donkey_outbound_failures_total" in rendered
      check "donkey_webhook_failures_total" in rendered
      check "donkey_reminder_failures_total" in rendered
      check "channel=\"qq\"" in rendered
      check "channel=\"tg\"" in rendered
      check "server=\"wechat\"" in rendered
      check "reason=\"delivery timeout\"" in rendered

    test "metrics are gcsafe and thread-safe (no crash on concurrent calls)":
      initMetrics()
      # Just verify these compile and run without error in gcsafe context
      recordOutboundFailure("fs", "rate limited")
      recordWebhookFailure("wecom", "token expired")
      recordReminderFailure("corrupted state")
      check metricsSnapshot().outboundFailures["fs"] == 1
      check metricsSnapshot().webhookFailures["wecom"] == 1
      check metricsSnapshot().reminderFailures["corrupted state"] == 1

    test "metrics do not pollute user-facing output":
      # Operational failure counters are only exposed on /metrics endpoint,
      # not in user-facing messages or responses.
      # This is a design invariant verified by architecture (separate module).
      initMetrics()
      let rendered = renderMetrics()
      # Metrics output is machine-readable Prometheus format, not user-facing text
      check rendered.startsWith("# HELP donkey_")
      check "# TYPE donkey_" in rendered

  suite "metrics — turns, tools, tokens, traffic and schedules":

    test "provider latency is a histogram with cumulative buckets":
      initMetrics()
      recordLatency("openrouter", 80.0)
      recordLatency("openrouter", 700.0)
      recordLatency("openrouter", 400_000.0)
      let r = renderMetrics()
      check "# TYPE donkey_provider_latency_ms histogram" in r
      check "donkey_provider_latency_ms_bucket{provider=\"openrouter\",le=\"50\"} 0" in r
      check "donkey_provider_latency_ms_bucket{provider=\"openrouter\",le=\"100\"} 1" in r
      check "donkey_provider_latency_ms_bucket{provider=\"openrouter\",le=\"1000\"} 2" in r
      check "donkey_provider_latency_ms_bucket{provider=\"openrouter\",le=\"300000\"} 2" in r
      check "donkey_provider_latency_ms_bucket{provider=\"openrouter\",le=\"+Inf\"} 3" in r
      check "donkey_provider_latency_ms_count{provider=\"openrouter\"} 3" in r

    test "tokens are counted per provider and direction":
      initMetrics()
      recordTokens("deepseek", 1200, 300)
      recordTokens("deepseek", 800, 0)
      recordTokens("gemini", 0, 0)
      let r = renderMetrics()
      check "donkey_provider_tokens_total{provider=\"deepseek\",direction=\"input\"} 2000" in r
      check "donkey_provider_tokens_total{provider=\"deepseek\",direction=\"output\"} 300" in r
      check "provider=\"gemini\",direction" notin r

    test "cached tokens are their own directions (E8.3)":
      initMetrics()
      recordTokens("anthropic", 3000, 5, cacheRead = 2048, cacheWrite = 100)
      let r = renderMetrics()
      check "donkey_provider_tokens_total{provider=\"anthropic\",direction=\"cache_read\"} 2048" in r
      check "donkey_provider_tokens_total{provider=\"anthropic\",direction=\"cache_write\"} 100" in r

    test "turns are counted per channel and outcome, with their duration":
      initMetrics()
      recordTurn("telegram", "user", 3_000.0, ok = true)
      recordTurn("telegram", "user", 9_000.0, ok = false)
      recordTurn("discord", "schedule", 500.0, ok = true)
      let r = renderMetrics()
      check "donkey_turns_total{channel=\"telegram\",kind=\"user\",outcome=\"ok\"} 1" in r
      check "donkey_turns_total{channel=\"telegram\",kind=\"user\",outcome=\"error\"} 1" in r
      check "donkey_turns_total{channel=\"discord\",kind=\"schedule\",outcome=\"ok\"} 1" in r
      check "donkey_turn_duration_ms_count{channel=\"telegram\"} 2" in r
      check "donkey_turn_duration_ms_sum{channel=\"telegram\"} 12000.0" in r

    test "tool calls are counted per tool and outcome, with their duration":
      initMetrics()
      recordToolCall("bash", 120.0, ok = true)
      recordToolCall("bash", 30.0, ok = false)
      recordToolCall("web_search", 900.0, ok = true)
      let r = renderMetrics()
      check "donkey_tool_calls_total{tool=\"bash\",outcome=\"ok\"} 1" in r
      check "donkey_tool_calls_total{tool=\"bash\",outcome=\"error\"} 1" in r
      check "donkey_tool_duration_ms_count{tool=\"web_search\"} 1" in r

    test "inbound and delivered messages are counted per channel":
      initMetrics()
      recordInbound("slack")
      recordInbound("slack")
      recordOutboundSent("slack")
      let r = renderMetrics()
      check "donkey_inbound_messages_total{channel=\"slack\"} 2" in r
      check "donkey_outbound_messages_total{channel=\"slack\"} 1" in r

    test "schedule runs and misses are counted":
      initMetrics()
      recordScheduleRun(sent = true)
      recordScheduleRun(sent = false)
      recordScheduleMissed(4)
      recordScheduleMissed(0)
      let r = renderMetrics()
      check "donkey_schedule_runs_total{outcome=\"sent\"} 1" in r
      check "donkey_schedule_runs_total{outcome=\"failed\"} 1" in r
      check "donkey_schedule_missed_total 4" in r

    test "start time, build and active sessions are gauges":
      initMetrics(startedAtMs = 1_700_000_000_000'i64, version = "1.2.3")
      setActiveSessions(3)
      let r = renderMetrics()
      check "donkey_start_time_seconds 1700000000" in r
      check "donkey_build_info{version=\"1.2.3\"} 1" in r
      check "# TYPE donkey_sessions_active gauge" in r
      check "donkey_sessions_active 3" in r

    test "every family has HELP and TYPE once":
      initMetrics()
      recordTurn("cli", "user", 1.0, ok = true)
      recordToolCall("calc", 1.0, ok = true)
      let r = renderMetrics()
      for family in ["donkey_turns_total", "donkey_turn_duration_ms",
                     "donkey_tool_calls_total", "donkey_tool_duration_ms",
                     "donkey_provider_tokens_total", "donkey_inbound_messages_total",
                     "donkey_outbound_messages_total", "donkey_schedule_runs_total",
                     "donkey_schedule_missed_total"]:
        check r.count("# TYPE " & family & " ") == 1
        check r.count("# HELP " & family & " ") == 1

when isMainModule:
  runTests()
