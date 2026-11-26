## Google Chat adapter (second round, front 1): replies through the Chat API
## with an access token the service account gets by signing an assertion,
## reused until it is due; in the thread they answer; text only.

import std/[json, os, strutils, unittest]
import donkey/adapters/channel/google_chat
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http
import ./google_chat_vectors

type Sent = ref object
  calls: seq[(string, string, seq[HttpHeader])]

proc fakeHttp(s: Sent; chatStatus = 200): HttpRuntimePort =
  HttpRuntimePort(post: proc(url, body: string;
      headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      s.calls.add (url, body, headers)
    if url.startsWith("https://oauth2.googleapis.com/"):
      return ok(HttpResponse(status: 200, body: """{"access_token":"ya29.t","expires_in":3600}"""))
    ok(HttpResponse(status: chatStatus, body: "{}")))

var n = 0
proc newAdapter(s: Sent; account = serviceAccountJson(); chatStatus = 200): GoogleChatAdapter =
  inc n
  let dir = getTempDir() / ("donkey_gchat_" & $n)
  removeDir(dir); createDir(dir)
  newGoogleChatAdapter(account, dir / "ids.tsv", dir / "spaces.json",
                       http = fakeHttp(s, chatStatus),
                       clock = proc(): int64 {.gcsafe.} = 1_800_000_000_000)

proc runTests*() =
  suite "google chat adapter":

    test "the first reply gets a token with a signed assertion, then posts in the thread":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckGoogleChat, text: "feito",
                                   replyTo: "spaces/S1|spaces/S1/threads/T1")).isOk
      check s.calls.len == 2
      check "assertion=" in s.calls[0][1]
      check s.calls[1][0] == messagesUrl("spaces/S1|spaces/S1/threads/T1")
      check parseJson(s.calls[1][1])["thread"]["name"].getStr == "spaces/S1/threads/T1"
      check ("Authorization", "Bearer ya29.t") in s.calls[1][2]

    test "the token is reused until it is due":
      let s = Sent()
      let a = newAdapter(s)
      check a.send(OutboundMessage(channel: ckGoogleChat, text: "1", replyTo: "spaces/S1")).isOk
      check a.send(OutboundMessage(channel: ckGoogleChat, text: "2", replyTo: "spaces/S1")).isOk
      check s.calls.len == 3

    test "without a target, the person's direct space; a forged target is refused":
      let s = Sent()
      let a = newAdapter(s)
      let uid = a.resolver.resolve(ckGoogleChat, "users/111")
      check a.send(OutboundMessage(userId: uid, channel: ckGoogleChat, text: "x")).isErr
      check a.rememberSpace("users/111", "spaces/DM1").isOk
      check a.send(OutboundMessage(userId: uid, channel: ckGoogleChat, text: "lembrete")).isOk
      check s.calls[^1][0] == messagesUrl("spaces/DM1")
      check a.send(OutboundMessage(channel: ckGoogleChat, text: "x",
                                   replyTo: "https://evil.example/x")).isErr

    test "a refused token (401) is dropped and the post tried once more with a new one":
      var posts = 0
      var tokens = 0
      let http = HttpRuntimePort(post: proc(url, body: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        {.cast(gcsafe).}:
          if url.startsWith("https://oauth2.googleapis.com/"):
            inc tokens
            return ok(HttpResponse(status: 200, body: """{"access_token":"t""" & $tokens & """","expires_in":3600}"""))
          inc posts
          return ok(HttpResponse(status: (if posts == 1: 401 else: 200), body: "{}")))
      let dir = getTempDir() / "donkey_gchat_401"
      removeDir(dir); createDir(dir)
      let a = newGoogleChatAdapter(serviceAccountJson(), dir / "ids.tsv", dir / "s.json",
                                   http = http, clock = proc(): int64 {.gcsafe.} = 1_800_000_000_000)
      check a.send(OutboundMessage(channel: ckGoogleChat, text: "x", replyTo: "spaces/S1")).isOk
      check tokens == 2 and posts == 2

    test "no account, a broken one, media, or a refused post are errors":
      check newAdapter(Sent(), account = "").send(
        OutboundMessage(channel: ckGoogleChat, text: "x", replyTo: "spaces/S1")).error.contains("GOOGLE_CHAT_SERVICE_ACCOUNT")
      check newAdapter(Sent(), account = "{}").send(
        OutboundMessage(channel: ckGoogleChat, text: "x", replyTo: "spaces/S1")).isErr
      check newAdapter(Sent()).send(OutboundMessage(channel: ckGoogleChat, text: "x",
        replyTo: "spaces/S1", mediaUrl: "/tmp/a.png")).isErr
      check newAdapter(Sent(), chatStatus = 403).send(
        OutboundMessage(channel: ckGoogleChat, text: "x", replyTo: "spaces/S1")).isErr

when isMainModule:
  runTests()
