## BlueBubbles inbound runtime (E13.3): what the connection queued becomes a turn
## through the shared inbound gate, once per message guid; `/continue` links the address.

import std/[os, strutils, unittest]
import donkey/adapters/channel/bluebubbles
import donkey/adapters/channel/bluebubbles_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http

let rtLog = newLogger("test.bluebubbles_runtime", lvlError)

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
proc newAdapter(): BlueBubblesAdapter =
  inc n
  let dir = getTempDir() / ("donkey_bluebubbles_rt_" & $n)
  removeDir(dir)
  createDir(dir)
  newBlueBubblesAdapter(BlueBubblesSettings(url: "https://mac.example.com", password: "pw"),
    dir / "ids.tsv", http = HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 200))))

proc runTests*() =
  suite "bluebubbles runtime":
    setup:
      while tryRecvBlue()[0]: discard

    test "a message on the topic becomes a turn, answered on the topic":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushBlue(BlueInbound(guid: "m-41", address: "+5511", chatGuid: "iMessage;-;+5511", text: "resume o dia"))
      check drainBlueBubblesEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      check s.turns[0].channel == ckBlueBubbles and s.turns[0].text == "resume o dia"
      check s.turns[0].rawChannelId == "+5511" and s.turns[0].messageId == "m-41"
      check s.turns[0].channelId == "iMessage;-;+5511"

    test "the same message twice makes one turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushBlue(BlueInbound(guid: "m-41", address: "+5511", chatGuid: "iMessage;-;+5511", text: "oi"))
      pushBlue(BlueInbound(guid: "m-41", address: "+5511", chatGuid: "iMessage;-;+5511", text: "oi"))
      check drainBlueBubblesEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1

    test "a wrong /continue code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushBlue(BlueInbound(guid: "m-42", address: "+5511", chatGuid: "iMessage;-;+5511", text: "/continue NOPE00"))
      check drainBlueBubblesEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 0 and s.replies.len == 1 and s.replies[0].channel == ckBlueBubbles

proc runUnreadTests*() =
  suite "bluebubbles runtime — attachments":
    test "only an attachment gets a note; text with attachments is a turn that names them":
      while tryRecvBlue()[0]: discard
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushBlue(BlueInbound(guid: "m-43", address: "+5511", chatGuid: "iMessage;-;+5511", attachments: 1))
      pushBlue(BlueInbound(guid: "m-44", address: "+5511", chatGuid: "iMessage;-;+5511", text: "veja", attachments: 2))
      check drainBlueBubblesEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 2
      check s.replies.len == 1 and "texto" in s.replies[0].text   ## only an attachment: a note
      check s.turns.len == 1 and "veja" in s.turns[0].text and "não lid" in s.turns[0].text

when isMainModule:
  runTests()
  runUnreadTests()
