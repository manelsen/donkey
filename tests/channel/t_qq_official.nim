import std/[json, unittest]
import results
import donkey/adapters/channel/qq_official
import donkey/core/types
import donkey/domain/message

suite "QQOfficialAdapter":

  test "parseOfficialEventJson reads c2c message payload envelope":
    let payload = """{
      "t":"C2C_MESSAGE_CREATE",
      "d":{
        "id":"msg-1",
        "content":"hello",
        "author":{"user_openid":"user-123"}
      }
    }"""
    let event = parseOfficialEventJson(payload).get()
    check event.messageType == "private"
    check event.userId == "user-123"
    check event.messageId == "msg:msg-1"
    check event.content == "hello"

  test "parseOfficialEventJson reads group message payload envelope":
    let payload = """{
      "t":"GROUP_AT_MESSAGE_CREATE",
      "d":{
        "id":"msg-2",
        "content":"@bot hi",
        "group_openid":"group-456",
        "author":{"member_openid":"member-789"}
      }
    }"""
    let event = parseOfficialEventJson(payload).get()
    check event.messageType == "group"
    check event.userId == "member-789"
    check event.groupId == "group-456"
    check event.messageId == "msg:msg-2"

  test "parseInteractionEventNode normalizes callback events":
    let payload = parseJson("""{
      "id":"evt-9",
      "scene":"group",
      "group_openid":"group-1",
      "group_member_openid":"member-2",
      "data":{"resolved":{"button_data":"models:provider:zai"}}
    }""")
    let event = parseInteractionEventNode(payload).get()
    check event.messageType == "group"
    check event.userId == "member-2"
    check event.groupId == "group-1"
    check event.messageId == "event:evt-9"
    check event.content == "/callback models:provider:zai"

  test "buildSendUrl distinguishes user and group openid":
    check buildSendUrl(QQOfficialDefaultApiBase, "user-openid").get() ==
      "https://api.sgroup.qq.com/v2/users/user-openid/messages"
    check buildSendUrl(QQOfficialDefaultApiBase, "group:group-openid").get() ==
      "https://api.sgroup.qq.com/v2/groups/group-openid/messages"

  test "buildSendBody includes passive reply metadata when replyTo exists":
    let body = buildSendBody(OutboundMessage(
      userId: UserId("u1"),
      channel: ckQQ,
      text: "pong",
      replyTo: "msg:msg-77",
    )).get()
    check body["msg_type"].getInt() == 0
    check body["content"].getStr() == "pong"
    check body["msg_id"].getStr() == "msg-77"
    check body["msg_seq"].getInt() == 1

  test "buildSendBody uses event_id for interaction replies":
    let body = buildSendBody(OutboundMessage(
      userId: UserId("u1"),
      channel: ckQQ,
      text: "ok",
      replyTo: "event:evt-77",
    )).get()
    check body["msg_type"].getInt() == 0
    check body["content"].getStr() == "ok"
    check body["event_id"].getStr() == "evt-77"
    check not body.hasKey("msg_id")

  test "buildKeyboardBody can lock buttons to one user":
    let body = buildKeyboardBody(
      "Escolha:",
      @[@[("Z.AI", "models:provider:zai")]],
      "event:evt-1",
      @["member-123"],
    )
    let action = body["keyboard"]["content"]["rows"][0]["buttons"][0]["action"]
    check body["event_id"].getStr() == "evt-1"
    check action["permission"]["type"].getInt() == 0
    check action["permission"]["specify_user_ids"][0].getStr() == "member-123"

  test "qq keyboard button styling highlights current item and deemphasizes nav":
    check qqKeyboardButtonStyle("✓ groq", "models:set:groq:llama") == 1
    check qqKeyboardButtonStyle("← voltar", "models:back") == 0
    check qqKeyboardButtonStyle("próxima →", "models:page:groq:1") == 0
    check qqKeyboardVisitedLabel("groq") == "✓ groq"
    check qqKeyboardVisitedLabel("✓ groq") == "✓ groq"

  test "parseAccessTokenResponse reads official token body":
    let token = parseAccessTokenResponse("""{
      "access_token":"abc123",
      "expires_in":"7200"
    }""").get()
    check token.accessToken == "abc123"
    check token.expiresInSec == 7200

  test "qqBotHeaders and buildAccessTokenUrl use official auth format":
    check buildAccessTokenUrl(QQOfficialDefaultTokenBase) ==
      "https://bots.qq.com/app/getAppAccessToken"
    check qqBotHeaders("tok-1")[0] == ("Authorization", "QQBot tok-1")
