## route_metrics — provider routing counters, recent samples and cooldowns.
##
## Composition-root code extracted from `src/donkey.nim`; it is not app logic
## and may reference concrete adapters.
##
## All state lives in `DaemonRuntime`; the procs here only mutate/read it.
## Extracted from the entry point, which keeps the lock-guarded calls.

import std/[algorithm, json, locks, os, strutils, tables, times]
import donkey/adapters/ipc/types as ipcTypes
import donkey/core/providers/smart_routing
import donkey/ports/provider
import ./daemon_types

var gRoutingLock: Lock
var gRoutingLockReady = false

proc initRoutingLock*() =
  if not gRoutingLockReady:
    initLock(gRoutingLock)
    gRoutingLockReady = true

template withRouteLock*(body: untyped): untyped =
  block:
    acquire(gRoutingLock)
    try:
      body
    finally:
      release(gRoutingLock)

func recentRouteSampleTtlSec(): int64 =
  let raw = getEnv("DONKEY_ROUTE_HEALTH_TTL_SEC")
  if raw.len == 0:
    return DefaultRecentRouteSampleTtlSec
  try:
    let ttl = parseInt(raw)
    if ttl > 0: ttl else: DefaultRecentRouteSampleTtlSec
  except ValueError:
    DefaultRecentRouteSampleTtlSec

func routeHealthPath*(home: string): string =
  home / "state" / "route_health.json"

func providerCooldownSec*(): int64 =
  let raw = getEnv("DONKEY_PROVIDER_COOLDOWN_SEC")
  if raw.len == 0:
    return DefaultProviderCooldownSec
  try:
    let ttl = parseInt(raw)
    if ttl > 0: ttl else: DefaultProviderCooldownSec
  except ValueError:
    DefaultProviderCooldownSec

proc pruneRecentRouteSamples*(runtime: DaemonRuntime) =
  let nowSec = getTime().toUnix()
  let ttlSec = recentRouteSampleTtlSec()
  for route, samples in runtime.routeRecentSamples.mpairs:
    var kept: seq[RouteSample] = @[]
    for sample in samples:
      if sample.recordedAtUnix > 0 and nowSec - sample.recordedAtUnix <= ttlSec:
        kept.add(sample)
    if kept.len > RecentRouteSampleLimit:
      kept = kept[(kept.len - RecentRouteSampleLimit) .. ^1]
    samples = kept

proc pruneProviderCooldowns*(runtime: DaemonRuntime) =
  let nowSec = getTime().toUnix()
  var expired: seq[string] = @[]
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix <= nowSec:
      expired.add(providerName)
  for providerName in expired:
    runtime.providerCooldownUntil.del(providerName)

proc saveRecentRouteSamples*(runtime: DaemonRuntime) =
  if runtime.routeHealthPath.len == 0:
    return
  try:
    runtime.pruneRecentRouteSamples()
    createDir(parentDir(runtime.routeHealthPath))
    var data = newJArray()
    for route, samples in runtime.routeRecentSamples:
      if samples.len == 0:
        continue
      var sampleData = newJArray()
      for sample in samples:
        sampleData.add(%*{
          "ok": sample.ok,
          "elapsed_ms": sample.elapsedMs,
          "recorded_at": sample.recordedAtUnix,
        })
      data.add(%*{
        "route": route,
        "samples": sampleData,
      })
    var cooldowns = newJArray()
    for providerName, untilUnix in runtime.providerCooldownUntil:
      cooldowns.add(%*{
        "provider": providerName,
        "until_unix": untilUnix,
      })
    writeFile(runtime.routeHealthPath, $(%*{
      "saved_at": getTime().toUnix(),
      "routes": data,
      "provider_cooldowns": cooldowns,
    }))
  except CatchableError:
    discard

proc loadRecentRouteSamples*(runtime: DaemonRuntime) =
  if runtime.routeHealthPath.len == 0 or not fileExists(runtime.routeHealthPath):
    return
  try:
    let parsed = parseJson(readFile(runtime.routeHealthPath))
    for routeNode in parsed{"routes"}:
      let route = routeNode{"route"}.getStr("")
      if route.len == 0:
        continue
      var samples: seq[RouteSample] = @[]
      for sampleNode in routeNode{"samples"}:
        samples.add(RouteSample(
          ok: sampleNode{"ok"}.getBool(false),
          elapsedMs: sampleNode{"elapsed_ms"}.getInt(0),
          recordedAtUnix: sampleNode{"recorded_at"}.getBiggestInt(0),
        ))
      runtime.routeRecentSamples[route] = samples
    runtime.pruneRecentRouteSamples()
    for cooldownNode in parsed{"provider_cooldowns"}:
      let providerName = cooldownNode{"provider"}.getStr("")
      let untilUnix = cooldownNode{"until_unix"}.getBiggestInt(0)
      if providerName.len > 0 and untilUnix > 0:
        runtime.providerCooldownUntil[providerName] = untilUnix
    runtime.pruneProviderCooldowns()
  except CatchableError:
    discard

proc recordRouteChoice*(runtime: DaemonRuntime; selection: ProviderSelection) =
  let key = selection.formatSelection
  runtime.routeCounts[key] = runtime.routeCounts.getOrDefault(key) + 1

proc refreshProviderCooldowns*(runtime: DaemonRuntime) {.gcsafe.}
proc currentRouteFeedback*(runtime: DaemonRuntime): seq[RouteFeedback] {.gcsafe.}

