## Turn traces as OpenTelemetry spans (second round, front 3): the endpoint
## and headers from the standard OTEL_EXPORTER_OTLP_* variables, and one
## turn as an OTLP/HTTP JSON span, its tool calls as span events. Format from
## the OTLP specification (opentelemetry.io/docs/specs/otlp, "OTLP/HTTP",
## JSON encoding) and the trace data model.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/turn_trace_pure
import donkey/domain/otlp_pure

let trace = TurnTrace(startedMs: 1_800_000_000_000, durationMs: 1_500, userId: "u-1",
  channel: "telegram", kind: "user", sessionId: "s-1", provider: "openrouter",
  streamed: true, tools: @[ToolCallTrace(name: "web_search", outcome: "output"),
                           ToolCallTrace(name: "bash", outcome: "operational_error")],
  inputTokens: 1200, outputTokens: 300, outcome: "ok")

proc attr(attrs: JsonNode; key: string): JsonNode =
  for a in attrs:
    if a["key"].getStr == key: return a["value"]

proc runTests*() =
  suite "otlp — where to send":

    test "the traces endpoint wins; otherwise the base endpoint plus /v1/traces":
      check otlpTracesUrl("", "").isErr
      check otlpTracesUrl("https://otel.example:4318", "").get == "https://otel.example:4318/v1/traces"
      check otlpTracesUrl("https://otel.example:4318/", "").get == "https://otel.example:4318/v1/traces"
      check otlpTracesUrl("https://a", "https://b/custom").get == "https://b/custom"
      check otlpTracesUrl("ftp://x", "").isErr

    test "headers are key=value pairs, URL-encoded values decoded":
      check parseOtlpHeaders("Authorization=Bearer%20abc, x-team = ops") ==
        @[("Authorization", "Bearer abc"), ("x-team", "ops")]
      check parseOtlpHeaders("") == newSeq[(string, string)]()
      check parseOtlpHeaders("broken") == newSeq[(string, string)]()

  suite "otlp — the span":

    test "one resource span for the donkey service, one span for the turn":
      let j = parseJson(otlpTraceJson(trace, "0af7651916cd43dd8448eb211c80319c", "b7ad6b7169203331"))
      let rs = j["resourceSpans"][0]
      check rs["resource"]["attributes"].attr("service.name")["stringValue"].getStr == "donkey"
      let span = rs["scopeSpans"][0]["spans"][0]
      check span["traceId"].getStr == "0af7651916cd43dd8448eb211c80319c"
      check span["spanId"].getStr == "b7ad6b7169203331"
      check span["name"].getStr == "donkey.turn user"
      check span["startTimeUnixNano"].getStr == "1800000000000000000"
      check span["endTimeUnixNano"].getStr == "1800000001500000000"

    test "what the turn was, as attributes; never what was said":
      let span = parseJson(otlpTraceJson(trace, "a".repeat(32), "b".repeat(16)))["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
      let a = span["attributes"]
      check a.attr("donkey.channel")["stringValue"].getStr == "telegram"
      check a.attr("donkey.provider")["stringValue"].getStr == "openrouter"
      check a.attr("donkey.streamed")["boolValue"].getBool
      check a.attr("gen_ai.usage.input_tokens")["intValue"].getStr == "1200"
      check a.attr("gen_ai.usage.output_tokens")["intValue"].getStr == "300"
      check a.attr("gen_ai.usage.cache_read_input_tokens")["intValue"].getStr == "0"
      check a.attr("donkey.outcome")["stringValue"].getStr == "ok"
      check span["status"]["code"].getInt == 1

    test "each tool call is an event with its outcome":
      let span = parseJson(otlpTraceJson(trace, "a".repeat(32), "b".repeat(16)))["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
      check span["events"].len == 2
      check span["events"][0]["name"].getStr == "tool web_search"
      check span["events"][1]["attributes"].attr("donkey.tool.outcome")["stringValue"].getStr == "operational_error"

    test "a clock that stepped back never makes the span end before it starts":
      var odd = trace
      odd.durationMs = -500
      let span = parseJson(otlpTraceJson(odd, "a".repeat(32), "b".repeat(16)))["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
      check span["endTimeUnixNano"].getStr == span["startTimeUnixNano"].getStr

    test "a turn that did not end well is an error span":
      var failed = trace
      failed.outcome = "provider_error"
      let span = parseJson(otlpTraceJson(failed, "a".repeat(32), "b".repeat(16)))["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
      check span["status"]["code"].getInt == 2

when isMainModule:
  runTests()
