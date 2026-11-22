## ThreadOwner — a check for state kept thread-local because one thread is
## meant to use it (the daemon loop).
##
## A `{.threadvar.}` is gcsafe, but the compiler cannot prove that only one
## thread uses it: another thread would silently read its own empty copy.
## The first thread to call `isOwner` becomes the owner; any later call from
## another thread is counted and logged, so the wrong assumption is loud.
## The owner id and the count are atomics: a global ThreadOwner holds no GC
## memory and is itself gcsafe.

import std/atomics
import ../core/log

type ThreadOwner* = object
  id: Atomic[int]       ## 0 until claimed; thread ids start at 1
  foreign: Atomic[int]  ## uses from other threads

proc isOwner*(o: var ThreadOwner; what = "thread-local state"): bool =
  ## True on the owning thread (claiming it on first use); otherwise logs
  ## and returns false.
  let me = getThreadId()
  var expected = 0
  if o.id.compareExchange(expected, me) or expected == me:
    return true
  discard o.foreign.fetchAdd(1)
  newLogger("thread_owner").error(what & " used from thread " & $me &
    ", but it belongs to thread " & $expected)
  false

proc foreignUses*(o: var ThreadOwner): int =
  o.foreign.load()
