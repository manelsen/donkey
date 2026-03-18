## WeComAdapter unit tests — pure functions only (signature, parse, build).
## HTTP calls and background thread are exercised in integration tests.

import std/[json, options, unittest]
import donkey/adapters/channel/wecom

suite "wecomSignature":

  test "deterministic — same inputs same output":
    let s1 = wecomSignature("mytoken", "1700000000", "abcnonce")
    let s2 = wecomSignature("mytoken", "1700000000", "abcnonce")
    check s1 == s2

  test "order-independent — sorts before hashing":
    ## token, ts, nonce sorted: depends on values; just confirm it's stable.
    let s1 = wecomSignature("aaa", "111", "zzz")
    let s2 = wecomSignature("zzz", "111", "aaa")
    ## Both should produce the same SHA-1 because sort([token,ts,nonce]).join("") is the same.
    check s1 == s2

  test "known value — SHA-1 of sorted join":
    ## sort(["token", "12345", "nonce"]) = ["12345", "nonce", "token"]
    ## join = "12345noncetoken"
    ## sha1("12345noncetoken") = ed162902f469af275c5a5909c5d782a55d14684e
    let sig = wecomSignature("token", "12345", "nonce")
    check sig == "ed162902f469af275c5a5909c5d782a55d14684e"

suite "verifyWeComSig":

  test "valid signature passes":
    let sig = wecomSignature("tok", "9999", "xyz")
    check verifyWeComSig("tok", "9999", "xyz", sig)

  test "wrong token fails":
    let sig = wecomSignature("tok", "9999", "xyz")
    check not verifyWeComSig("bad", "9999", "xyz", sig)

  test "wrong timestamp fails":
    let sig = wecomSignature("tok", "9999", "xyz")
    check not verifyWeComSig("tok", "0000", "xyz", sig)

  test "tampered signature fails":
    check not verifyWeComSig("tok", "9999", "xyz", "0000000000000000000000000000000000000000")

suite "parseWeComMessage":

  test "text message returns Some with correct fields":
    let xml = """<xml>
  <ToUserName><![CDATA[ww_corp]]></ToUserName>
  <FromUserName><![CDATA[user_abc]]></FromUserName>
  <MsgType><![CDATA[text]]></MsgType>
  <Content><![CDATA[Hello Donkey]]></Content>
  <MsgId>12345678</MsgId>
</xml>"""
    let evt = parseWeComMessage(xml)
    require evt.isSome
    check evt.get.toUser    == "ww_corp"
    check evt.get.fromUser  == "user_abc"
    check evt.get.msgType   == "text"
    check evt.get.content   == "Hello Donkey"
    check evt.get.msgId     == "12345678"

  test "event message (non-text) returns Some with empty content":
    let xml = """<xml>
  <ToUserName><![CDATA[ww_corp]]></ToUserName>
  <FromUserName><![CDATA[user_abc]]></FromUserName>
  <MsgType><![CDATA[event]]></MsgType>
  <Event><![CDATA[subscribe]]></Event>
  <MsgId>99</MsgId>
</xml>"""
    let evt = parseWeComMessage(xml)
    require evt.isSome
    check evt.get.msgType == "event"
    check evt.get.content == ""

  test "malformed XML returns None":
    let evt = parseWeComMessage("not xml at all <<<")
    check evt.isNone

suite "buildSendBody":

  test "produces correct JSON structure":
    let body = buildSendBody(agentId = 1, toUser = "user_abc", text = "Hi!")
    check body["touser"].getStr()         == "user_abc"
    check body["msgtype"].getStr()        == "text"
    check body["agentid"].getInt()        == 1
    check body["text"]["content"].getStr() == "Hi!"

  test "special chars in text are preserved":
    let body = buildSendBody(1, "u", "你好 & <test>")
    check body["text"]["content"].getStr() == "你好 & <test>"
