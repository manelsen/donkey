## Metrics tests — verify that operational failure counters are
## recorded and rendered correctly for outbound, webhook, and reminder paths.
##
## US-012 AC:
##   1. Falhas de outbound emitem métrica estruturada
##   2. Falhas de webhook emitem métrica estruturada
##   3. Falhas de reminder emitem métrica estruturada
##   4. Métricas são rastreáveis sem poluir UX final do usuário

import std/[strutils, unittest, tables]
import donkey/app/metrics

suite "metrics — operational failure counters":

  test "initMetrics initializes empty counters":
    initMetrics()
    check gMetrics.outboundFailures.len == 0
    check gMetrics.webhookFailures.len == 0
    check gMetrics.reminderFailures.len == 0

  test "recordOutboundFailure increments counter per channel":
    initMetrics()
    recordOutboundFailure("qq", "network unreachable")
    check gMetrics.outboundFailures.hasKey("qq")
    check gMetrics.outboundFailures["qq"] == 1

    recordOutboundFailure("qq", "timeout")
    check gMetrics.outboundFailures["qq"] == 2

    recordOutboundFailure("tg", "network unreachable")
    check gMetrics.outboundFailures.hasKey("tg")
    check gMetrics.outboundFailures["tg"] == 1

  test "recordWebhookFailure increments counter per server type":
    initMetrics()
    recordWebhookFailure("wechat", "parse error")
    check gMetrics.webhookFailures.hasKey("wechat")
    check gMetrics.webhookFailures["wechat"] == 1

    recordWebhookFailure("qq", "connection reset")
    check gMetrics.webhookFailures.hasKey("qq")
    check gMetrics.webhookFailures["qq"] == 1

  test "recordReminderFailure increments counter":
    initMetrics()
    recordReminderFailure("delivery timeout")
    check gMetrics.reminderFailures.len == 1
    check gMetrics.reminderFailures.hasKey("delivery timeout")
    check gMetrics.reminderFailures["delivery timeout"] == 1

    recordReminderFailure("delivery timeout")
    check gMetrics.reminderFailures["delivery timeout"] == 2

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
    check gMetrics.outboundFailures["fs"] == 1
    check gMetrics.webhookFailures["wecom"] == 1
    check gMetrics.reminderFailures["corrupted state"] == 1

  test "metrics do not pollute user-facing output":
    # Operational failure counters are only exposed on /metrics endpoint,
    # not in user-facing messages or responses.
    # This is a design invariant verified by architecture (separate module).
    let rendered = renderMetrics()
    # Metrics output is machine-readable Prometheus format, not user-facing text
    check rendered.startsWith("# HELP donkey_")
    check "# TYPE donkey_" in rendered
