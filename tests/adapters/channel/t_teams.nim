## The Teams adapter (PRD-roadmap E2.1–E2.3): the connector's keys shared by
## the webhook threads, the app token, and sending through the Bot Connector.
## No socket: the HTTP port is a recording fake.

import std/[json, os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http
import donkey/adapters/channel/teams
import donkey/adapters/identity/identity_resolver
import ./teams_jwt_vectors

const
  ServiceUrl = "https://smba.trafficmanager.net/amer/"
  Jwks = """{"keys":[{"kty":"RSA","kid":"k1","n":"""" & vecN &
         """","e":"AQAB","endorsements":["msteams"]}]}"""
  Hour = 3_600_000'i64

type Recorder = ref object
  posts: seq[(string, string, seq[HttpHeader])]
  tokenCalls: int
  failSend: bool

proc fakeHttp(r: Recorder): HttpRuntimePort =
  result.post = proc(url, body: string; headers: seq[HttpHeader] = @[]):
      Result[HttpResponse, string] {.gcsafe.} =
    r.posts.add (url, body, headers)
    if url.startsWith("https://login.microsoftonline.com/"):
      inc r.tokenCalls
      return ok(HttpResponse(status: 200, body: """{"token_type":"Bearer",
        "expires_in":3600,"access_token":"tok-""" & $r.tokenCalls & "\"}"))
    if r.failSend:
      return ok(HttpResponse(status: 403, body: "{}"))
    ok(HttpResponse(status: 201, body: """{"id":"new"}"""))

proc headerOf(h: seq[HttpHeader]; name: string): string =
  for (k, v) in h:
    if cmpIgnoreCase(k, name) == 0:
      return v

proc tempDir(tag: string): string =
  result = getTempDir() / ("donkey_teams_" & tag)
  removeDir(result)
  createDir(result)

proc adapterFor(r: Recorder; dir: string; nowMs: int64 = 1_000): TeamsAdapter =
  newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
                  identityPath = dir / "identities.tsv",
                  conversationsPath = dir / "teams_conversations.json",
                  http = fakeHttp(r), clock = proc(): int64 {.gcsafe.} = nowMs)

