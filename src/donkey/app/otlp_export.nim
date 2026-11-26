## otlp_export — sending a turn's trace to an OpenTelemetry collector
## (second round, front 3).
##
## On when OTEL_EXPORTER_OTLP_TRACES_ENDPOINT or OTEL_EXPORTER_OTLP_ENDPOINT
## is set (OTEL_EXPORTER_OTLP_HEADERS for auth). The span is built by
## domain/otlp_pure; the POST goes through OffLoopIo, off the event loop,
## only to the endpoint's host. The orchestrator spawns it after the turn,
## so a slow collector never delays an answer; a failure is returned for it
## to log.

import std/[monotimes, strutils, sysrand, uri]
import chronos
import ../config/environment
import ../core/pipeops
import ../domain/otlp_pure
import ../domain/turn_trace_pure
import ./offloop_io

func otlpEnabled*(env: Environment): bool =
  otlpTracesUrl(env.get("OTEL_EXPORTER_OTLP_ENDPOINT"),
                env.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")).isOk

var gFallbackCounter {.threadvar.}: uint64

func fallbackHex*(bytes: int; seed: uint64): string =
  ## Without the system's random source: a splitmix64 stream from the seed,
  ## never all zeros (an invalid id).
  var x = seed
  while result.len < bytes * 2:
    x += 0x9E3779B97F4A7C15'u64
    var z = x
    z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9'u64
    z = (z xor (z shr 27)) * 0x94D049BB133111EB'u64
    z = z xor (z shr 31)
    result.add z.toHex(16).toLowerAscii
  result.setLen(bytes * 2)
  if result == "0".repeat(bytes * 2):
    result[^1] = '1'

proc randomHex(bytes: int): string =
  var raw = newSeq[byte](bytes)
  if not urandom(raw):
    inc gFallbackCounter
    return fallbackHex(bytes, uint64(getMonoTime().ticks) xor (gFallbackCounter shl 32))
  for b in raw: result.add b.toHex(2).toLowerAscii

proc exportTurnTrace*(env: Environment; trace: TurnTrace; io: OffLoopIo):
    Future[Result[void, string]] {.async: (raises: []).} =
  let url = otlpTracesUrl(env.get("OTEL_EXPORTER_OTLP_ENDPOINT"),
                          env.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")).valueOr:
    return err(error)
  if io.httpPost == nil:
    return err("OTLP export is not available in this process")
  let host =
    try: parseUri(url).hostname
    except CatchableError: ""
  if host.len == 0:
    return err("the OTLP endpoint has no host: " & url)
  let body = otlpTraceJson(trace, randomHex(16), randomHex(8))
  let headers = @[("Content-Type", "application/json")] &
                parseOtlpHeaders(env.get("OTEL_EXPORTER_OTLP_HEADERS"))
  let resp = (await io.httpPost(url, body, headers, @[host])).valueOr:
    return err("OTLP export failed: " & error)
  if resp.status notin 200 .. 299:
    return err("OTLP export answered " & $resp.status)
  return ok()
