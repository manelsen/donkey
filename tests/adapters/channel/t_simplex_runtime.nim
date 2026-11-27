## SimpleX inbound runtime (E13.2): what the connection queued becomes a turn
## through the shared inbound gate, once per item id; `/continue` links the contact.

import std/[os, strutils, unittest]
import donkey/adapters/channel/simplex
import donkey/adapters/channel/simplex_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message

let rtLog = newLogger("test.simplex_runtime", lvlError)

type Sink = ref object
  turns: seq[InboundMessage]
  replies: seq[OutboundMessage]

proc fallbackFor(s: Sink): proc(msg: InboundMessage) {.gcsafe.} =
  result = proc(msg: InboundMessage) {.gcsafe.} =
    {.cast(gcsafe).}: s.turns.add msg

proc replyFor(s: Sink): proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
  result = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: s.replies.add msg
    ok()

var n = 0
proc newAdapter(): SimplexAdapter =
  inc n
  let dir = getTempDir() / ("donkey_simplex_rt_" & $n)
  removeDir(dir)
  createDir(dir)
  newSimplexAdapter("", dir / "ids.tsv")

proc runTests*() =
  suite "simplex runtime":
    setup:
      while tryRecvSimplex()[0]: discard

    test "a message on the topic becomes a turn, answered on the topic":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSimplex(SimplexInbound(contactId: 5, name: "ana", text: "resume o dia", itemId: "41"))
      check drainSimplexEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      check s.turns[0].channel == ckSimplex and s.turns[0].text == "resume o dia"
      check s.turns[0].rawChannelId == "5" and s.turns[0].messageId == "41"

    test "the same message twice makes one turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSimplex(SimplexInbound(contactId: 5, name: "ana", text: "oi", itemId: "41"))
      pushSimplex(SimplexInbound(contactId: 5, name: "ana", text: "oi", itemId: "41"))
      check drainSimplexEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1

    test "a wrong /continue code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSimplex(SimplexInbound(contactId: 5, name: "ana", text: "/continue NOPE00", itemId: "42"))
      check drainSimplexEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 0 and s.replies.len == 1 and s.replies[0].channel == ckSimplex

proc runUnreadTests*() =
  suite "simplex runtime — not text":
    test "an image or a file is answered with a note, not a turn":
      while tryRecvSimplex()[0]: discard
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSimplex(SimplexInbound(contactId: 5, name: "ana", unreadKind: "image", itemId: "43"))
      check drainSimplexEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 0 and s.replies.len == 1 and "texto" in s.replies[0].text

when isMainModule:
  runTests()
  runUnreadTests()
