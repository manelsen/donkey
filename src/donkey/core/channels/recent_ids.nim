## RecentIds — the ids of inbound events already handled, so a redelivered
## event does not run a command or a turn twice. Bounded twice: by age (`ttl`)
## and by count (`capacity`, oldest forgotten first). Channels redeliver within
## minutes (a Slack retry after a lost ack, a Discord gateway RESUME replay,
## a startup backfill overlapping the live stream), so a short window does.

import std/tables

type RecentIds* = object
  ttlSec:   float
  capacity: int
  seenAt:   Table[string, float]

func initRecentIds*(ttlSec: float; capacity: int): RecentIds =
  RecentIds(ttlSec: ttlSec, capacity: max(1, capacity))

func seenBefore*(r: var RecentIds; id: string; nowSec: float): bool =
  ## True when `id` was recorded within the ttl; otherwise records it now and
  ## returns false. An empty id cannot be told apart and is never a duplicate.
  if id.len == 0:
    return false
  var expired: seq[string]
  for k, at in r.seenAt:
    if nowSec - at > r.ttlSec:
      expired.add k
  for k in expired:
    r.seenAt.del k
  if id in r.seenAt:
    return true
  if r.seenAt.len >= r.capacity:
    var oldestKey = ""
    var oldestAt = nowSec
    for k, at in r.seenAt:
      if oldestKey.len == 0 or at < oldestAt:
        oldestAt = at
        oldestKey = k
    r.seenAt.del oldestKey
  r.seenAt[id] = nowSec
  false
