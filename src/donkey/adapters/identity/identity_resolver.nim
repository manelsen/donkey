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

import std/[os, random, strutils, tables, times]
import ../../core/types

type
  LinkEntry = object
    userId: UserId
    expiry: Time

  IdentityResolver* = ref object
    store*:       Table[string, UserId]       ## "kind:rawId" → uuid
    reverseMap*:  Table[string, seq[string]]  ## string(uuid) → seq["kind:rawId"]
    path*:        string
    pendingLinks: Table[string, LinkEntry]    ## code → {userId, expiry}

const
  LinkCodeAlpha  = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  LinkCodeLen    = 6
  LinkCodeTtlSec = 600  ## 10 minutes

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

proc save(r: IdentityResolver) =
  createDir(r.path.parentDir())
  var buf = ""
  for k, v in r.store:
    buf.add(k & '\t' & $v & '\n')
  writeFile(r.path, buf)

proc newIdentityResolver*(path: string): IdentityResolver =
  result = IdentityResolver(
    path:         path,
    store:        initTable[string, UserId](),
    reverseMap:   initTable[string, seq[string]](),
    pendingLinks: initTable[string, LinkEntry](),
  )
  if fileExists(path):
    for line in lines(path):
      let parts = line.split('\t')
      if parts.len == 2:
        let key = parts[0]
        let uid = UserId(parts[1])
        result.store[key] = uid
        let us = $uid
        if us notin result.reverseMap:
          result.reverseMap[us] = @[]
        result.reverseMap[us].add(key)

proc resolve*(r: IdentityResolver; kind: ChannelKind; rawId: string): UserId =
  ## Returns the stable UserId for (kind, rawId), minting a new UUID on first contact.
  let key = channelKey(kind, rawId)
  if key notin r.store:
    randomize()
    let uid = UserId(generateUUID())
    r.store[key] = uid
    let us = $uid
    if us notin r.reverseMap:
      r.reverseMap[us] = @[]
    r.reverseMap[us].add(key)
    r.save()
  r.store[key]

proc reverseChannel*(r: IdentityResolver; userId: UserId; kind: ChannelKind): string =
  ## Reverse lookup: UserId + channel kind → raw channel user ID.
  ## Returns "" if not found.
  let us = $userId
  if us notin r.reverseMap: return ""
  let prefix = $kind & ":"
  for key in r.reverseMap[us]:
    if key.startsWith(prefix):
      return key[prefix.len .. ^1]
  ""

proc generateLinkCode*(r: IdentityResolver; userId: UserId): string =
  ## Generates a 6-char one-time code for cross-channel linking.
  ## Valid for 10 minutes. Call this when user types /mycode on any channel.
  randomize()
  result = newString(LinkCodeLen)
  for i in 0..<LinkCodeLen:
    result[i] = LinkCodeAlpha[rand(LinkCodeAlpha.len - 1)]
  r.pendingLinks[result] = LinkEntry(
    userId: userId,
    expiry: getTime() + initDuration(seconds = LinkCodeTtlSec),
  )

proc consumeLinkCode*(r: IdentityResolver; code: string;
                      kind: ChannelKind; rawId: string): bool =
  ## Links (kind, rawId) to the userId stored under code. Single-use. Saves to disk.
  ## Returns false if code is unknown or expired.
  if code notin r.pendingLinks: return false
  let entry = r.pendingLinks[code]
  if getTime() > entry.expiry:
    r.pendingLinks.del(code)
    return false
  let key = channelKey(kind, rawId)
  r.store[key] = entry.userId
  let us = $entry.userId
  if us notin r.reverseMap: r.reverseMap[us] = @[]
  if key notin r.reverseMap[us]:
    r.reverseMap[us].add(key)
  r.pendingLinks.del(code)
  r.save()
  true
