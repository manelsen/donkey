## Mattermost adapter (second round, front 1): replies as posts, in the
## thread they answer, split under the post limit, only text; a person's last
## channel kept for sends without a target (reminders).

import std/[json, os, strutils, unittest]
import donkey/adapters/channel/mattermost
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
proc newAdapter(s: Sent; server = "https://chat.example.com"; token = "tok";
                status = 201): MattermostAdapter =
  inc n
  let dir = getTempDir() / ("donkey_mm_" & $n)
  removeDir(dir)
  createDir(dir)
  newMattermostAdapter(server, token, dir / "ids.tsv", dir / "channels.json",
                       http = fakeHttp(s, status))

proc runTests*() =
  suite "mattermost adapter":

    test "a reply is a post in the thread it answers, with the bot's token":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckMattermost, text: "feito",
                                   replyTo: "chan-1:root-9")).isOk
      check s.calls.len == 1
      check s.calls[0][0] == "https://chat.example.com/api/v4/posts"
      let body = parseJson(s.calls[0][1])
      check body["channel_id"].getStr == "chan-1" and body["root_id"].getStr == "root-9"
      check body["message"].getStr == "feito"
      check ("Authorization", "Bearer tok") in s.calls[0][2]

    test "a long reply goes as several posts":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckMattermost, replyTo: "chan-1",
                                   text: "x".repeat(MattermostPostChars + 5))).isOk
      check s.calls.len == 2

    test "without a target, the person's last channel; none known is an error":
      let s = Sent()
      var a = newAdapter(s)
      let r = a.send(OutboundMessage(userId: UserId("u-1"), channel: ckMattermost,
                                     text: "lembrete"))
      check r.isErr and "no channel" in r.error
      let uid = a.resolver.resolve(ckMattermost, "alice-id")
      check a.rememberChannel("alice-id", "dm-chan").isOk
      check a.send(OutboundMessage(userId: uid, channel: ckMattermost, text: "lembrete")).isOk
      check parseJson(s.calls[^1][1])["channel_id"].getStr == "dm-chan"

    test "the remembered channels survive a restart":
      let s = Sent()
      inc n
      let dir = getTempDir() / ("donkey_mm_restart_" & $n)
      removeDir(dir)
      createDir(dir)
      var a = newMattermostAdapter("https://chat.example.com", "tok", dir / "ids.tsv",
                                   dir / "channels.json", http = fakeHttp(s))
      let uid = a.resolver.resolve(ckMattermost, "alice-id")
      check a.rememberChannel("alice-id", "dm-chan").isOk
      let b = newMattermostAdapter("https://chat.example.com", "tok", dir / "ids.tsv",
                                   dir / "channels.json", http = fakeHttp(s))
      check b.send(OutboundMessage(userId: uid, channel: ckMattermost, text: "oi")).isOk

    test "media is refused, not dropped; a refused post is an error":
      let s = Sent()
      check newAdapter(s).send(OutboundMessage(channel: ckMattermost, replyTo: "c",
        text: "foto", mediaUrl: "/tmp/x.png")).isErr
      check newAdapter(Sent(), status = 403).send(
        OutboundMessage(channel: ckMattermost, replyTo: "c", text: "oi")).isErr

    test "a missing token or a plain-HTTP server is reported on every send":
      let r = newAdapter(Sent(), token = "").send(
        OutboundMessage(channel: ckMattermost, replyTo: "c", text: "oi"))
      check r.isErr and "MATTERMOST_TOKEN" in r.error
      check newAdapter(Sent(), server = "http://chat.example.com").send(
        OutboundMessage(channel: ckMattermost, replyTo: "c", text: "oi")).isErr

when isMainModule:
  runTests()
