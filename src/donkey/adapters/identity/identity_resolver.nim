## IdentityResolver — maps (ChannelKind, raw_channel_user_id) → UserId.
##
## Persistence: tab-separated file, one mapping per line:
##   telegram:12345\tuuid\n
##   discord:678901234\tuuid\n
##
## Link codes enable cross-channel identity linking (/mycode → /continue):
##   User on Telegram calls /mycode → gets 6-char code, valid 10 minutes.
##   User on Discord calls /continue <code> → their Discord ID is mapped
##   to the same UUID as the Telegram user.

import std/[options, os, random, strutils, tables]
import ../../app/inbound_gate
import ../../core/identity/link_codes
import ../../core/pipeops
import ../../core/types
import ../../ports/link_codes

type
  IdentityResolver* = ref object
    store*:       Table[string, UserId]       ## "kind:rawId" → uuid
    reverseMap*:  Table[string, seq[string]]  ## string(uuid) → seq["kind:rawId"]
    path*:        string
    linkCodes*:   LinkCodeService             ## shared per identity file

func channelKey*(kind: ChannelKind; rawId: string): string =
  ## Storage key: "telegram:12345" or "discord:678901234".
  $kind & ":" & rawId

proc generateUUID*(): string =
  ## Random UUID v4.
  var b: array[16, byte]
  for i in 0..<16: b[i] = byte(rand(255))
  b[6] = (b[6] and 0x0F) or 0x40   ## version 4
  b[8] = (b[8] and 0x3F) or 0x80   ## variant RFC 4122
  result = newStringOfCap(36)
  const hex = "0123456789abcdef"
  for i, v in b:
    if i in [4, 6, 8, 10]: result.add('-')
    result.add(hex[v shr 4])
    result.add(hex[v and 0x0F])

proc save(r: IdentityResolver): Result[void, string] =
  var buf = ""
  for k, v in r.store:
    buf.add(k & '\t' & $v & '\n')
  try:
    createDir(r.path.parentDir())
    let tmp = r.path & ".tmp"
    writeFile(tmp, buf)
    moveFile(tmp, r.path)
    ok()
  except CatchableError as e:
    err("identity store write failed: " & e.msg)

proc loadPersistedMappings(r: IdentityResolver): Result[void, string] =
  ## Rebuilds the in-memory maps from disk. On a read failure the current maps
  ## are kept intact and the error is returned so callers do not mint/save.
  var store = initTable[string, UserId]()
  var reverseMap = initTable[string, seq[string]]()
  if fileExists(r.path):
    try:
      for line in lines(r.path):
        let parts = line.split('\t')
        if parts.len == 2:
          let key = parts[0]
          let uid = UserId(parts[1])
          store[key] = uid
          let us = $uid
          if us notin reverseMap:
            reverseMap[us] = @[]
          reverseMap[us].add(key)
    except CatchableError as e:
      return err("identity store read failed: " & e.msg)
  r.store = store
  r.reverseMap = reverseMap
  ok()

proc newIdentityResolver*(path: string): IdentityResolver =
  result = IdentityResolver(
    path:        path,
    store:       initTable[string, UserId](),
    reverseMap:  initTable[string, seq[string]](),
    linkCodes:   sharedLinkCodeService(path),
  )
  discard result.loadPersistedMappings()

proc removeReverseEntry(r: IdentityResolver; us, key: string) =
  if us in r.reverseMap:
    var idx = -1
    for i, existing in r.reverseMap[us]:
      if existing == key:
        idx = i
        break
    if idx >= 0:
      r.reverseMap[us].delete(idx)
    if r.reverseMap[us].len == 0:
      r.reverseMap.del(us)

proc resolve*(r: IdentityResolver; kind: ChannelKind; rawId: string): UserId =
  ## Returns the stable UserId for (kind, rawId), minting a new UUID on first
  ## contact. Reloads the persisted map before minting so a UUID written by
  ## another process (e.g. `ctl pair approve`) is not clobbered.
  let key = channelKey(kind, rawId)
  if key notin r.store:
    if r.loadPersistedMappings().isErr:
      ## Do not mint or overwrite the file when the persisted map is
      ## unreadable; an empty UserId is rejected by the ingress gates.
      return UserId("")
  if key notin r.store:
    randomize()
    let uid = UserId(generateUUID())
    r.store[key] = uid
    let us = $uid
    if us notin r.reverseMap:
      r.reverseMap[us] = @[]
    r.reverseMap[us].add(key)
    let saved = r.save()
    if saved.isErr:
      ## Keep memory consistent with disk: do not expose an unpersisted UUID.
      r.store.del(key)
      r.removeReverseEntry(us, key)
      return UserId("")
  r.store[key]

