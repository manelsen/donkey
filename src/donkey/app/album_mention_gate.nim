## album_mention_gate.nim — remembers which albums were addressed to the bot.
##
## The domain decides the key and the expiry rule; this module owns the shared
## table and its lifecycle, so `domain/` stays free of mutable state.

import std/tables

type AlbumMentionGate* = ref object
  ## chatId|mediaGroupId → epoch ms until the album counts as addressed.
  untilMs*: Table[string, int64]

const AlbumMentionTtlMs* = 60_000'i64

func newAlbumMentionGate*(): AlbumMentionGate =
  AlbumMentionGate(untilMs: initTable[string, int64]())

proc rememberAddressedAlbum*(gate: AlbumMentionGate; key: string;
                             nowMs: int64; ttlMs = AlbumMentionTtlMs) =
  if gate.isNil or key.len == 0:
    return
  gate.untilMs[key] = nowMs + ttlMs

func albumAddressed*(gate: AlbumMentionGate; key: string;
                     nowMs: int64): bool =
  if gate.isNil or key.len == 0:
    return false
  gate.untilMs.getOrDefault(key, 0'i64) > nowMs

proc clearExpiredAlbums*(gate: AlbumMentionGate; nowMs: int64) =
  if gate.isNil:
    return
  var expired: seq[string] = @[]
  for key, untilMs in gate.untilMs:
    if untilMs <= nowMs:
      expired.add(key)
  for key in expired:
    gate.untilMs.del(key)
