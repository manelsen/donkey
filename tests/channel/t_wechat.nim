import std/[strutils, unittest]
import results
import donkey/adapters/channel/wechat

suite "WeChatAdapter":

  test "parseWebhookXml reads text event":
    let xml = """
<xml>
  <ToUserName><![CDATA[toUser]]></ToUserName>
  <FromUserName><![CDATA[open-id-1]]></FromUserName>
  <CreateTime>123456</CreateTime>
  <MsgType><![CDATA[text]]></MsgType>
  <Content><![CDATA[hello donkey]]></Content>
  <MsgId>99</MsgId>
</xml>"""
    let event = parseWebhookXml(xml).get()
    check event.fromUser == "open-id-1"
    check event.msgType == "text"
    check event.content == "hello donkey"
    check event.msgId == "99"

  test "buildOAuthUrl includes app id scope and state":
    let adapter = newWeChatAdapter("wx-app", "secret", "token", "tpl", "/tmp/wechat_ids.tsv")
    let url = adapter.buildOAuthUrl("https://example.com/callback", "abc123")
    check url.find("appid=wx-app") >= 0
    check url.find("scope=snsapi_userinfo") >= 0
    check url.find("state=abc123") >= 0
