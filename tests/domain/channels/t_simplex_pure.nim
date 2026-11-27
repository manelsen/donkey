## SimpleX as a channel (E13.2): the simplex-chat CLI's WebSocket API, pure.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/simplex_pure

const Incoming = """{"resp":{"type":"newChatItems","user":{"userId":1},"chatItems":[
 {"chatInfo":{"type":"direct","contact":{"contactId":5,"localDisplayName":"ana","profile":{"displayName":"Ana"}}},
  "chatItem":{"chatDir":{"type":"directRcv"},"meta":{"itemId":41},
              "content":{"type":"rcvMsgContent","msgContent":{"type":"text","text":"oi, Donkey"}}}},
 {"chatInfo":{"type":"direct","contact":{"contactId":5,"localDisplayName":"ana"}},
  "chatItem":{"chatDir":{"type":"directSnd"},"meta":{"itemId":42},
              "content":{"type":"sndMsgContent","msgContent":{"type":"text","text":"minha resposta"}}}},
 {"chatInfo":{"type":"group","groupInfo":{"groupId":3}},
  "chatItem":{"chatDir":{"type":"groupRcv"},"meta":{"itemId":43},
              "content":{"type":"rcvMsgContent","msgContent":{"type":"text","text":"num grupo"}}}},
 {"chatInfo":{"type":"direct","contact":{"contactId":6,"localDisplayName":"bob"}},
  "chatItem":{"chatDir":{"type":"directRcv"},"meta":{"itemId":44},
              "content":{"type":"rcvMsgContent","msgContent":{"type":"image","text":"","image":"data:..."}}}}
]}}"""

proc runTests*() =
  suite "simplex":
    test "a direct text message in; the bot's own, groups and non-text out":
      let got = parseSimplexEvent(Incoming)
      check got.messages == @[SimplexMessage(contactId: 5, name: "ana", text: "oi, Donkey", itemId: 41)]
      check got.unread == @[(contactId: 6'i64, name: "bob", kind: "image", itemId: 44'i64)]

    test "other events and command answers bring nothing":
      check parseSimplexEvent("""{"resp":{"type":"contactConnected","contact":{"contactId":7}}}""").messages.len == 0
      check parseSimplexEvent("""{"corrId":"3","resp":{"type":"newChatItems","chatItems":[]}}""").messages.len == 0
      check parseSimplexEvent("not json").messages.len == 0

    test "sending: /_send to the contact, the text as a composed message":
      let cmd = parseJson(sendCommand("9", 5, "olá \"Ana\""))
      check cmd["corrId"] == %"9"
      check cmd["cmd"].getStr.startsWith("/_send @5 json ")
      let composed = parseJson(cmd["cmd"].getStr["/_send @5 json ".len .. ^1])
      check composed == %* [{"msgContent": {"type": "text", "text": "olá \"Ana\""}, "mentions": {}}]

    test "the CLI's address: ws on this machine only (it has no authentication)":
      check parseSimplexUrl("ws://127.0.0.1:5225").get == (host: "127.0.0.1", port: 5225)
      check parseSimplexUrl("ws://localhost:5225").get.host == "localhost"
      check parseSimplexUrl("").get == (host: "127.0.0.1", port: 5225)   ## the default
      check parseSimplexUrl("ws://10.0.0.5:5225").isErr
      check parseSimplexUrl("wss://127.0.0.1:5225").isErr
      check parseSimplexUrl("ws://127.0.0.1:x").isErr

    test "long answers in pieces":
      check simplexPieces("a".repeat(SimplexMaxMessageBytes + 5)).len == 2

when isMainModule:
  runTests()
