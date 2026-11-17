## Daemon lease tests.
##
## The lease is what stops two daemons from writing the same state directory.
## A lease left by a dead process is taken over; a live one blocks startup; a
## lease from another host cannot be verified and is treated as live.

import std/[json, options, os, strutils, unittest]
import donkey/adapters/state/daemon_lease
import donkey/core/lease_pure
import donkey/core/pipeops

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_lease_" & tag & "_" & $getCurrentProcessId())
  try:
    removeDir(result)
  except CatchableError:
    discard
  createDir(result)

proc cleanup(dir: string) =
  try:
    removeDir(dir)
  except CatchableError:
    discard

proc writeLease(path: string; pid: int; host: string) =
  createDir(parentDir(path))
  writeFile(path, $(%* {"pid": pid, "host": host, "startedAtMs": 1}))

suite "lease purity":

  test "a dead pid on the same host is stale":
    check leaseIsStale(LeaseRecord(pid: 10, host: "h"), "h", pidAlive = false)

  test "a live pid on the same host is not stale":
    check not leaseIsStale(LeaseRecord(pid: 10, host: "h"), "h", pidAlive = true)

  test "a lease from another host is never stale":
    check not leaseIsStale(LeaseRecord(pid: 10, host: "other"), "h", pidAlive = false)

  test "a record without a host is judged by its pid":
    check leaseIsStale(LeaseRecord(pid: 10, host: ""), "h", pidAlive = false)

  test "round-trips through JSON":
    let record = LeaseRecord(pid: 42, host: "h", startedAtMs: 99)
    check decodeLease(encodeLease(record)).get() == record

  test "a corrupt record decodes to none":
    check decodeLease("not json").isNone
    check decodeLease("{}").isNone

suite "daemon lease":

  test "a fresh state directory acquires the lease":
    let dir = freshDir("fresh")
    defer: cleanup(dir)
    let lease = acquireDaemonLease(dir, nowMs = 100)
    check lease.isOk
    check lease.get().held
    check fileExists(leasePath(dir))

  test "a live lease blocks a second daemon":
    let dir = freshDir("live")
    defer: cleanup(dir)
    let first = acquireDaemonLease(dir)
    check first.isOk
    let second = acquireDaemonLease(dir)
    check second.isErr
    check second.error.contains("already running")
    var released = first.get()
    releaseDaemonLease(released)

  test "releasing removes the lease and allows a new acquire":
    let dir = freshDir("release")
    defer: cleanup(dir)
    var lease = acquireDaemonLease(dir).get()
    releaseDaemonLease(lease)
    check not lease.held
    check not fileExists(leasePath(dir))
    check acquireDaemonLease(dir).isOk

  test "a lease from a dead pid is taken over":
    let dir = freshDir("stale")
    defer: cleanup(dir)
    writeLease(leasePath(dir), pid = 2_000_000_000, host = daemonHost())
    let lease = acquireDaemonLease(dir, nowMs = 500)
    check lease.isOk
    let stored = decodeLease(readFile(leasePath(dir))).get()
    check stored.pid == getCurrentProcessId()

  test "a lease from another host is not taken over":
    let dir = freshDir("otherhost")
    defer: cleanup(dir)
    writeLease(leasePath(dir), pid = 2_000_000_000, host = "some-other-host")
    check acquireDaemonLease(dir).isErr

  test "release does not remove a successor's lease":
    let dir = freshDir("successor")
    defer: cleanup(dir)
    var lease = acquireDaemonLease(dir).get()
    writeLease(leasePath(dir), pid = 2_000_000_000, host = daemonHost())
    releaseDaemonLease(lease)
    check fileExists(leasePath(dir))

  test "a corrupt lease does not block startup":
    let dir = freshDir("corrupt")
    defer: cleanup(dir)
    writeFile(leasePath(dir), "garbage")
    check acquireDaemonLease(dir).isOk
