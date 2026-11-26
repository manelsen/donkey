## otlp_pure — a turn trace as an OpenTelemetry span (second round, front 3).
##
## When an OTLP endpoint is configured with the standard variables
## (OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, or OTEL_EXPORTER_OTLP_ENDPOINT plus
## `/v1/traces`; headers in OTEL_EXPORTER_OTLP_HEADERS), each turn's trace
## (turn_trace_pure) goes out as one span, OTLP/HTTP with the JSON encoding.
## The span carries what the trace carries and nothing more: when, how long,
## which channel, kind, provider, tokens and outcome, and each tool call as
## an event, never what was said. Format from the OTLP specification and
## the trace data model (opentelemetry.io).

import std/[json, strutils, uri]
import ../core/pipeops
import ./turn_trace_pure

const
  StatusUnset = 0
  StatusOk = 1
  StatusError = 2

func otlpTracesUrl*(baseEndpoint, tracesEndpoint: string): Result[string, string] =
  let explicit = tracesEndpoint.strip
  var url =
    if explicit.len > 0: explicit
    else:
      var base = baseEndpoint.strip
      while base.endsWith("/"): base.setLen(base.len - 1)
      if base.len == 0: "" else: base & "/v1/traces"
  if url.len == 0:
    return err("no OTLP endpoint")
  if not (url.startsWith("https://") or url.startsWith("http://")):
    return err("the OTLP endpoint must be http(s): " & url)
  ok(url)

proc parseOtlpHeaders*(raw: string): seq[(string, string)] =
  ## `key=value,key2=value2`, values URL-encoded (the spec's format).
  for part in raw.split(','):
    let eq = part.find('=')
    if eq <= 0: continue
    let key = part[0 ..< eq].strip
    let value = decodeUrl(part[eq + 1 .. ^1].strip, decodePlus = false)
    if key.len > 0: result.add (key, value)

proc strAttr(key, value: string): JsonNode =
  %* {"key": key, "value": {"stringValue": value}}

proc intAttr(key: string; value: int): JsonNode =
  %* {"key": key, "value": {"intValue": $value}}   ## int64 as a string, per the JSON mapping

proc boolAttr(key: string; value: bool): JsonNode =
  %* {"key": key, "value": {"boolValue": value}}

func nanos(ms: int64): string = $ms & "000000"

proc otlpTraceJson*(t: TurnTrace; traceIdHex, spanIdHex: string): string =
  let endMs = t.startedMs + max(0'i64, t.durationMs)   ## a wall clock may step back
  var attrs = @[strAttr("donkey.channel", t.channel), strAttr("donkey.kind", t.kind),
                strAttr("donkey.session", t.sessionId), strAttr("donkey.user", t.userId),
                strAttr("donkey.provider", t.provider), boolAttr("donkey.streamed", t.streamed),
                intAttr("gen_ai.usage.input_tokens", t.inputTokens),
                intAttr("gen_ai.usage.output_tokens", t.outputTokens),
                strAttr("donkey.outcome", t.outcome)]
  if t.agentProvider.len > 0:
    attrs.add strAttr("donkey.agent_provider", t.agentProvider)
  var events = newJArray()
  for call in t.tools:
    events.add(%* {"timeUnixNano": nanos(endMs), "name": "tool " & call.name,
                   "attributes": [strAttr("donkey.tool.outcome", call.outcome)]})
  let code =
    case t.outcome
    of "ok": StatusOk
    of "stopped": StatusUnset
    else: StatusError
  let span = %* {
    "traceId": traceIdHex, "spanId": spanIdHex, "name": "donkey.turn " & t.kind,
    "kind": 1, "startTimeUnixNano": nanos(t.startedMs),
    "endTimeUnixNano": nanos(endMs),
    "attributes": attrs, "events": events, "status": {"code": code}}
  $(%* {"resourceSpans": [{
    "resource": {"attributes": [strAttr("service.name", "donkey")]},
    "scopeSpans": [{"scope": {"name": "donkey"}, "spans": [span]}]}]})
