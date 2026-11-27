## ntfy as a channel (E13.1): publishing answers on the topic, and one poll
## round of the topic, through a fake HTTP port.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/log
import donkey/core/types
import donkey/domain/message
import donkey/ports/http
import donkey/adapters/channel/ntfy

type Sent = ref object
  posts: seq[(string, string, seq[HttpHeader])]
  gets: seq[string]
  pollBody: string

proc fakeHttp(s: Sent): HttpRuntimePort =
  HttpRuntimePort(
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}: s.posts.add((url, body, headers))
      ok(HttpResponse(status: 200, body: "{}")),
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        s.gets.add url
        ok(HttpResponse(status: 200, body: s.pollBody)))

proc adapter(s: Sent; token = ""): NtfyAdapter =
  let dir = getTempDir() / "donkey_ntfy"
  createDir(dir)
  newNtfyAdapter(NtfySettings(url: "https://ntfy.example", topic: "ana-donkey", token: token),
                 dir / "ids.tsv", http = fakeHttp(s))

proc runTests*() =
  suite "ntfy adapter":
    test "an answer is published on the topic, tagged, with the token":
      let s = Sent()
      check adapter(s, "tk_1").send(OutboundMessage(userId: UserId("u"), channel: ckNtfy, text: "Olá")).isOk
      check s.posts.len == 1
      check s.posts[0][0] == "https://ntfy.example/ana-donkey" and s.posts[0][1] == "Olá"
      check ("Tags", "donkey") in s.posts[0][2] and ("Authorization", "Bearer tk_1") in s.posts[0][2]

    test "buttons are dropped (the text says how to answer); a file becomes a note":
      let s = Sent()
      let a = adapter(s)
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckNtfy,
        text: "Aprovar? Use /approve abc", keyboard: @[@[("✅", "approval:abc:allow")]])).isOk
      check s.posts[0][1] == "Aprovar? Use /approve abc"
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckNtfy, text: "segue",
                                   mediaUrl: "/p/a.pdf")).isOk
      check "não pôde ser enviado" in s.posts[1][1] and "/p/a.pdf" notin s.posts[1][1]

    test "one poll round: the person's messages, and where the next starts":
      let s = Sent(pollBody: """{"id":"m1","time":1,"event":"message","topic":"ana-donkey","message":"oi"}
{"id":"m2","time":2,"event":"message","topic":"ana-donkey","message":"eco","tags":["donkey"]}
""")
      let round = pollNtfy(fakeHttp(s), NtfySettings(url: "https://ntfy.example", topic: "ana-donkey"), "m0").get
      check s.gets == @["https://ntfy.example/ana-donkey/json?poll=1&since=m0"]
      check round.messages == @[NtfyMessage(id: "m1", text: "oi")]
      check round.since == "m2"

    test "the poller is refused a server that is not http(s)":
      check startNtfy(NtfySettings(url: "ntfy.example", topic: "ana"), newLogger("t", lvlError)).isErr

    test "a bad topic is refused at start":
      let s = Sent()
      check newNtfyAdapter(NtfySettings(url: "https://ntfy.example", topic: "a/b"), "",
                           http = fakeHttp(s)).configError.len > 0

when isMainModule:
  runTests()
