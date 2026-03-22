import std/unittest
import std/[tables, strutils]
import donkey/core/pipeops
import donkey/adapters/channel/wechat

suite "WeChatAdapter":

  test "verifyWebhookSignature validates correctly":
    # WeChat verification: sort([token, timestamp, nonce]), SHA1, compare
    check verifyWebhookSignature("mytoken", "1409735669", "1320562132",
                                 "79662182ab7ba91fa70b2446ff8866b0ef5f4f7b")

  test "verifyWebhookSignature rejects wrong signature":
    check not verifyWebhookSignature("mytoken", "1409735669", "1320562132",
                                     "0000000000000000000000000000000000000000")

  test "parseWebhookXml extracts text message":
    let xml = """<xml>
<ToUserName><![CDATA[gh_abc123]]></ToUserName>
<FromUserName><![CDATA[openid_user_1]]></FromUserName>
<MsgType><![CDATA[text]]></MsgType>
<Content><![CDATA[hello world]]></Content>
<MsgId>1234567890</MsgId>
</xml>"""
    let r = parseWebhookXml(xml)
    check r.isOk
    check r.value.fromUser == "openid_user_1"
    check r.value.msgType  == "text"
    check r.value.content  == "hello world"
    check r.value.msgId    == "1234567890"

  test "parseWebhookXml rejects missing FromUserName":
    let xml = "<xml><MsgType><![CDATA[text]]></MsgType></xml>"
    check parseWebhookXml(xml).isErr

  test "parseWebhookXml handles non-CDATA fields":
    let xml = "<xml><FromUserName>plain_id</FromUserName><MsgType>text</MsgType></xml>"
    let r = parseWebhookXml(xml)
    check r.isOk
    check r.value.fromUser == "plain_id"

  test "parseQueryString extracts all params":
    let q = "signature=abc&timestamp=123&nonce=xyz&echostr=hello"
    let t = parseQueryString(q)
    check t.getOrDefault("signature") == "abc"
    check t.getOrDefault("timestamp") == "123"
    check t.getOrDefault("nonce") == "xyz"
    check t.getOrDefault("echostr") == "hello"

  test "parseQueryString handles empty query":
    check parseQueryString("").len == 0

  test "parseQueryString handles missing value":
    let t = parseQueryString("key=")
    check t.getOrDefault("key") == ""

  test "enqueueWebhookXml and tryRecvEvent round-trip":
    var a = newWeChatAdapter("appid", "secret", "mytoken", "", "/tmp/wechat_test_ids.tsv")
    let xml = """<xml>
<FromUserName><![CDATA[uid1]]></FromUserName>
<MsgType><![CDATA[text]]></MsgType>
<Content><![CDATA[ping]]></Content>
<MsgId>99</MsgId>
</xml>"""
    let r = a.enqueueWebhookXml(xml)
    check r.isOk
    let (ok, event) = a.tryRecvEvent()
    check ok
    check event.content == "ping"
    check event.fromUser == "uid1"

  test "tryRecvEvent returns false on empty queue":
    var a = newWeChatAdapter("appid", "secret", "tok", "", "/tmp/wechat_test_empty.tsv")
    let (ok, _) = a.tryRecvEvent()
    check not ok
