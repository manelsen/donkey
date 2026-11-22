## Route health persisted to a JSON file (`state/route_health.json`), behind
## RouteHealthStore. The format is the one the daemon wrote before the port
## existed, so a saved state still loads.

import std/[json, os]
import ../../core/pipeops
import ../../core/providers/smart_routing
import ../../ports/route_health_store

proc encode(snapshot: RouteHealthSnapshot): JsonNode =
  var routes = newJArray()
  for route in snapshot.routes:
    if route.samples.len == 0:
      continue
    var samples = newJArray()
    for sample in route.samples:
      samples.add(%*{"ok": sample.ok, "elapsed_ms": sample.elapsedMs,
                     "recorded_at": sample.recordedAtUnix})
    routes.add(%*{"route": route.route, "samples": samples})
  var cooldowns = newJArray()
  for cooldown in snapshot.cooldowns:
    cooldowns.add(%*{"provider": cooldown.providerName,
                     "until_unix": cooldown.untilUnix})
  %*{"saved_at": snapshot.savedAt, "routes": routes,
     "provider_cooldowns": cooldowns}

proc decode(node: JsonNode): RouteHealthSnapshot =
  result.savedAt = node{"saved_at"}.getBiggestInt(0)
  for routeNode in node{"routes"}:
    let route = routeNode{"route"}.getStr("")
    if route.len == 0:
      continue
    var entry = RouteSamples(route: route)
    for sampleNode in routeNode{"samples"}:
      entry.samples.add(RouteSampleRecord(
        ok: sampleNode{"ok"}.getBool(false),
        elapsedMs: sampleNode{"elapsed_ms"}.getInt(0),
        recordedAtUnix: sampleNode{"recorded_at"}.getBiggestInt(0)))
    result.routes.add(entry)
  for cooldownNode in node{"provider_cooldowns"}:
    let providerName = cooldownNode{"provider"}.getStr("")
    let untilUnix = cooldownNode{"until_unix"}.getBiggestInt(0)
    if providerName.len > 0 and untilUnix > 0:
      result.cooldowns.add(ProviderCooldown(providerName: providerName,
                                            untilUnix: untilUnix))

proc routeHealthFileStore*(path: string): RouteHealthStore =
  RouteHealthStore(
    load: proc(): Result[RouteHealthSnapshot, string] {.gcsafe, raises: [].} =
      if not fileExists(path):
        return ok(RouteHealthSnapshot())
      try:
        ok(decode(parseJson(readFile(path))))
      except CatchableError as e:
        err("route health " & path & ": " & e.msg),
    save: proc(snapshot: RouteHealthSnapshot): Result[void, string] {.gcsafe, raises: [].} =
      try:
        createDir(parentDir(path))
        writeFile(path, $encode(snapshot))
        ok()
      except CatchableError as e:
        err("route health " & path & ": " & e.msg),
  )
