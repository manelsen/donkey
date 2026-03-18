## IdentityResolver — multi-channel identity mapping + cross-channel pairing.
##
## Maps (ChannelKind, channel_user_id) → stable UserId (UUID v4).
## Persistence: tab-separated file with columns: channel, channelUserId, uuid.
##
## Cross-channel pairing:
##   generateLinkCode(userId) → 6-digit OTP, TTL 10 min, max 5 attempts.
##   consumeLinkCode(code, channel, channelUserId) → bool (true if linked).

import std/[os, random, strutils, tables, times]
import ../../core/types
import ../../domain/message   ## for ChannelKind

type
  LinkEntry = object
    userId:   UserId
    expiry:   Time
    attempts: int

  IdentityResolver* = ref object
    ## Maps (channel, channelUserId) → UserId; stored as TSV.
    store:  Table[string, UserId]    ## key = "$channel\t$channelUserId"
    path:   string
    codes:  Table[string, LinkEntry] ## OTP codes in flight

const
  LinkCodeTtlSecs  = 600   ## 10 minutes
  LinkCodeMaxTries = 5

# ── Persistence ───────────────────────────────────────────────────────────────

proc save(r: IdentityResolver) =
  createDir(parentDir(r.path))
  var content = ""
  for key, uid in r.store:
    content.add key & '\t' & $uid & '\n'
  writeFile(r.path, content)

proc newIdentityResolver*(path: string): IdentityResolver =
  result = IdentityResolver(path: path,
                            store: initTable[string, UserId](),
                            codes: initTable[string, LinkEntry]())
  if fileExists(path):
    for line in lines(path):
      let parts = line.split('\t')
      if parts.len == 3:   ## channel \t channelUserId \t uuid
        let key = parts[0] & '\t' & parts[1]
        result.store[key] = UserId(parts[2])

# ── Core resolution ────────────────────────────────────────────────────────────

proc generateUUID(): string =
  randomize()
  let hex = "0123456789abcdef"
  result = newStringOfCap(36)
  for i in 0..<36:
    if i in [8, 13, 18, 23]: result.add '-'
    elif i == 14:             result.add '4'
    elif i == 19:             result.add hex[(rand(3) + 8)]
    else:                     result.add hex[rand(15)]

proc resolve*(r: IdentityResolver; channel: ChannelKind;
              channelUserId: string): UserId =
  ## Returns the stable UserId for a (channel, id) pair, creating one if absent.
  let key = $channel & '\t' & channelUserId
  if key notin r.store:
    r.store[key] = UserId(generateUUID())
    r.save()
  r.store[key]

# ── Telegram-specific resolve (int64 overload) ────────────────────────────────

proc resolve*(r: IdentityResolver; telegramUserId: int64): UserId =
  r.resolve(ckTelegram, $telegramUserId)

proc telegramId*(r: IdentityResolver; userId: UserId): int64 =
  ## Reverse lookup: internal UserId → Telegram numeric ID.
  for key, uid in r.store:
    if uid == userId:
      let parts = key.split('\t')
      if parts.len == 2 and parts[0] == $ckTelegram:
        try: return parseBiggestInt(parts[1]).int64
        except: discard
  return 0

# ── Cross-channel pairing (OTP) ───────────────────────────────────────────────

proc generateLinkCode*(r: IdentityResolver; userId: UserId): string =
  ## Generates a fresh 6-digit OTP valid for LinkCodeTtlSecs seconds.
  ## Any previous code for this userId is replaced.
  randomize()
  result = $rand(100_000..999_999)
  ## Remove any existing code for this user.
  var toDelete: seq[string]
  for code, entry in r.codes:
    if entry.userId == userId: toDelete.add(code)
  for c in toDelete: r.codes.del(c)
  r.codes[result] = LinkEntry(userId:   userId,
                               expiry:   getTime() + initDuration(seconds = LinkCodeTtlSecs),
                               attempts: 0)

proc consumeLinkCode*(r: IdentityResolver; code: string;
                      channel: ChannelKind; channelUserId: string): bool =
  ## Validates the OTP and, if valid, links (channel, channelUserId) to the
  ## code's owner UserId. Returns true on success.
  if code notin r.codes:
    return false
  var entry = r.codes[code]
  inc entry.attempts
  if getTime() > entry.expiry or entry.attempts > LinkCodeMaxTries:
    r.codes.del(code)
    return false
  ## Link the new channel identity to the existing user.
  let key = $channel & '\t' & channelUserId
  r.store[key] = entry.userId
  r.save()
  r.codes.del(code)
  true
