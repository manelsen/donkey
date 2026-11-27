## ntfy inbound runtime (E13.1): what the poll queued becomes a turn through
## the shared inbound gate, once per message id; `/continue` links the topic.

import std/[os, strutils, unittest]
import donkey/adapters/channel/ntfy
import donkey/adapters/channel/ntfy_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http

let rtLog = newLogger("test.ntfy_runtime", lvlError)

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
proc newAdapter(): NtfyAdapter =
  inc n
  let dir = getTempDir() / ("donkey_ntfy_rt_" & $n)
  removeDir(dir)
  createDir(dir)
  newNtfyAdapter(NtfySettings(url: "https://ntfy.example", topic: "ana-donkey"), dir / "ids.tsv",
    http = HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 200))))

proc runTests*() =
  suite "ntfy runtime":
    setup:
      while tryRecvNtfy()[0]: discard

    test "a message on the topic becomes a turn, answered on the topic":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushNtfy(NtfyInbound(id: "m1", text: "resume o dia", topic: "ana-donkey"))
      check drainNtfyEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      check s.turns[0].channel == ckNtfy and s.turns[0].text == "resume o dia"
      check s.turns[0].rawChannelId == "ana-donkey" and s.turns[0].messageId == "m1"

    test "the same message twice makes one turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushNtfy(NtfyInbound(id: "m1", text: "oi", topic: "ana-donkey"))
      pushNtfy(NtfyInbound(id: "m1", text: "oi", topic: "ana-donkey"))
      check drainNtfyEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1

    test "a wrong /continue code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushNtfy(NtfyInbound(id: "m2", text: "/continue NOPE00", topic: "ana-donkey"))
      check drainNtfyEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 0 and s.replies.len == 1 and s.replies[0].channel == ckNtfy

when isMainModule:
  runTests()
