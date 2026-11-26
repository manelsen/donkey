## Google Chat inbound runtime (second round, front 1): verified events
## become session turns through the shared inbound gate; a direct space is
## remembered; a redelivered message is one turn; `/continue` is local.

import std/[os, strutils, unittest]
import donkey/adapters/channel/google_chat
import donkey/adapters/channel/google_chat_runtime
import donkey/domain/channels/google_chat_pure
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/core/security/dm_policy
import donkey/domain/message
import ./google_chat_vectors

let rtLog = newLogger("test.gchat_runtime", lvlError)

type Sink = ref object
  turns: seq[InboundMessage]
  replies: seq[OutboundMessage]

proc fallbackFor(s: Sink): proc(msg: InboundMessage) {.gcsafe.} =
  result = proc(msg: InboundMessage) {.gcsafe.} =
    {.cast(gcsafe).}:
      s.turns.add msg

proc replyFor(s: Sink): proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
  result = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      s.replies.add msg
    ok()

var n = 0
proc newAdapter(): GoogleChatAdapter =
  inc n
  let dir = getTempDir() / ("donkey_gchat_rt_" & $n)
  removeDir(dir); createDir(dir)
  newGoogleChatAdapter(serviceAccountJson(), dir / "ids.tsv", dir / "spaces.json")

proc ev(id = "spaces/S1/messages/M1"; text = "oi"; room = false): ChatEvent =
  ChatEvent(kind: "MESSAGE", id: id, sender: "users/111", displayName: "Belle",
            senderType: "HUMAN", text: text,
            space: (if room: "spaces/ROOM" else: "spaces/S1"),
            thread: (if room: "spaces/ROOM/threads/T1" else: ""), isGroup: room)

proc runTests*() =
  suite "google chat runtime":
    setup:
      while tryRecvChatEvent()[0]: discard

    test "a direct message becomes a turn answered in its space":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushChatEvent(ev(text = "resume a reunião"))
      check drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      let m = s.turns[0]
      check m.channel == ckGoogleChat and m.text == "resume a reunião"
      check m.channelId == "spaces/S1" and m.rawChannelId == "users/111" and not m.isGroup

    test "a redelivered message is one turn; other events are not turns":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushChatEvent(ev())
      pushChatEvent(ev())
      var added = ev(id = "")
      added.kind = "ADDED_TO_SPACE"
      pushChatEvent(added)
      discard drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1

    test "a room passes the group allowlist and answers in its thread":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      sm.configureGroupGate(GroupGate(allowedChats: @["spaces/OTHER"]))
      let s = Sink()
      pushChatEvent(ev(room = true))
      discard drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      sm.configureGroupGate(GroupGate(allowedChats: @["spaces/ROOM"]))
      pushChatEvent(ev(id = "spaces/ROOM/messages/M2", room = true))
      discard drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1 and s.turns[0].channelId == "spaces/ROOM|spaces/ROOM/threads/T1"

    test "/continue is answered locally, in the person's space":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushChatEvent(ev(text = "/continue ZZZZZZ"))
      discard drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0 and s.replies.len == 1 and s.replies[0].replyTo == "spaces/S1"

proc runMediaTests*() =
  suite "google chat runtime — attachments (E9.2)":
    setup:
      while tryRecvChatEvent()[0]: discard

    test "the first uploaded file goes to the turn; a Drive file and the rest are named":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      var e = ev(text = "")
      e.attachments = @[
        ChatAttachment(name: "plano.gdoc", drive: true),
        ChatAttachment(resourceName: "AbC-123_xyz=", name: "foto.png", mimeType: "image/png"),
        ChatAttachment(resourceName: "DeF-456=", name: "nota.pdf")]
      pushChatEvent(e)
      check drainGoogleChatEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      let m = s.turns[0]
      check m.mediaUrl == "AbC-123_xyz=" and m.mediaFileName == "foto.png"
      check m.mediaMimeType == "image/png"
      check "plano.gdoc" in m.text and "nota.pdf" in m.text

when isMainModule:
  runTests()
  runMediaTests()
