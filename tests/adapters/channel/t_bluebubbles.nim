## BlueBubbles (iMessage) as a channel (E13.3): sending and one poll round,
## through a fake HTTP port.

import std/[json, os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/http
import donkey/adapters/channel/bluebubbles

type Sent = ref object
  posts: seq[(string, string)]
  page: string

proc fakeHttp(s: Sent): HttpRuntimePort =
  HttpRuntimePort(
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        s.posts.add((url, body))
        if "/message/query" in url: return ok(HttpResponse(status: 200, body: s.page))
      ok(HttpResponse(status: 200, body: """{"status":200,"message":"Message sent!"}""")))

proc adapter(s: Sent): BlueBubblesAdapter =
  let dir = getTempDir() / "donkey_bluebubbles"
  createDir(dir)
  newBlueBubblesAdapter(BlueBubblesSettings(url: "https://mac.example.com", password: "pw"),
                        dir / "ids.tsv", http = fakeHttp(s))

proc runTests*() =
  suite "bluebubbles adapter":
    test "an answer goes to the chat, with a fresh temporary guid each time":
      let s = Sent()
      let a = adapter(s)
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckBlueBubbles, text: "olá",
                                   replyTo: "iMessage;-;+5511999990000")).isOk
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckBlueBubbles, text: "de novo",
                                   replyTo: "iMessage;-;+5511999990000")).isOk
      check s.posts[0][0] == "https://mac.example.com/api/v1/message/text?password=pw"
      let first = parseJson(s.posts[0][1])
      check first["chatGuid"] == %"iMessage;-;+5511999990000" and first["message"] == %"olá"
      check first["tempGuid"].getStr.len >= 16
      check first["tempGuid"] != parseJson(s.posts[1][1])["tempGuid"]

    test "buttons are dropped; a file becomes a note":
      let s = Sent()
      let a = adapter(s)
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckBlueBubbles, text: "Aprovar? /approve x",
        keyboard: @[@[("✅", "approval:x:allow")]], replyTo: "+5511")).isOk
      check parseJson(s.posts[0][1])["chatGuid"] == %"any;-;+5511"
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckBlueBubbles, text: "segue",
                                   mediaUrl: "/p/a.pdf", replyTo: "+5511")).isOk
      check "não pôde ser enviado" in parseJson(s.posts[1][1])["message"].getStr

    test "one poll round: the people's messages and where the next starts":
      let s = Sent(page: """{"status":200,"data":[{"guid":"m-1","text":"oi","isFromMe":false,"dateCreated":1700000001000,"handle":{"address":"+5511"},"chats":[{"guid":"iMessage;-;+5511"}]}]}""")
      let round = pollBlueBubbles(fakeHttp(s), BlueBubblesSettings(url: "https://mac.example.com", password: "pw"),
                                  1700000000000'i64).get
      check s.posts[0][0] == "https://mac.example.com/api/v1/message/query?password=pw"
      check parseJson(s.posts[0][1])["after"] == %1700000000000'i64
      check round.messages.len == 1 and round.messages[0].text == "oi"
      check round.after == 1700000001000'i64

    test "a server over plain http elsewhere is refused (the password would travel in clear)":
      let s = Sent()
      check newBlueBubblesAdapter(BlueBubblesSettings(url: "http://mac.example.com", password: "pw"),
                                  "", http = fakeHttp(s)).configError.len > 0

when isMainModule:
  runTests()
