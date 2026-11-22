## RouteHealthStore — where route health survives a restart.
##
## `app/route_health` keeps the counters, the TTL and the cooldown policy; it
## hands the recent samples and the active cooldowns to this port as plain
## data. Every operation returns `Result`: I/O and decoding failures stay in
## the adapter.

import ../core/pipeops
import ../core/providers/smart_routing

type
  RouteSampleRecord* = object
    ok*:             bool
    elapsedMs*:      int
    recordedAtUnix*: int64

  RouteSamples* = object
    route*:   string
    samples*: seq[RouteSampleRecord]

  RouteHealthSnapshot* = object
    routes*:    seq[RouteSamples]
    cooldowns*: seq[ProviderCooldown]
    savedAt*:   int64

  RouteHealthStore* = object
    load*: proc(): Result[RouteHealthSnapshot, string] {.gcsafe, raises: [].}
      ## Nothing saved yet is an empty snapshot, not an error.
    save*: proc(snapshot: RouteHealthSnapshot): Result[void, string] {.gcsafe, raises: [].}

func hasRouteHealthStore*(store: RouteHealthStore): bool =
  store.load != nil and store.save != nil
