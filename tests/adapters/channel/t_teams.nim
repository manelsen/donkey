## The Teams adapter (PRD-roadmap E2.1–E2.3): the connector's keys shared by
## the webhook threads, the app token, and sending through the Bot Connector.
## No socket: the HTTP port is a recording fake.

import std/[json, os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http
import donkey/adapters/channel/teams
import ./teams_cert_vectors
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

proc runMediaTests*() =
  suite "teams — attachments in (E9.4)":
    proc withGets(r: Recorder; gets: ref seq[(string, seq[HttpHeader])]): HttpRuntimePort =
      result = fakeHttp(r)
      result.get = proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        {.cast(gcsafe).}: gets[].add (url, headers)
        ok(HttpResponse(status: 200, body: "FILEDATA"))

    proc mediaAdapter(r: Recorder; gets: ref seq[(string, seq[HttpHeader])]): TeamsAdapter =
      let dir = tempDir("media")
      newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
                      identityPath = dir / "identities.tsv",
                      conversationsPath = dir / "teams_conversations.json",
                      http = withGets(r, gets), clock = proc(): int64 {.gcsafe.} = 1_000)

    test "a SharePoint file is fetched as is: its URL carries the authorization":
      let r = Recorder()
      let gets = new seq[(string, seq[HttpHeader])]
      let d = mediaAdapter(r, gets).downloadFile("file:https://contoso.sharepoint.com/x/a.pdf?tempauth=t")
      check d.isOk and d.get.data.len == 8
      check gets[][0][0] == "https://contoso.sharepoint.com/x/a.pdf?tempauth=t"
      check headerOf(gets[][0][1], "Authorization") == ""
      check r.tokenCalls == 0

    test "an inline image is fetched with the bot's token":
      let r = Recorder()
      let gets = new seq[(string, seq[HttpHeader])]
      let d = mediaAdapter(r, gets).downloadFile(
        "image:https://smba.trafficmanager.net/amer/v3/attachments/A1/views/original")
      check d.isOk
      check headerOf(gets[][0][1], "Authorization") == "Bearer tok-1"

    test "anything else is refused before a request":
      let r = Recorder()
      let gets = new seq[(string, seq[HttpHeader])]
      check mediaAdapter(r, gets).downloadFile("image:https://evil.example/x.png").isErr
      check gets[].len == 0 and r.tokenCalls == 0

type Wire = ref object
  tokenForms: seq[string]
  posts: seq[(string, string)]
  puts: seq[(string, string, seq[HttpHeader])]
  putStatus: int

proc wireHttp(w: Wire): HttpRuntimePort =
  result.post = proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      if url.startsWith("https://login.microsoftonline.com/"):
        if "client_assertion" in body: w.tokenForms.add body
        return ok(HttpResponse(status: 200, body: """{"access_token":"tok","expires_in":3600}"""))
      w.posts.add (url, body)
    ok(HttpResponse(status: 201, body: """{"id":"new"}"""))
  result.put = proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      w.puts.add (url, body, headers)
      ok(HttpResponse(status: (if w.putStatus > 0: w.putStatus else: 201), body: "{}"))

proc filesAdapter(w: Wire; tag: string): (TeamsAdapter, string) =
  let dir = tempDir("files_" & tag)
  createDir(dir / "attachments")
  writeFile(dir / "attachments" / "grafico.png", "PNGBYTES")
  writeFile(dir / "attachments" / "relatorio.pdf", "%PDF-1.7 conteudo")
  (newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
                   identityPath = dir / "identities.tsv",
                   conversationsPath = dir / "teams_conversations.json",
                   http = wireHttp(w), clock = proc(): int64 {.gcsafe.} = 1_000), dir)

proc consent(pending, action: string; uploadUrl = "https://contoso-my.sharepoint.com/upload?x=1"): TeamsActivity =
  TeamsActivity(kind: "invoke", name: "fileConsent/invoke", id: "inv-1", serviceUrl: ServiceUrl,
    channelId: "msteams", conversationId: "a:1xyz", conversationType: "personal",
    fromId: "29:1abc", aadObjectId: "aad-belle",
    value: $(%* {"type": "fileUpload", "action": action, "context": {"pending": pending},
                 "uploadInfo": {"name": "relatorio.pdf", "uploadUrl": uploadUrl,
                   "contentUrl": "https://contoso-my.sharepoint.com/personal/belle/relatorio.pdf",
                   "uniqueId": "U-1", "fileType": "pdf"}}))

proc pendingOf(post: string): string =
  parseJson(post)["attachments"][0]["content"]["acceptContext"]["pending"].getStr

