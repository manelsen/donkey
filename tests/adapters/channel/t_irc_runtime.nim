## IRC inbound runtime (second round, front 1): messages from services
## accounts become session turns through the shared inbound gate; the nick
## is remembered for sends without a target; `/continue` is answered locally.

import std/[os, unittest]
import donkey/adapters/channel/irc
import donkey/adapters/channel/irc_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/core/security/dm_policy
import donkey/domain/message

let rtLog = newLogger("test.irc_runtime", lvlError)

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
proc newAdapter(): IrcAdapter =
  inc n
  let dir = getTempDir() / ("donkey_irc_rt_" & $n)
  removeDir(dir); createDir(dir)
  newIrcAdapter(true, dir / "ids.tsv", dir / "nicks.json")

proc pm(text = "oi"; channel = ""): IrcPrivmsg =
  IrcPrivmsg(account: "belle", nick: "Belle", text: text, channel: channel,
             isGroup: channel.len > 0, replyTo: (if channel.len > 0: channel else: "Belle"))

proc runTests*() =
  suite "irc runtime":
    setup:
      while tryRecvIrc()[0]: discard
      while tryTakeOutLine()[0]: discard

    test "a private message becomes a turn answered to the nick":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushIrc(pm("resume a reunião"))
      check drainIrcEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      let m = s.turns[0]
      check m.channel == ckIrc and m.text == "resume a reunião"
      check m.channelId == "Belle" and m.rawChannelId == "belle" and not m.isGroup

    test "a channel the operator did not allow is dropped; an allowed one answers there":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      sm.configureGroupGate(GroupGate(allowedChats: @["#other"]))
      let s = Sink()
      pushIrc(pm("oi", "#donkey"))
      discard drainIrcEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      sm.configureGroupGate(GroupGate(allowedChats: @["#donkey"]))
      pushIrc(pm("oi", "#donkey"))
      discard drainIrcEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1 and s.turns[0].isGroup and s.turns[0].channelId == "#donkey"

    test "the nick is remembered for sends without a target":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushIrc(pm())
      discard drainIrcEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check a.send(OutboundMessage(userId: s.turns[0].userId, channel: ckIrc,
                                   text: "lembrete")).isOk
      check tryTakeOutLine() == (true, "PRIVMSG Belle :lembrete")

    test "/continue with a bad code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushIrc(pm("/continue ZZZZZZ"))
      discard drainIrcEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0 and s.replies.len == 1 and s.replies[0].replyTo == "Belle"

when isMainModule:
  runTests()
