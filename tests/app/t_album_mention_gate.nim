## Tests for the album mention window.

import std/[tables, unittest]
import donkey/app/album_mention_gate
import donkey/domain/channels/telegram_policy

proc runTests*() =
  suite "album mention gate":

    test "TG-028: an addressed album admits its siblings":
      let gate = newAlbumMentionGate()
      let key = albumKey("u1", "g1")
      gate.rememberAddressedAlbum(key, 1_000)
      check gate.albumAddressed(key, 1_500)
      check not gate.albumAddressed(albumKey("u1", "g2"), 1_500)
      check not gate.albumAddressed(albumKey("u2", "g1"), 1_500)

    test "TG-028: the window expires":
      let gate = newAlbumMentionGate()
      let key = albumKey("u1", "g1")
      gate.rememberAddressedAlbum(key, 1_000, ttlMs = 500)
      check not gate.albumAddressed(key, 1_600)

    test "TG-028: a message without a group is never admitted":
      let gate = newAlbumMentionGate()
      gate.rememberAddressedAlbum(albumKey("u1", ""), 1_000)
      check not gate.albumAddressed("", 1_000)

    test "TG-028: expired entries are dropped":
      let gate = newAlbumMentionGate()
      gate.rememberAddressedAlbum(albumKey("u1", "g1"), 1_000, ttlMs = 500)
      gate.rememberAddressedAlbum(albumKey("u1", "g2"), 1_000, ttlMs = 9_000)
      gate.clearExpiredAlbums(2_000)
      check gate.untilMs.len == 1

when isMainModule:
  runTests()
