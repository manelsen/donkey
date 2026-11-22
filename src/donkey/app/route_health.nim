## Route health: how each provider route has been doing, for smart routing
## and the status views.
##
## - Counters per route (choices, calls, ok, errors, latency) for the
##   daemon's lifetime.
## - Recent samples per route, kept within a TTL and capped, persisted to
##   `state/route_health.json` so a restart does not forget a failing route.
## - Provider cooldowns: a provider whose recent results trip
##   `shouldCircuitBreakProvider` is skipped for `cooldownSec`.
##
## Used on the daemon loop only: routing hooks run in the session coroutines,
## and the IPC server and HTTP gateway run on the same loop. The clock is
## injectable for tests.

import std/[algorithm, json, os, tables, times]
import ../core/providers/smart_routing
import ../ports/ipc
import ../ports/provider

const
  RecentRouteSampleLimit* = 32
  DefaultRecentRouteSampleTtlSec* = 6 * 60 * 60
  DefaultProviderCooldownSec* = 10 * 60

type
  RouteSample = object
    ok: bool
    elapsedMs: int
    recordedAtUnix: int64

  Clock* = proc(): int64 {.gcsafe, nimcall, raises: [].}

  RouteHealth* = ref object
    path: string                 ## "" keeps everything in memory
    sampleTtlSec: int64
    cooldownSec: int64
    clock: Clock
    choiceCounts: Table[string, int]
    callCounts: Table[string, int]
    okCounts: Table[string, int]
    errCounts: Table[string, int]
    latencyTotalsMs: Table[string, int64]
    recentSamples: Table[string, seq[RouteSample]]
    cooldownUntil: Table[string, int64]

proc systemClock(): int64 {.gcsafe, nimcall, raises: [].} = getTime().toUnix()

proc newRouteHealth*(path: string;
                     sampleTtlSec = int64(DefaultRecentRouteSampleTtlSec);
                     cooldownSec = int64(DefaultProviderCooldownSec);
                     clock: Clock = nil): RouteHealth =
  RouteHealth(path: path,
              sampleTtlSec: if sampleTtlSec > 0: sampleTtlSec
                            else: DefaultRecentRouteSampleTtlSec,
              cooldownSec: if cooldownSec > 0: cooldownSec
                           else: DefaultProviderCooldownSec,
              clock: if clock != nil: clock else: systemClock)

proc now(h: RouteHealth): int64 = h.clock()

# ── pruning and persistence ───────────────────────────────────────────────────

proc pruneSamples(h: RouteHealth) =
  let nowSec = h.now()
  for route, samples in h.recentSamples.mpairs:
    var kept: seq[RouteSample] = @[]
    for sample in samples:
      if sample.recordedAtUnix > 0 and nowSec - sample.recordedAtUnix <= h.sampleTtlSec:
        kept.add(sample)
    if kept.len > RecentRouteSampleLimit:
      kept = kept[(kept.len - RecentRouteSampleLimit) .. ^1]
    samples = kept

proc pruneCooldowns(h: RouteHealth) =
  let nowSec = h.now()
  var expired: seq[string] = @[]
  for providerName, untilUnix in h.cooldownUntil:
    if untilUnix <= nowSec:
      expired.add(providerName)
  for providerName in expired:
    h.cooldownUntil.del(providerName)

proc save(h: RouteHealth) =
  ## Best effort: losing the file only costs the memory of recent failures.
  if h.path.len == 0:
    return
  try:
    h.pruneSamples()
    createDir(parentDir(h.path))
    var routes = newJArray()
    for route, samples in h.recentSamples:
      if samples.len == 0:
        continue
      var sampleData = newJArray()
      for sample in samples:
        sampleData.add(%*{
          "ok": sample.ok,
          "elapsed_ms": sample.elapsedMs,
          "recorded_at": sample.recordedAtUnix,
        })
      routes.add(%*{"route": route, "samples": sampleData})
    var cooldowns = newJArray()
    for providerName, untilUnix in h.cooldownUntil:
      cooldowns.add(%*{"provider": providerName, "until_unix": untilUnix})
    writeFile(h.path, $(%*{
      "saved_at": h.now(),
      "routes": routes,
      "provider_cooldowns": cooldowns,
    }))
  except CatchableError:
    discard

proc load*(h: RouteHealth) =
  ## Restores the recent samples and cooldowns saved by an earlier run. A
  ## missing or unreadable file starts empty.
  if h.path.len == 0 or not fileExists(h.path):
    return
  try:
    let parsed = parseJson(readFile(h.path))
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
      h.recentSamples[route] = samples
    h.pruneSamples()
    for cooldownNode in parsed{"provider_cooldowns"}:
      let providerName = cooldownNode{"provider"}.getStr("")
      let untilUnix = cooldownNode{"until_unix"}.getBiggestInt(0)
      if providerName.len > 0 and untilUnix > 0:
        h.cooldownUntil[providerName] = untilUnix
    h.pruneCooldowns()
  except CatchableError:
    discard

# ── recording ─────────────────────────────────────────────────────────────────

proc feedback*(h: RouteHealth): seq[RouteFeedback] {.gcsafe, raises: [].}

proc refreshCooldowns(h: RouteHealth) =
  h.pruneCooldowns()
  let nowSec = h.now()
  for provider in aggregateProviderFeedback(h.feedback()):
    if provider.shouldCircuitBreakProvider and
       h.cooldownUntil.getOrDefault(provider.providerName) <= nowSec:
      h.cooldownUntil[provider.providerName] = nowSec + h.cooldownSec
  h.save()

