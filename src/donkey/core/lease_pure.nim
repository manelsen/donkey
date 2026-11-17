## lease_pure.nim — ownership records for a state directory.
##
## A lease says "this pid on this host owns the state directory". The decision
## to take one over is pure: the caller supplies whether the recorded pid is
## alive, because checking it needs the OS.
##
## No I/O.

import std/[json, options]

type
  LeaseRecord* = object
    pid*:         int
    host*:        string
    startedAtMs*: int64

func encodeLease*(record: LeaseRecord): string =
  $(%* {
    "pid": record.pid,
    "host": record.host,
    "startedAtMs": record.startedAtMs,
  })

proc decodeLease*(raw: string): Option[LeaseRecord] =
  ## A lease that cannot be decoded is `none`: it cannot identify a live
  ## owner, so the caller may replace it.
  let node = try:
    parseJson(raw)
  except CatchableError:
    return none(LeaseRecord)
  if node.kind != JObject:
    return none(LeaseRecord)
  let pid = node.getOrDefault("pid")
  if pid.isNil or pid.kind != JInt or pid.getInt() <= 0:
    return none(LeaseRecord)
  let started = node.getOrDefault("startedAtMs")
  some(LeaseRecord(
    pid:         pid.getInt(),
    host:        node.getOrDefault("host").getStr(""),
    startedAtMs: if started.kind == JInt: started.getInt() else: 0'i64,
  ))

func leaseIsStale*(record: LeaseRecord; host: string; pidAlive: bool): bool =
  ## Same host: the pid decides. Another host: we cannot check the pid, so the
  ## lease is treated as live — a shared filesystem is not a reason to start a
  ## second daemon.
  if record.host.len > 0 and record.host != host:
    return false
  not pidAlive
