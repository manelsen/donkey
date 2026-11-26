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

const Media = "https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1"

proc mediaAdapter(gets: ref seq[(string, seq[HttpHeader])]; location = ""): SmsAdapter =
  inc n
  let dir = getTempDir() / ("donkey_sms_media_" & $n)
  removeDir(dir); createDir(dir)
  let http = HttpRuntimePort(
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 201)),
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}: gets[].add (url, headers)
      ok(HttpResponse(status: 200, body: "JPEGDATA")),
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}: gets[].add (url, headers)
      if location.len > 0:
        return ok(HttpResponse(status: 307, headers: @[("Location", location)]))
      ok(HttpResponse(status: 200, body: "JPEGDATA")))
  newSmsAdapter("AC1", "tok", "+5511888880000", dir / "ids.tsv", http = http)

proc runMediaTests*() =
  suite "sms adapter — MMS in (E9.3)":
    test "the account's media is fetched with its credentials":
      let gets = new seq[(string, seq[HttpHeader])]
      let d = mediaAdapter(gets).downloadFile(Media)
      check d.isOk and d.get.data.len == 8
      check gets[][0][0] == Media
      check gets[][0][1].len == 1 and gets[][0][1][0][0] == "Authorization"

    test "a redirect to Twilio's storage is followed, without the credentials":
      let gets = new seq[(string, seq[HttpHeader])]
      let d = mediaAdapter(gets, "https://media.twiliocdn.com/AC1/abc").downloadFile(Media)
      check d.isOk
      check gets[][1][0] == "https://media.twiliocdn.com/AC1/abc" and gets[][1][1].len == 0

    test "another account's media, or a redirect elsewhere, is refused":
      let gets = new seq[(string, seq[HttpHeader])]
      check mediaAdapter(gets).downloadFile(Media.replace("AC1", "AC2")).isErr
      check gets[].len == 0
      check mediaAdapter(gets, "https://evil.example/x").downloadFile(Media).isErr
      check gets[].len == 1   ## the redirect was not followed

when isMainModule:
  runTests()
  runMediaTests()
