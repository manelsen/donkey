## Exporting a turn trace over OTLP (second round, front 3): configured by
## the standard variables, sent off the loop through OffLoopIo, only to the
## endpoint's host; a failure is reported, never raised.

import std/[json, strutils, unittest]
import chronos
import donkey/app/offloop_io
import donkey/app/otlp_export
import donkey/config/environment
import donkey/core/pipeops
import donkey/domain/turn_trace_pure
import donkey/ports/http

type Seen = ref object
  posts: seq[(string, string, seq[HttpHeader], seq[string])]

proc io(s: Seen; status = 200): OffLoopIo =
  OffLoopIo(httpPost: proc(url, body: string; headers: seq[HttpHeader]; allowHosts: seq[string]):
      Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.} =
    {.cast(gcsafe).}:
      s.posts.add (url, body, headers, allowHosts)
    return ok(HttpResponse(status: status)))

let trace = TurnTrace(startedMs: 1_800_000_000_000, durationMs: 10, userId: "u",
                      channel: "cli", kind: "user", outcome: "ok")

proc runTests*() =
  suite "otlp export":

    test "off when no endpoint is set":
      check not otlpEnabled(environmentOf({"X": "1"}))
      check otlpEnabled(environmentOf({"OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example:4318"}))

    test "a trace is posted as OTLP JSON, with the configured headers, only to that host":
      let s = Seen()
      let env = environmentOf({"OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example:4318",
                               "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer%20t"})
      check (waitFor exportTurnTrace(env, trace, io(s))).isOk
      check s.posts.len == 1
      let (url, body, headers, hosts) = s.posts[0]
      check url == "https://otel.example:4318/v1/traces"
      check parseJson(body)["resourceSpans"][0]["scopeSpans"][0]["spans"][0]["traceId"].getStr.len == 32
      check ("Content-Type", "application/json") in headers
      check ("Authorization", "Bearer t") in headers
      check hosts == @["otel.example"]

    test "each export has its own ids":
      let s = Seen()
      let env = environmentOf({"OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example"})
      discard waitFor exportTurnTrace(env, trace, io(s))
      discard waitFor exportTurnTrace(env, trace, io(s))
      proc idOf(i: int): string =
        parseJson(s.posts[i][1])["resourceSpans"][0]["scopeSpans"][0]["spans"][0]["spanId"].getStr
      check idOf(0) != idOf(1) and idOf(0).len == 16

    test "ids stay unique even without the system's random source":
      check fallbackHex(8, 1) != fallbackHex(8, 2)
      check fallbackHex(8, 1).len == 16 and fallbackHex(16, 1).len == 32
      check fallbackHex(8, 0) != "0".repeat(16)

    test "a refused export or no runner is an error to log":
      let env = environmentOf({"OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example"})
      check (waitFor exportTurnTrace(env, trace, io(Seen(), status = 400))).isErr
      check (waitFor exportTurnTrace(env, trace, OffLoopIo())).isErr

when isMainModule:
  runTests()
