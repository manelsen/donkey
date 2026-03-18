## FeishuAdapter unit tests — pure functions only (signature, parse, build).

import std/[json, options, unittest]
import donkey/adapters/channel/feishu

suite "feishuSignature":

  test "deterministic — same inputs same output":
    let s1 = feishuSignature("1700000000", "nonce123", "mysecret", "helo body")
    let s2 = feishuSignature("1700000000", "nonce123", "mysecret", "helo body")
    check s1 == s2

  test "different body produces different signature":
    let s1 = feishuSignature("1700000000", "nonce123", "mysecret", "body1")
    let s2 = feishuSignature("1700000000", "nonce123", "mysecret", "body2")
    check s1 != s2

  test "known value — sha256(timestamp+nonce+secret+body)":
    ## sha256("1700000000" & "nonce123" & "mysecret" & "helobody")
    ## = f0efec7a8c7436f35f2b609fef6774876e05828895b5f8a91313b696a0b1b0e8
    let sig = feishuSignature("1700000000", "nonce123", "mysecret", "helobody")
    check sig == "f0efec7a8c7436f35f2b609fef6774876e05828895b5f8a91313b696a0b1b0e8"

suite "verifyFeishuSig":

  test "valid signature passes":
    let body = """{"key":"value"}"""
    let sig  = feishuSignature("111", "nnn", "sec", body)
    check verifyFeishuSig("111", "nnn", "sec", body, sig)

  test "wrong secret fails":
    let body = """{"key":"value"}"""
    let sig  = feishuSignature("111", "nnn", "sec", body)
    check not verifyFeishuSig("111", "nnn", "bad", body, sig)

  test "tampered body fails":
    let body = """{"key":"value"}"""
    let sig  = feishuSignature("111", "nnn", "sec", body)
    check not verifyFeishuSig("111", "nnn", "sec", """{"key":"TAMPERED"}""", sig)

suite "parseFeishuEvent":

  test "url_verification returns Some with challenge":
    let body = """{"challenge":"TestChallenge123","token":"mytoken","type":"url_verification"}"""
    let evt = parseFeishuEvent(body)
    require evt.isSome
    check evt.get.eventType == "url_verification"
    check evt.get.challenge == "TestChallenge123"

  test "text message returns Some with correct fields":
    let body = """{
      "schema": "2.0",
      "header": {
        "event_type": "im.message.receive_v1",
        "event_id": "ev123"
      },
      "event": {
        "sender": {
          "sender_id": {"open_id": "ou_abc123"}
        },
        "message": {
          "message_id": "om_xyz",
          "chat_id":    "oc_chat1",
          "message_type": "text",
          "content": "{\"text\":\"Hello Donkey\"}"
        }
      }
    }"""
    let evt = parseFeishuEvent(body)
    require evt.isSome
    check evt.get.eventType == "im.message.receive_v1"
    check evt.get.openId    == "ou_abc123"
    check evt.get.msgType   == "text"
    check evt.get.content   == "Hello Donkey"
    check evt.get.msgId     == "om_xyz"
    check evt.get.chatId    == "oc_chat1"

  test "non-text message returns Some with empty content":
    let body = """{
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "sender": {"sender_id": {"open_id": "ou_abc"}},
        "message": {
          "message_id": "om_1",
          "chat_id": "oc_1",
          "message_type": "image",
          "content": "{\"image_key\":\"img_xxx\"}"
        }
      }
    }"""
    let evt = parseFeishuEvent(body)
    require evt.isSome
    check evt.get.msgType == "image"
    check evt.get.content == ""

  test "malformed JSON returns None":
    check parseFeishuEvent("not json {{{").isNone

  test "missing header returns None":
    check parseFeishuEvent("""{"event": {}}""").isNone

suite "buildSendBody":

  test "produces correct JSON for text message":
    let body = buildSendBody("ou_abc123", "open_id", "Hi there!")
    check body["receive_id"].getStr()               == "ou_abc123"
    check body["msg_type"].getStr()                 == "text"
    let content = parseJson(body["content"].getStr())
    check content["text"].getStr()                  == "Hi there!"

  test "receive_id_type param is preserved":
    let body = buildSendBody("oc_chat1", "chat_id", "Hello")
    check body["receive_id"].getStr() == "oc_chat1"

suite "challengeResponse":

  test "returns JSON with challenge echoed":
    let resp = challengeResponse("abc123")
    check resp["challenge"].getStr() == "abc123"
