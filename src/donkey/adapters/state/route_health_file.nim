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

func arrayAt(node: JsonNode; key: string): Result[seq[JsonNode], string] =
  ## The array under `key`; absent is empty, any other kind is an error.
  ## Iterating a non-array JsonNode fails with a Defect, not an exception.
  let value = node{key}
  if value == nil: return ok(newSeq[JsonNode]())
  if value.kind != JArray: return err("`" & key & "` is not an array")
  ok(value.elems)

func decode(node: JsonNode): Result[RouteHealthSnapshot, string] =
  ## A snapshot from the saved document, checking each level's shape first.
  if node.kind != JObject:
    return err("the document is not an object")
  var snapshot = RouteHealthSnapshot(savedAt: node{"saved_at"}.getBiggestInt(0))
  for routeNode in ? node.arrayAt("routes"):
    if routeNode.kind != JObject:
      return err("a route entry is not an object")
    let route = routeNode{"route"}.getStr("")
    if route.len == 0:
      continue
    var entry = RouteSamples(route: route)
    for sampleNode in ? routeNode.arrayAt("samples"):
      if sampleNode.kind != JObject:
        return err("a sample is not an object")
      entry.samples.add(RouteSampleRecord(
        ok: sampleNode{"ok"}.getBool(false),
        elapsedMs: sampleNode{"elapsed_ms"}.getInt(0),
        recordedAtUnix: sampleNode{"recorded_at"}.getBiggestInt(0)))
    snapshot.routes.add(entry)
  for cooldownNode in ? node.arrayAt("provider_cooldowns"):
    if cooldownNode.kind != JObject:
      return err("a cooldown is not an object")
    let providerName = cooldownNode{"provider"}.getStr("")
    let untilUnix = cooldownNode{"until_unix"}.getBiggestInt(0)
    if providerName.len > 0 and untilUnix > 0:
      snapshot.cooldowns.add(ProviderCooldown(providerName: providerName,
                                              untilUnix: untilUnix))
  ok(snapshot)

proc routeHealthFileStore*(path: string): RouteHealthStore =
  RouteHealthStore(
    load: proc(): Result[RouteHealthSnapshot, string] {.gcsafe, raises: [].} =
      if not fileExists(path):
        return ok(RouteHealthSnapshot())
      let parsed =
        try: parseJson(readFile(path))
        except CatchableError as e:
          return err("route health " & path & ": " & e.msg)
      decode(parsed).mapErr(proc(e: string): string = "route health " & path & ": " & e),
    save: proc(snapshot: RouteHealthSnapshot): Result[void, string] {.gcsafe, raises: [].} =
      try:
        createDir(parentDir(path))
        writeFile(path, $encode(snapshot))
        ok()
      except CatchableError as e:
        err("route health " & path & ": " & e.msg),
  )