proc lookup*(r: IdentityResolver; kind: ChannelKind; rawId: string): Option[UserId] =
  ## Returns the stored mapping for (kind, rawId), if any, without minting a
  ## new identity. Reloads the persisted map first so approvals performed by
  ## `ctl` are visible to a long-running daemon.
  let key = channelKey(kind, rawId)
  if key notin r.store:
    if r.loadPersistedMappings().isErr:
      return none(UserId)
  if key in r.store:
    some(r.store[key])
  else:
    none(UserId)

proc reverseChannel*(r: IdentityResolver; userId: UserId; kind: ChannelKind): string =
  ## Reverse lookup: UserId + channel kind → raw channel user ID.
  ## Returns "" if not found.
  let us = $userId
  if us notin r.reverseMap:
    if r.loadPersistedMappings().isErr:
      return ""
    if us notin r.reverseMap:
      return ""
  let prefix = $kind & ":"
  for key in r.reverseMap[us]:
    if key.startsWith(prefix):
      return key[prefix.len .. ^1]
  ""

proc generateLinkCode*(r: IdentityResolver; userId: UserId): string =
  ## Generates a 6-char one-time code for cross-channel linking.
  ## Valid for 10 minutes. Call this when user types /mycode on any channel.
  ## The table is shared by every resolver built from the same identity file,
  ## so the code is redeemable on another channel in this process.
  r.linkCodes.mint(userId)

proc linkCodePort*(r: IdentityResolver): LinkCodePort {.gcsafe.} =
  ## The cross-channel seam for `/mycode` → `/continue`. It exposes the shared
  ## table, not this resolver, so a code minted on another channel resolves
  ## here.
  let service = r.linkCodes
  LinkCodePort(
    mint:   proc(userId: UserId): string {.gcsafe.} =
      service.mint(userId),
    peek:   proc(code: string): Option[UserId] {.gcsafe.} =
      service.peek(code),
    redeem: proc(code: string): Option[UserId] {.gcsafe.} =
      service.redeem(code),
  )

proc peekLinkCode*(r: IdentityResolver; code: string): Option[UserId] =
  ## Returns the target UUID for a valid, unexpired link code without consuming
  ## it. Used by the DM gate to admit `/continue` from an unknown identity only
  ## when the code points at an already-authorized account.
  r.linkCodes.peek(code)

proc identityGate*(r: IdentityResolver): IdentityGatePort {.gcsafe.} =
  ## Adapter-side port used by the application inbound gate. The business
  ## decision stays in `app/inbound_gate`; this only exposes resolver calls.
  IdentityGatePort(
    lookup: proc(kind: ChannelKind; rawId: string): Option[UserId] {.gcsafe.} =
      r.lookup(kind, rawId),
    resolve: proc(kind: ChannelKind; rawId: string): UserId {.gcsafe.} =
      r.resolve(kind, rawId),
    peekLinkCode: proc(code: string): Option[UserId] {.gcsafe.} =
      r.peekLinkCode(code),
  )

proc consumeLinkCode*(r: IdentityResolver; code: string;
                      kind: ChannelKind; rawId: string): bool =
  ## Links (kind, rawId) to the userId stored under code. Single-use. Saves to disk.
  ## Returns false if code is unknown or expired. The code table is shared by
  ## every resolver built from the same identity file, so a code minted on
  ## another channel is redeemable here.
  let target = r.linkCodes.redeem(code)
  if target.isNone: return false
  let userId = target.get
  let key = channelKey(kind, rawId)
  r.store[key] = userId
  let us = $userId
  if us notin r.reverseMap: r.reverseMap[us] = @[]
  if key notin r.reverseMap[us]:
    r.reverseMap[us].add(key)
  let saved = r.save()
  if saved.isErr:
    r.store.del(key)
    r.removeReverseEntry(us, key)
    return false
  true

proc identityLinkPort*(r: IdentityResolver): IdentityLinkPort {.gcsafe.} =
  ## `/mycode` and `/continue` as the command dispatcher sees them.
  IdentityLinkPort(
    mint: proc(userId: UserId): string {.gcsafe.} =
      r.generateLinkCode(userId),
    link: proc(code: string; channel: ChannelKind; rawId: string): bool {.gcsafe.} =
      r.consumeLinkCode(code, channel, rawId),
  )
