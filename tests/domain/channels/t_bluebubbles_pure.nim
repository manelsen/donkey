## BlueBubbles (iMessage) as a channel (E13.3), the pure half: polling the
## server's message query and sending text, both with the server password.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/bluebubbles_pure

const Page = """{"status":200,"message":"Success","data":[
 {"guid":"m-1","text":"oi","isFromMe":false,"dateCreated":1700000001000,
  "handle":{"address":"+5511999990000"},"chats":[{"guid":"iMessage;-;+5511999990000","style":45}],"attachments":[]},
 {"guid":"m-2","text":"minha resposta","isFromMe":true,"dateCreated":1700000002000,
  "handle":null,"chats":[{"guid":"iMessage;-;+5511999990000"}]},
 {"guid":"m-3","text":"no grupo","isFromMe":false,"dateCreated":1700000003000,
  "handle":{"address":"bob@icloud.com"},"chats":[{"guid":"iMessage;+;chat123","style":43}]},
 {"guid":"m-4","text":"","isFromMe":false,"dateCreated":1700000004000,
  "handle":{"address":"ana@icloud.com"},"attachments":[{"guid":"a-1","mimeType":"image/jpeg"}]}
]}"""

proc runTests*() =
  suite "bluebubbles":
    test "a page: one-to-one messages from people in; Donkey's own and groups out":
      let got = parseMessagePage(Page).get
      check got.messages.len == 2
      check got.messages[0] == BlueMessage(guid: "m-1", address: "+5511999990000",
        chatGuid: "iMessage;-;+5511999990000", text: "oi", attachments: 0)
      ## no chat in the answer: the one-to-one chat is the address's
      check got.messages[1] == BlueMessage(guid: "m-4", address: "ana@icloud.com",
        chatGuid: "any;-;ana@icloud.com", text: "", attachments: 1)
      check got.newest == 1700000004000'i64   ## every message seen counts, Donkey's own too
      check parseMessagePage("""{"status":401,"message":"Unauthorized"}""").isErr
      check parseMessagePage("nope").isErr
      let bare = parseMessagePage("""{"status":200,"data":[{"guid":"m-9","text":"x","isFromMe":false,"handle":{"address":"a@b.c"}}]}""").get
      check bare.messages[0].attachments == 0

    test "the query: what came after, oldest first, with the chat and the sender":
      check parseJson(queryBody(1700000000000'i64)) == %* {"with": ["chat", "handle"],
        "after": 1700000000000'i64, "sort": "ASC", "limit": 100}
      check apiUrl("https://mac.example.com/", "/api/v1/message/query", "s3n h4") ==
        "https://mac.example.com/api/v1/message/query?password=s3n%20h4"

    test "sending: the chat, the text, a temporary guid":
      check parseJson(sendTextBody("iMessage;-;+5511999990000", "olá", "tmp-1")) ==
        %* {"chatGuid": "iMessage;-;+5511999990000", "message": "olá", "tempGuid": "tmp-1",
            "method": "apple-script"}

    test "a reply target: the chat guid as is, or the one-to-one chat of an address":
      check chatFor("iMessage;-;+5511") == "iMessage;-;+5511"
      check chatFor("+5511") == "any;-;+5511"

    test "the server: https, or http on this machine (the password travels in the URL)":
      check validServerUrl("https://mac.example.com")
      check validServerUrl("http://127.0.0.1:1234")
      check not validServerUrl("http://mac.example.com")
      check not validServerUrl("ftp://x")

when isMainModule:
  runTests()
