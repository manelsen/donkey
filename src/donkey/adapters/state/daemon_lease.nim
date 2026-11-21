## daemon_lease.nim — single-owner lease for the daemon state directory.
##
## The daemon writes the session registry, the delivery ledger and the
## approval/pairing stores. Two daemons on the same directory can interleave
## those writes, so startup acquires a lease first. A lease left behind by a
## dead process is taken over; a lease from another host is left alone.

import std/[options, os]
when defined(posix):
  import std/posix
import ../../core/lease_pure
import ../../core/pipeops

type
  DaemonLease* = object
    path*:  string
    owner*: LeaseRecord
    held*:  bool

const DaemonLeaseFileName* = "daemon.lease"

when defined(posix):
  proc cKill(pid: cint; sig: cint): cint {.
    importc: "kill", header: "<signal.h>".}

proc pidAlive*(pid: int): bool {.gcsafe, raises: [].} =
  ## `kill(pid, 0)` only checks for the process; EPERM still means it exists.
  when defined(posix):
    if pid <= 0:
      return false
    if cKill(cint(pid), 0) == 0:
      return true
    errno == EPERM
  else:
    ## Without a portable check, assume the owner is alive rather than risk a
    ## second daemon on the same state.
    true

func leasePath*(stateDir: string): string =
  stateDir / DaemonLeaseFileName

proc daemonHost*(): string {.gcsafe, raises: [].} =
  ## The host recorded in the lease. Empty when it cannot be determined; the
  ## stale decision then falls back to the pid.
  when defined(posix):
    var buf: array[256, char]
    if gethostname(cast[cstring](addr buf[0]), buf.len.cint) == 0:
      result = $cast[cstring](addr buf[0])
  else:
    ""

proc acquireDaemonLease*(stateDir: string; nowMs = epochMs();
                         host = daemonHost();
                         ownPid = getCurrentProcessId()):
                           Result[DaemonLease, string] {.gcsafe, raises: [].} =
  ## Creates the state directory if needed and takes the lease, unless a live
  ## owner holds it. A corrupt lease is replaced: it cannot name a live owner.
  if stateDir.len == 0:
    return err("state directory is empty")
  try:
    createDir(stateDir)
    let path = leasePath(stateDir)
    if fileExists(path):
      let existing = decodeLease(readFile(path))
      if existing.isSome and
         not leaseIsStale(existing.get(), host, pidAlive(existing.get().pid)):
        return err("another daemon is already running (pid " &
                   $existing.get().pid & " on " & existing.get().host & ")")
    let owner = LeaseRecord(pid: ownPid, host: host, startedAtMs: nowMs)
    let tmp = path & ".tmp"
    writeFile(tmp, encodeLease(owner))
    moveFile(tmp, path)
    when defined(posix):
      discard posix.chmod(path.cstring, posix.Mode(0o600))
    ok(DaemonLease(path: path, owner: owner, held: true))
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("acquire daemon lease: " & e.msg)

proc releaseDaemonLease*(lease: var DaemonLease) {.gcsafe, raises: [].} =
  ## Removes the lease only if it is still ours. A successor that took over
  ## after our process was presumed dead keeps its file.
  if not lease.held:
    return
  lease.held = false
  try:
    if not fileExists(lease.path):
      return
    let current = decodeLease(readFile(lease.path))
    if current.isSome and current.get().pid == lease.owner.pid and
       current.get().host == lease.owner.host:
      removeFile(lease.path)
  except CatchableError:
    discard
