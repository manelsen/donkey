## The route-health file: a snapshot written and read back, nothing saved
## yet, and a file that cannot be read.

import std/[os, unittest]
import donkey/core/pipeops
import donkey/core/providers/smart_routing
import donkey/ports/route_health_store
import donkey/adapters/state/route_health_file

proc scratchPath(name: string): string =
  getTempDir() / ("donkey_rh_file_" & name & "_" & $getCurrentProcessId()) / "route_health.json"

proc runTests*() =
  suite "route health file":
    test "a snapshot is written and read back":
      let path = scratchPath("roundtrip")
      defer: removeDir(parentDir(path))
      let store = routeHealthFileStore(path)
      let snapshot = RouteHealthSnapshot(
        routes: @[RouteSamples(route: "openrouter/a", samples: @[
          RouteSampleRecord(ok: true, elapsedMs: 120, recordedAtUnix: 1_000),
          RouteSampleRecord(ok: false, elapsedMs: 900, recordedAtUnix: 1_010)])],
        cooldowns: @[ProviderCooldown(providerName: "gemini", untilUnix: 2_000)],
        savedAt: 1_020)
      check store.save(snapshot).isOk
      check store.load().get == snapshot

    test "nothing saved yet is an empty snapshot":
      let path = scratchPath("missing")
      check routeHealthFileStore(path).load().get == RouteHealthSnapshot()

    test "a file that cannot be decoded is an error":
      let path = scratchPath("broken")
      defer: removeDir(parentDir(path))
      createDir(parentDir(path))
      writeFile(path, "{not json")
      check routeHealthFileStore(path).load().isErr

when isMainModule:
  runTests()
