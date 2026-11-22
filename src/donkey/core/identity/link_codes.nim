## Shared link-code table for cross-channel identity linking.
##
## A code minted by `/mycode` on one channel must be redeemable by
## `/continue` on any other. Each channel adapter builds its own
## `IdentityResolver` over the same identity file, so the pending codes cannot
## live on the resolver instance: they live here, one table per identity file,
## shared by every resolver built from that path in the same process.
##
## The registry and each table are guarded by a `Lock` because resolvers from
## different channels (or threads) reach the same service. A code is removed
## on redemption, preserving single use, and expiry is checked on access.
##
## Pending codes are intentionally not persisted: the identity file format is
## unchanged, and a code only has to survive the process that minted it.

import std/[locks, options, os, random, tables, times]
import ../types
import ../../ports/link_codes

const
  LinkCodeAlpha*  = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  LinkCodeLen*    = 6
  LinkCodeTtlSec* = 600  ## 10 minutes

type
  LinkCodeEntry = object
    userId: UserId
    expiry: Time

  LinkCodeService* = ref object
    ## Pending codes for the identities persisted in one identity file.
    lock:    Lock
    entries: Table[string, LinkCodeEntry]

proc newLinkCodeService*(): LinkCodeService =
  new(result)
  initLock(result.lock)
  result.entries = initTable[string, LinkCodeEntry]()

proc mint*(s: LinkCodeService; userId: UserId;
           now = getTime(); ttlSec = LinkCodeTtlSec): string =
  ## Mints a fresh one-time code for `userId`. A collision overwrites the
  ## older code, as the per-resolver table did.
  withLock s.lock:
    randomize()
    result = newString(LinkCodeLen)
    for i in 0..<LinkCodeLen:
      result[i] = LinkCodeAlpha[rand(LinkCodeAlpha.len - 1)]
    s.entries[result] = LinkCodeEntry(
      userId: userId,
      expiry: now + initDuration(seconds = ttlSec),
    )

proc peek*(s: LinkCodeService; code: string;
           now = getTime()): Option[UserId] =
  ## Returns the target for a valid code without consuming it. Expired codes
  ## are dropped so the table does not grow without bound.
  withLock s.lock:
    if code notin s.entries:
      return none(UserId)
    let entry = s.entries[code]
    if now > entry.expiry:
      s.entries.del(code)
      return none(UserId)
    result = some(entry.userId)

proc redeem*(s: LinkCodeService; code: string;
             now = getTime()): Option[UserId] =
  ## Consumes a valid code and returns its target. Single use: the entry is
  ## removed on the first redemption attempt, including an expired one.
  withLock s.lock:
    if code notin s.entries:
      return none(UserId)
    let entry = s.entries[code]
    s.entries.del(code)
    if now > entry.expiry:
      return none(UserId)
    result = some(entry.userId)

var
  gRegistryLock: Lock
  gServices:     Table[string, LinkCodeService]

initLock(gRegistryLock)  ## module init runs before any resolver is built

proc serviceKey(path: string): string {.gcsafe.} =
  ## Canonical enough to make `ids.tsv` and `/home/u/ids.tsv` the same table
  ## without requiring the file to exist yet (resolvers may be built before
  ## the first save).
  try:
    result = absolutePath(path)
  except CatchableError:
    result = path

proc sharedLinkCodeService*(path: string): LinkCodeService {.gcsafe.} =
  ## Returns the process-wide service for `path`, creating it on first use.
  ## Every resolver built from the same identity file shares this table, so a
  ## code minted on one channel is redeemable on another.
  ##
  ## The registry is global by design (one table per identity file); the cast
  ## mirrors `app/metrics.nim`: every access happens under `gRegistryLock`.
  let key = serviceKey(path)
  {.cast(gcsafe).}:
    withLock gRegistryLock:
      if key notin gServices:
        gServices[key] = newLinkCodeService()
      result = gServices[key]

proc linkCodePort*(s: LinkCodeService): LinkCodePort {.gcsafe.} =
  ## The service as the cross-channel seam every channel asks for. It carries
  ## no channel knowledge, so any channel's port lands on the same table.
  LinkCodePort(
    mint:   proc(userId: UserId): string {.gcsafe.} =
      s.mint(userId),
    peek:   proc(code: string): Option[UserId] {.gcsafe.} =
      s.peek(code),
    redeem: proc(code: string): Option[UserId] {.gcsafe.} =
      s.redeem(code),
  )