proc recordRouteResult*(runtime: DaemonRuntime;
                        selection: ProviderSelection;
                        elapsedMs: int64;
                        ok: bool) {.gcsafe.} =
  let key = selection.formatSelection
  let nowSec = getTime().toUnix()
  runtime.routeCallCounts[key] = runtime.routeCallCounts.getOrDefault(key) + 1
  runtime.routeLatencyTotalsMs[key] = runtime.routeLatencyTotalsMs.getOrDefault(key) + elapsedMs
  var samples = runtime.routeRecentSamples.getOrDefault(key)
  samples.add(RouteSample(
    ok: ok,
    elapsedMs: if elapsedMs > 0: int(elapsedMs) else: 0,
    recordedAtUnix: nowSec,
  ))
  if samples.len > RecentRouteSampleLimit:
    samples = samples[(samples.len - RecentRouteSampleLimit) .. ^1]
  runtime.routeRecentSamples[key] = samples
  runtime.pruneRecentRouteSamples()
  runtime.saveRecentRouteSamples()
  if ok:
    runtime.routeOkCounts[key] = runtime.routeOkCounts.getOrDefault(key) + 1
  else:
    runtime.routeErrCounts[key] = runtime.routeErrCounts.getOrDefault(key) + 1
  runtime.refreshProviderCooldowns()

proc refreshProviderCooldowns*(runtime: DaemonRuntime) {.gcsafe.} =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  for feedback in aggregateProviderFeedback(runtime.currentRouteFeedback()):
    if feedback.shouldCircuitBreakProvider and
       runtime.providerCooldownUntil.getOrDefault(feedback.providerName) <= nowSec:
      runtime.providerCooldownUntil[feedback.providerName] = nowSec + providerCooldownSec()
  runtime.saveRecentRouteSamples()

proc topRouteCounts*(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteCount] =
  var items: seq[(string, int)] = @[]
  for route, count in runtime.routeCounts:
    items.add((route, count))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    result.add(ipcTypes.RouteCount(route: items[i][0], count: items[i][1]))

proc topRouteMetrics*(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteMetric] =
  var items: seq[(string, int)] = @[]
  for route, calls in runtime.routeCallCounts:
    items.add((route, calls))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let route = items[i][0]
    let calls = items[i][1]
    let totalLatency = runtime.routeLatencyTotalsMs.getOrDefault(route)
    result.add(ipcTypes.RouteMetric(
      route: route,
      calls: calls,
      okCalls: runtime.routeOkCounts.getOrDefault(route),
      errCalls: runtime.routeErrCounts.getOrDefault(route),
      avgLatencyMs: if calls > 0: int(totalLatency div calls) else: 0,
    ))

proc topRecentRouteMetrics*(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteMetric] =
  runtime.pruneRecentRouteSamples()
  var items: seq[(string, int)] = @[]
  for route, samples in runtime.routeRecentSamples:
    if samples.len > 0:
      items.add((route, samples.len))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let route = items[i][0]
    let samples = runtime.routeRecentSamples.getOrDefault(route)
    var okCalls = 0
    var errCalls = 0
    var totalLatency = 0
    for sample in samples:
      totalLatency += sample.elapsedMs
      if sample.ok:
        inc okCalls
      else:
        inc errCalls
    let calls = samples.len
    result.add(ipcTypes.RouteMetric(
      route: route,
      calls: calls,
      okCalls: okCalls,
      errCalls: errCalls,
      avgLatencyMs: if calls > 0: totalLatency div calls else: 0,
    ))

proc currentRouteFeedback*(runtime: DaemonRuntime): seq[RouteFeedback] {.gcsafe.} =
  runtime.pruneRecentRouteSamples()
  for route, samples in runtime.routeRecentSamples:
    if samples.len == 0:
      continue
    var okCalls = 0
    var errCalls = 0
    var totalLatency = 0
    for sample in samples:
      totalLatency += sample.elapsedMs
      if sample.ok:
        inc okCalls
      else:
        inc errCalls
    let calls = samples.len
    result.add(RouteFeedback(
      route: route,
      calls: calls,
      okCalls: okCalls,
      errCalls: errCalls,
      avgLatencyMs: if calls > 0: totalLatency div calls else: 0,
    ))

proc topRecentProviderMetrics*(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.ProviderMetric] =
  let feedback = aggregateProviderFeedback(runtime.currentRouteFeedback())
  var items = feedback
  items.sort(proc(a, b: ProviderFeedback): int =
    if a.calls != b.calls:
      return cmp(b.calls, a.calls)
    cmp(a.providerName, b.providerName)
  )
  for i in 0 ..< min(limit, items.len):
    result.add(ipcTypes.ProviderMetric(
      providerName: items[i].providerName,
      calls: items[i].calls,
      okCalls: items[i].okCalls,
      errCalls: items[i].errCalls,
      avgLatencyMs: items[i].avgLatencyMs,
    ))

proc activeProviderCooldowns*(runtime: DaemonRuntime; limit = 5): seq[string] =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  var items: seq[(string, int64)] = @[]
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix > nowSec:
      items.add((providerName, untilUnix))
  items.sort(proc(a, b: (string, int64)): int =
    if a[1] != b[1]:
      return cmp(a[1], b[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let remaining = max(0'i64, items[i][1] - nowSec)
    result.add(items[i][0] & " (" & relativeAgeText(remaining) & ")")

proc currentProviderCooldowns*(runtime: DaemonRuntime): seq[ProviderCooldown] =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix > nowSec:
      result.add(ProviderCooldown(providerName: providerName, untilUnix: untilUnix))
