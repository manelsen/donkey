## SMS inbound runtime (second round, front 1): the messages the webhook
## queued become session turns through the shared inbound gate; a message
## with media and no text gets a short answer instead of a turn.

import std/[os, strutils, unittest]
import donkey/adapters/channel/sms
import donkey/adapters/channel/sms_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http

let rtLog = newLogger("test.sms_runtime", lvlError)

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
proc newAdapter(): SmsAdapter =
  inc n
  let dir = getTempDir() / ("donkey_sms_rt_" & $n)
  removeDir(dir)
  createDir(dir)
  newSmsAdapter("AC1", "tok", "+5511888880000", dir / "ids.tsv",
    http = HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 201))))

proc sms(sid: string; text = "oi"; media = 0): InboundSms =
  InboundSms(sid: sid, sender: "+5511999990000", receiver: "+5511888880000",
             text: text, mediaCount: media)

proc runTests*() =
  suite "sms runtime":
    setup:
      while tryRecvSms()[0]: discard

    test "a message becomes a turn answered to the sender's number":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSms(sms("SM1", "resume a reunião"))
      check drainSmsEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      let m = s.turns[0]
      check m.channel == ckSms and m.text == "resume a reunião"
      check m.channelId == "+5511999990000" and m.rawChannelId == "+5511999990000"
      check m.messageId == "SM1" and not m.isGroup

    test "the same message delivered twice is one turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSms(sms("SM1"))
      pushSms(sms("SM1"))
      discard drainSmsEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1

    test "an MMS is a turn: the first item goes by its URL and type, the rest are counted (E9.3)":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      var m = sms("MM2", "", media = 2)
      m.media = @[("https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM2/Media/ME1", "image/jpeg"),
                  ("https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM2/Media/ME2", "audio/ogg")]
      pushSms(m)
      check drainSmsEvents(a, sm, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1 and s.replies.len == 0
      check s.turns[0].mediaUrl.endsWith("/Media/ME1") and s.turns[0].mediaMimeType == "image/jpeg"
      check "audio/ogg" in s.turns[0].text

    test "media the webhook did not list (no URL) is still answered, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSms(sms("SM2", "", media = 1))
      discard drainSmsEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      check s.replies.len == 1 and s.replies[0].replyTo == "+5511999990000"

    test "/continue with a bad code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      let s = Sink()
      pushSms(sms("SM3", "/continue ZZZZZZ"))
      discard drainSmsEvents(a, sm, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0 and s.replies.len == 1

when isMainModule:
  runTests()
