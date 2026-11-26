## SMS adapter (second round, front 1): a reply is a Twilio message from the
## configured number to the person's number, split under the body limit.

import std/[os, strutils, unittest]
import donkey/adapters/channel/sms
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http

type Sent = ref object
  calls: seq[(string, string, seq[HttpHeader])]

proc fakeHttp(s: Sent; status = 201): HttpRuntimePort =
  HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      s.calls.add (url, body, headers)
    ok(HttpResponse(status: status, body: "{}")))

var n = 0
proc newAdapter(s: Sent; sid = "AC1"; token = "tok"; number = "+5511888880000";
                status = 201): SmsAdapter =
  inc n
  let dir = getTempDir() / ("donkey_sms_" & $n)
  removeDir(dir)
  createDir(dir)
  newSmsAdapter(sid, token, number, dir / "ids.tsv", http = fakeHttp(s, status))

proc runTests*() =
  suite "sms adapter":

    test "a reply goes from the configured number to the one it answers":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckSms, text: "feito",
                                   replyTo: "+5511999990000")).isOk
      check s.calls.len == 1
      check s.calls[0][0] == messagesUrl("AC1")
      let f = parseForm(s.calls[0][1])
      check f.get("To") == "+5511999990000" and f.get("From") == "+5511888880000"
      check f.get("Body") == "feito"
      check ("Authorization", basicAuth("AC1", "tok")) in s.calls[0][2]

    test "without a target, the person's own number":
      let s = Sent()
      let a = newAdapter(s)
      let uid = a.resolver.resolve(ckSms, "+5511999990000")
      check a.send(OutboundMessage(userId: uid, channel: ckSms, text: "lembrete")).isOk
      check parseForm(s.calls[0][1]).get("To") == "+5511999990000"
      check a.send(OutboundMessage(userId: UserId("ninguem"), channel: ckSms,
                                   text: "x")).isErr

    test "a long reply goes as several messages; media is refused":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckSms, replyTo: "+1",
                                   text: "x".repeat(SmsBodyChars + 1))).isOk
      check s.calls.len == 2
      check a.send(OutboundMessage(channel: ckSms, replyTo: "+1", text: "foto",
                                   mediaUrl: "/tmp/x.png")).isErr

    test "missing settings or a refused message are errors":
      let r = newAdapter(Sent(), token = "").send(
        OutboundMessage(channel: ckSms, replyTo: "+1", text: "oi"))
      check r.isErr and "TWILIO_AUTH_TOKEN" in r.error
      check newAdapter(Sent(), status = 400).send(
        OutboundMessage(channel: ckSms, replyTo: "+1", text: "oi")).isErr

when isMainModule:
  runTests()