proc runFilesTests*() =
  suite "teams — files out (Teams complete, parts 1 and 2)":
    let personal = replyTarget(ServiceUrl, "a:1xyz", "act-1")

    test "a small image goes inline, in one message, no consent":
      let w = Wire()
      let (a, dir) = filesAdapter(w, "img")
      check a.send(OutboundMessage(channel: ckTeams, text: "segue", replyTo: personal,
        mediaUrl: dir / "attachments" / "grafico.png", mediaRoot: dir)).isOk
      check w.posts.len == 1
      let body = parseJson(w.posts[0][1])
      check body["attachments"][0]["contentUrl"].getStr.startsWith("data:image/png;base64,")
      check body["text"].getStr == "segue"

    test "another file in a personal chat: a consent card; accepted, it is uploaded and shown":
      let w = Wire()
      let (a, dir) = filesAdapter(w, "pdf")
      check a.send(OutboundMessage(channel: ckTeams, text: "o relatório", replyTo: personal,
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      check w.posts.len == 1
      let card = parseJson(w.posts[0][1])["attachments"][0]
      check card["contentType"].getStr == "application/vnd.microsoft.teams.card.file.consent"
      check card["content"]["sizeInBytes"].getInt == 17
      check w.puts.len == 0                            ## nothing uploaded before consent
      check a.handleFileConsent(consent(pendingOf(w.posts[0][1]), "accept")).isOk
      check w.puts.len == 1
      check w.puts[0][0] == "https://contoso-my.sharepoint.com/upload?x=1"
      check w.puts[0][1] == "%PDF-1.7 conteudo"
      check ("Content-Range", "bytes 0-16/17") in w.puts[0][2]
      let info = parseJson(w.posts[^1][1])["attachments"][0]
      check info["contentType"].getStr == "application/vnd.microsoft.teams.card.file.info"
      check info["content"]["uniqueId"].getStr == "U-1"
      ## the pending file is gone: a second answer finds nothing
      check a.handleFileConsent(consent(pendingOf(w.posts[0][1]), "accept")).isOk
      check w.puts.len == 1

    test "declined, nothing is uploaded and the person is told":
      let w = Wire()
      let (a, dir) = filesAdapter(w, "decline")
      check a.send(OutboundMessage(channel: ckTeams, replyTo: personal,
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      check a.handleFileConsent(consent(pendingOf(w.posts[0][1]), "decline")).isOk
      check w.puts.len == 0
      check "relatorio.pdf" in parseJson(w.posts[^1][1])["text"].getStr

    test "an upload URL outside SharePoint is refused":
      let w = Wire()
      let (a, dir) = filesAdapter(w, "evil")
      check a.send(OutboundMessage(channel: ckTeams, replyTo: personal,
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      check a.handleFileConsent(consent(pendingOf(w.posts[0][1]), "accept",
                                        uploadUrl = "https://evil.example/u")).isErr
      check w.puts.len == 0

    test "in a group or channel, a file becomes a note; a path outside the paddock too":
      let w = Wire()
      let (a, dir) = filesAdapter(w, "group")
      check a.send(OutboundMessage(channel: ckTeams, text: "segue",
        replyTo: replyTarget(ServiceUrl, "19:abc@thread.v2", "act-9"),
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      check "attachments" notin w.posts[0][1] and "segue" in w.posts[0][1]
      check a.send(OutboundMessage(channel: ckTeams, replyTo: personal,
        mediaUrl: "/etc/passwd", mediaRoot: dir)).isOk
      check "/etc/passwd" notin w.posts[^1][1] and "file.consent" notin w.posts[^1][1]

proc runFileTokenTests*() =
  suite "teams — the file token from a certificate (Teams complete, part 3)":
    proc certAdapter(w: Wire; gets: ref seq[(string, seq[HttpHeader])]; tag: string): (TeamsAdapter, string) =
      let dir = tempDir("cert_" & tag)
      createDir(dir / "attachments")
      writeFile(dir / "attachments" / "relatorio.pdf", "%PDF")
      writeFile(dir / "app.pem", TestCombinedPem)
      var http = wireHttp(w)
      http.get = proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        {.cast(gcsafe).}: gets[].add (url, headers)
        ok(HttpResponse(status: 200, body: "DATA"))
      (newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
                       identityPath = dir / "identities.tsv",
                       conversationsPath = dir / "teams_conversations.json",
                       http = http, clock = proc(): int64 {.gcsafe.} = 1_000,
                       certPath = dir / "app.pem"), dir)

    test "with a certificate, a SharePoint download carries a token got by a client assertion":
      let w = Wire()
      let gets = new seq[(string, seq[HttpHeader])]
      let (a, _) = certAdapter(w, gets, "dl")
      check a.downloadFile("file:https://contoso.sharepoint.com/x/a.pdf").isOk
      check headerOf(gets[][0][1], "Authorization") == "Bearer tok"
      check w.tokenForms.len == 1
      check "client_assertion=" in w.tokenForms[0] and "client_secret" notin w.tokenForms[0]
      check "scope=https%3A%2F%2Fcontoso.sharepoint.com%2F.default" in w.tokenForms[0]

    test "with a certificate, the upload carries the token too":
      let w = Wire()
      let gets = new seq[(string, seq[HttpHeader])]
      let (a, dir) = certAdapter(w, gets, "up")
      check a.send(OutboundMessage(channel: ckTeams, replyTo: replyTarget(ServiceUrl, "a:1xyz", "act-1"),
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      check a.handleFileConsent(consent(pendingOf(w.posts[0][1]), "accept")).isOk
      check headerOf(w.puts[0][2], "Authorization") == "Bearer tok"

    test "a certificate file that cannot be read fails the file calls, with why":
      let dir = tempDir("cert_bad")
      writeFile(dir / "app.pem", "not a pem")
      let a = newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
        identityPath = dir / "identities.tsv", conversationsPath = dir / "c.json",
        http = wireHttp(Wire()), clock = proc(): int64 {.gcsafe.} = 1_000, certPath = dir / "app.pem")
      let r = a.downloadFile("file:https://contoso.sharepoint.com/x/a.pdf")
      check r.isErr and "MICROSOFT_APP_CERT" in r.error

when isMainModule:
  runTests()
  runMediaTests()
  runFilesTests()
  runFileTokenTests()