proc runTests*() =
  suite "teams — the connector's keys":

    test "seeded keys are what the webhook threads see":
      resetBotKeys()
      check currentBotKeys().len == 0
      seedBotKeys(Jwks, nowMs = 1_000)
      check currentBotKeys().len == 1
      check currentBotKeys()[0].kid == "k1"

    test "missing keys are fetched; fresh ones are not fetched again":
      resetBotKeys()
      var calls = 0
      let fetch: KeyFetch = proc(): Result[string, string] {.gcsafe.} =
        inc calls
        ok(Jwks)
      check refreshBotKeys(fetch, nowMs = 1_000).isOk
      check calls == 1
      check refreshBotKeys(fetch, nowMs = 2_000).isOk
      check calls == 1
      check refreshBotKeys(fetch, nowMs = 1_000 + 25 * Hour).isOk
      check calls == 2   ## older than a day

    test "an unknown key asks again, but not more than once in five minutes":
      resetBotKeys()
      var calls = 0
      let fetch: KeyFetch = proc(): Result[string, string] {.gcsafe.} =
        inc calls
        ok(Jwks)
      discard refreshBotKeys(fetch, nowMs = 1_000)
      check refreshBotKeys(fetch, nowMs = 2_000, unknownKey = true).isOk
      check calls == 1   ## just fetched
      check refreshBotKeys(fetch, nowMs = 1_000 + 6 * 60_000, unknownKey = true).isOk
      check calls == 2

    test "a failed fetch keeps the keys in hand":
      resetBotKeys()
      seedBotKeys(Jwks, nowMs = 1_000)
      let failing: KeyFetch = proc(): Result[string, string] {.gcsafe.} = err("down")
      check refreshBotKeys(failing, nowMs = 1_000 + 25 * Hour).isErr
      check currentBotKeys().len == 1

  suite "teams — sending":

    test "a reply asks for the app token once and answers in the thread":
      let dir = tempDir("reply")
      defer: removeDir(dir)
      let r = Recorder()
      let a = adapterFor(r, dir)
      let target = replyTarget(ServiceUrl, "a:1xyz", "1700")
      check a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
                                   replyTo: target, text: "olá")).isOk
      check a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
                                   replyTo: target, text: "de novo")).isOk
      check r.tokenCalls == 1
      check r.posts.len == 3
      check r.posts[0][0] == "https://login.microsoftonline.com/tenant-1/oauth2/v2.0/token"
      check "client_secret=pw" in r.posts[0][1]
      check r.posts[1][0] ==
        "https://smba.trafficmanager.net/amer/v3/conversations/a%3A1xyz/activities/1700"
      check headerOf(r.posts[1][2], "Authorization") == "Bearer tok-1"
      check parseJson(r.posts[1][1])["text"].getStr == "olá"

    test "the token is renewed when it is about to expire":
      let dir = tempDir("renew")
      defer: removeDir(dir)
      let r = Recorder()
      var now = 1_000'i64
      let a = newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "t",
        identityPath = dir / "identities.tsv",
        conversationsPath = dir / "teams_conversations.json",
        http = fakeHttp(r), clock = proc(): int64 {.gcsafe.} = now)
      let msg = OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
                                replyTo: replyTarget(ServiceUrl, "a:1", ""), text: "x")
      check a.send(msg).isOk
      now = 1_000 + 3_301_000
      check a.send(msg).isOk
      check r.tokenCalls == 2

    test "a long answer goes in pieces":
      let dir = tempDir("long")
      defer: removeDir(dir)
      let r = Recorder()
      let a = adapterFor(r, dir)
      check a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
        replyTo: replyTarget(ServiceUrl, "a:1", ""),
        text: "a".repeat(TeamsChunkChars + 5))).isOk
      check r.posts.len == 3   ## token + two pieces

    test "a service on a host that is not allowed is never sent to":
      let dir = tempDir("host")
      defer: removeDir(dir)
      let r = Recorder()
      let a = adapterFor(r, dir)
      let res = a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
        replyTo: replyTarget("https://evil.example/", "a:1", ""), text: "x"))
      check res.isErr
      check r.posts.len == 0

    test "a refused send is an error, with the status":
      let dir = tempDir("refused")
      defer: removeDir(dir)
      let r = Recorder(failSend: true)
      let a = adapterFor(r, dir)
      let res = a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
        replyTo: replyTarget(ServiceUrl, "a:1", ""), text: "x"))
      check res.isErr and "403" in res.error

    test "without a reply target the user's last conversation is used, also after a restart":
      let dir = tempDir("proactive")
      defer: removeDir(dir)
      let r = Recorder()
      var a = adapterFor(r, dir)
      let uid = a.resolver.resolve(ckTeams, "aad-belle")
      check a.send(OutboundMessage(userId: uid, channel: ckTeams, text: "x")).isErr
      check a.rememberConversation("aad-belle", ServiceUrl, "a:1xyz").isOk
      let again = adapterFor(r, dir)   ## a new process
      check again.send(OutboundMessage(userId: uid, channel: ckTeams, text: "lembrete")).isOk
      check r.posts[^1][0] ==
        "https://smba.trafficmanager.net/amer/v3/conversations/a%3A1xyz/activities"

    test "a conversation that cannot be saved is reported, and still used":
      let dir = tempDir("unsaved")
      defer: removeDir(dir)
      let r = Recorder()
      let a = newTeamsAdapter("app-123", "pw", "t", dir / "ids.tsv",
        "/proc/donkey-no-such/teams_conversations.json", http = fakeHttp(r),
        clock = proc(): int64 {.gcsafe.} = 1_000)
      let uid = a.resolver.resolve(ckTeams, "aad-belle")
      check a.rememberConversation("aad-belle", ServiceUrl, "a:1xyz").isErr
      check a.send(OutboundMessage(userId: uid, channel: ckTeams, text: "x")).isOk

    test "empty text sends nothing":
      let dir = tempDir("empty")
      defer: removeDir(dir)
      let r = Recorder()
      let a = adapterFor(r, dir)
      check a.send(OutboundMessage(userId: UserId("u-1"), channel: ckTeams,
        replyTo: replyTarget(ServiceUrl, "a:1", ""), text: "  ")).isOk
      check r.posts.len == 0

when isMainModule:
  runTests()