proc recordChoice*(h: RouteHealth; selection: ProviderSelection) =
  let key = selection.formatSelection
  h.choiceCounts[key] = h.choiceCounts.getOrDefault(key) + 1

proc recordResult*(h: RouteHealth; selection: ProviderSelection;
                   elapsedMs: int64; ok: bool) =
  let key = selection.formatSelection
  h.callCounts[key] = h.callCounts.getOrDefault(key) + 1
  h.latencyTotalsMs[key] = h.latencyTotalsMs.getOrDefault(key) + elapsedMs
  var samples = h.recentSamples.getOrDefault(key)
  samples.add(RouteSample(
    ok: ok,
    elapsedMs: if elapsedMs > 0: int(elapsedMs) else: 0,
    recordedAtUnix: h.now(),
  ))
  if samples.len > RecentRouteSampleLimit:
    samples = samples[(samples.len - RecentRouteSampleLimit) .. ^1]
  h.recentSamples[key] = samples
  if ok:
    h.okCounts[key] = h.okCounts.getOrDefault(key) + 1
  else:
    h.errCounts[key] = h.errCounts.getOrDefault(key) + 1
  h.refreshCooldowns()

# ── reading ───────────────────────────────────────────────────────────────────

func summarize(route: string; samples: seq[RouteSample]): RouteFeedback =
  var okCalls, errCalls, totalLatency = 0
  for sample in samples:
    totalLatency += sample.elapsedMs
    if sample.ok: inc okCalls else: inc errCalls
  RouteFeedback(route: route, calls: samples.len, okCalls: okCalls,
                errCalls: errCalls,
                avgLatencyMs: if samples.len > 0: totalLatency div samples.len else: 0)

proc feedback*(h: RouteHealth): seq[RouteFeedback] {.gcsafe, raises: [].} =
  ## Recent results per route, for smart routing.
  h.pruneSamples()
  for route, samples in h.recentSamples:
    if samples.len > 0:
      result.add summarize(route, samples)

proc cooldowns*(h: RouteHealth): seq[ProviderCooldown] =
  ## Providers in cooldown now, for smart routing.
  h.pruneCooldowns()
  let nowSec = h.now()
  for providerName, untilUnix in h.cooldownUntil:
    if untilUnix > nowSec:
      result.add(ProviderCooldown(providerName: providerName, untilUnix: untilUnix))

func byCountThenName(a, b: (string, int)): int =
  if a[1] != b[1]: cmp(b[1], a[1]) else: cmp(a[0], b[0])

proc topRouteCounts*(h: RouteHealth; limit = 5): seq[RouteCount] =
  var items: seq[(string, int)] = @[]
  for route, count in h.choiceCounts:
    items.add((route, count))
  items.sort(byCountThenName)
  for i in 0 ..< min(limit, items.len):
    result.add(RouteCount(route: items[i][0], count: items[i][1]))

proc topRouteMetrics*(h: RouteHealth; limit = 5): seq[RouteMetric] =
  var items: seq[(string, int)] = @[]
  for route, calls in h.callCounts:
    items.add((route, calls))
  items.sort(byCountThenName)
  for i in 0 ..< min(limit, items.len):
    let (route, calls) = items[i]
    let totalLatency = h.latencyTotalsMs.getOrDefault(route)
    result.add(RouteMetric(
      route: route,
      calls: calls,
      okCalls: h.okCounts.getOrDefault(route),
      errCalls: h.errCounts.getOrDefault(route),
      avgLatencyMs: if calls > 0: int(totalLatency div calls) else: 0,
    ))

proc topRecentRouteMetrics*(h: RouteHealth; limit = 5): seq[RouteMetric] =
  var recent = h.feedback()
  recent.sort(proc(a, b: RouteFeedback): int =
    byCountThenName((a.route, a.calls), (b.route, b.calls)))
  for i in 0 ..< min(limit, recent.len):
    let f = recent[i]
    result.add(RouteMetric(route: f.route, calls: f.calls, okCalls: f.okCalls,
                           errCalls: f.errCalls, avgLatencyMs: f.avgLatencyMs))

proc topRecentProviderMetrics*(h: RouteHealth; limit = 5): seq[ProviderMetric] =
  var items = aggregateProviderFeedback(h.feedback())
  items.sort(proc(a, b: ProviderFeedback): int =
    byCountThenName((a.providerName, a.calls), (b.providerName, b.calls)))
  for i in 0 ..< min(limit, items.len):
    result.add(ProviderMetric(
      providerName: items[i].providerName,
      calls: items[i].calls,
      okCalls: items[i].okCalls,
      errCalls: items[i].errCalls,
      avgLatencyMs: items[i].avgLatencyMs,
    ))

proc activeCooldownLabels*(h: RouteHealth; limit = 5): seq[string] =
  ## "provider (time left)", soonest to end first, for the status views.
  let nowSec = h.now()
  var items: seq[(string, int64)] = @[]
  for cooldown in h.cooldowns():
    items.add((cooldown.providerName, cooldown.untilUnix))
  items.sort(proc(a, b: (string, int64)): int =
    if a[1] != b[1]: cmp(a[1], b[1]) else: cmp(a[0], b[0]))
  for i in 0 ..< min(limit, items.len):
    let remaining = max(0'i64, items[i][1] - nowSec)
    result.add(items[i][0] & " (" & relativeAgeText(remaining) & ")")
