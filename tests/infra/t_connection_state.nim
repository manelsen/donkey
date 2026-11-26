## Connection state per channel (second round, §3): the connection threads
## count their sockets and which are connected; the status reads the counts.

import std/unittest
import donkey/core/types
import donkey/infra/connection_state

proc runTests*() =
  suite "connection state":

    test "a socket starts, connects, drops and ends":
      resetConnections()
      check connectionCounts(ckDiscord) == (running: 0, connected: 0)
      socketStarted(ckDiscord)
      check connectionCounts(ckDiscord) == (running: 1, connected: 0)
      socketConnected(ckDiscord)
      check connectionCounts(ckDiscord) == (running: 1, connected: 1)
      socketDisconnected(ckDiscord)
      check connectionCounts(ckDiscord) == (running: 1, connected: 0)
      socketEnded(ckDiscord)
      check connectionCounts(ckDiscord) == (running: 0, connected: 0)

    test "several sockets of one channel (several bots) add up; others are apart":
      resetConnections()
      socketStarted(ckDiscord); socketStarted(ckDiscord)
      socketConnected(ckDiscord)
      socketStarted(ckIrc)
      check connectionCounts(ckDiscord) == (running: 2, connected: 1)
      check connectionCounts(ckIrc) == (running: 1, connected: 0)

    test "the counts never go below zero":
      resetConnections()
      socketDisconnected(ckSlack)
      socketEnded(ckSlack)
      check connectionCounts(ckSlack) == (running: 0, connected: 0)

    test "the last message of a channel without a counted socket":
      resetConnections()
      check lastInboundMs(ckTelegram) == 0
      noteInbound(ckTelegram, 1_000)
      check lastInboundMs(ckTelegram) == 1_000
      check activeLabel(0, 10_000) == "active, no message yet"
      check activeLabel(1_000, 1_000 + 30_000) == "active, last message 30s ago"
      check activeLabel(1_000, 1_000 + 5 * 60_000) == "active, last message 5m ago"
      check activeLabel(1_000, 1_000 + 3 * 3_600_000) == "active, last message 3h ago"
      check activeLabel(1_000, 1_000 + 2 * 86_400_000) == "active, last message 2d ago"

    test "a label for the status views":
      check connectionLabel(true, 1, 1) == "connected"
      check connectionLabel(true, 2, 1) == "reconnecting 1/2"
      check connectionLabel(true, 1, 0) == "connecting"
      check connectionLabel(true, 0, 0) == "stopped"
      check connectionLabel(false, 0, 0) == "active"   ## a channel without a counted socket

when isMainModule:
  runTests()
