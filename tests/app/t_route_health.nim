## Route health: per-route counters, recent samples kept within a TTL and
## persisted across restarts, and provider cooldowns opened by a failing
## provider. Driven by an injected clock; no daemon.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/ports/route_health_store
import donkey/core/providers/smart_routing
import donkey/app/route_health

var gNow = 1_000_000'i64
proc fakeClock(): int64 {.gcsafe, nimcall, raises: [].} = gNow

func sel(provider, model: string): ProviderSelection =
  ProviderSelection(providerName: provider, modelName: model)

var gSaved {.threadvar.}: RouteHealthSnapshot

proc memoryStore(): RouteHealthStore =
  RouteHealthStore(
    load: proc(): Result[RouteHealthSnapshot, string] {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: ok(gSaved),
    save: proc(snapshot: RouteHealthSnapshot): Result[void, string] {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: gSaved = snapshot
      ok())

proc failingStore(): RouteHealthStore =
  RouteHealthStore(
    load: proc(): Result[RouteHealthSnapshot, string] {.gcsafe, raises: [].} =
      err("disk gone"),
    save: proc(snapshot: RouteHealthSnapshot): Result[void, string] {.gcsafe, raises: [].} =
      err("disk gone"))

proc fresh(ttlSec = 3600'i64; cooldownSec = 600'i64): RouteHealth =
  newRouteHealth(RouteHealthStore(), sampleTtlSec = ttlSec,
                 cooldownSec = cooldownSec, clock = fakeClock)

proc runTests*() =
  suite "route health":
    setup:
      gNow = 1_000_000

    test "choices and results are counted per route":
      let h = fresh()
      h.recordChoice(sel("openrouter", "a"))
      h.recordChoice(sel("openrouter", "a"))
      h.recordResult(sel("openrouter", "a"), 200, ok = true)
      h.recordResult(sel("openrouter", "a"), 400, ok = false)
      check h.topRouteCounts()[0].route == "openrouter/a"
      check h.topRouteCounts()[0].count == 2
      let metric = h.topRouteMetrics()[0]
      check (metric.calls, metric.okCalls, metric.errCalls) == (2, 1, 1)
      check metric.avgLatencyMs == 300

    test "recent samples expire after the TTL":
      let h = fresh(ttlSec = 60)
      h.recordResult(sel("anthropic", "x"), 100, ok = true)
      check h.feedback().len == 1
      gNow += 61
      check h.feedback().len == 0
      check h.topRecentRouteMetrics().len == 0

    test "a provider that keeps failing goes into cooldown, and leaves it":
      let h = fresh(cooldownSec = 600)
      for _ in 0 ..< 4:
        h.recordResult(sel("gemini", "g"), 100, ok = false)
      check h.cooldowns().len == 1
      check h.cooldowns()[0].providerName == "gemini"
      check h.activeCooldownLabels()[0].startsWith("gemini (")
      gNow += 601
      check h.cooldowns().len == 0

    test "a store that fails does not stop recording":
      ## Persistence is best effort: routing goes on without it.
      let h = newRouteHealth(failingStore(), clock = fakeClock)
      h.load()
      h.recordResult(sel("openrouter", "a"), 100, ok = true)
      check h.feedback().len == 1

    test "samples and cooldowns survive a restart":
      gSaved = RouteHealthSnapshot()
      block:
        let h = newRouteHealth(memoryStore(), clock = fakeClock)
        for _ in 0 ..< 4:
          h.recordResult(sel("gemini", "g"), 100, ok = false)
        h.recordResult(sel("openrouter", "a"), 50, ok = true)
      let reloaded = newRouteHealth(memoryStore(), clock = fakeClock)
      reloaded.load()
      check reloaded.feedback().len == 2
      check reloaded.cooldowns().len == 1
      check reloaded.topRecentProviderMetrics().len == 2


when isMainModule:
  runTests()
