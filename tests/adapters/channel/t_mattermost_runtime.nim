## Mattermost inbound runtime (second round, front 1): the posts the socket
## queued become session turns on the daemon loop, through the shared
## inbound gate; `/continue` is answered locally.

import std/[os, unittest]
import donkey/adapters/channel/mattermost
import donkey/adapters/channel/mattermost_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/core/security/dm_policy
import donkey/domain/message
import donkey/ports/http

let rtLog = newLogger("test.mattermost_runtime", lvlError)

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
proc newAdapter(): MattermostAdapter =
  inc n
  let dir = getTempDir() / ("donkey_mm_rt_" & $n)
  removeDir(dir)
  createDir(dir)
  newMattermostAdapter("https://chat.example.com", "tok", dir / "ids.tsv",
    dir / "channels.json", http = HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 201))))

proc post(id: string; text = "oi"; group = false; channel = "chan-1"): MattermostPost =
  MattermostPost(id: id, userId: "alice-id", channelId: channel, text: text,
                 senderName: "@alice", isGroup: group, mentioned: group)

proc runTests*() =
  suite "mattermost runtime":
    setup:
      while tryRecvPost()[0]: discard

    test "a direct message becomes a turn that answers in that channel":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushPost(post("p1", "resume a reunião"))
      check drainMattermostEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      let m = s.turns[0]
      check m.channel == ckMattermost and m.text == "resume a reunião"
      check m.channelId == "chan-1" and m.rawChannelId == "alice-id"
      check m.messageId == "p1" and not m.isGroup
      check not tryRecvPost()[0]

    test "a group the operator did not allow is dropped; an allowed one is a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      sm.configureGroupGate(GroupGate(allowedChats: @["other-chan"]))
      let s = Sink()
      pushPost(post("p1", group = true, channel = "team-chan"))
      discard drainMattermostEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      sm.configureGroupGate(GroupGate(allowedChats: @["team-chan"]))
      pushPost(post("p2", group = true, channel = "team-chan"))
      discard drainMattermostEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1 and s.turns[0].isGroup
      check s.turns[0].channelId == "team-chan:p2"   ## answered in the post's thread

    test "the direct channel is remembered for sends without a target":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushPost(post("p1"))
      discard drainMattermostEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check a.send(OutboundMessage(userId: s.turns[0].userId, channel: ckMattermost,
                                   text: "lembrete")).isOk

    test "/continue with a bad code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushPost(post("p1", "/continue ZZZZZZ"))
      discard drainMattermostEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      check s.replies.len == 1 and s.replies[0].replyTo == "chan-1"

when isMainModule:
  runTests()
