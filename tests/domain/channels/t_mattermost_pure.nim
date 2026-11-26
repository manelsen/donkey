## Mattermost, the pure half (PRD-roadmap, second round, front 1): reading a
## `posted` event from the WebSocket, the authentication challenge, the reply
## target and the post body. Formats from the Mattermost API reference
## ("WebSocket" and "Create a post", api.mattermost.com / developers.mattermost.com).

import std/[json, options, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/mattermost_pure

const Bot = "botuid"

proc posted(message: string; channelType = "D"; userId = "alice-id";
            mentions: seq[string] = @[]; postType = ""; rootId = ""): string =
  let post = %* {"id": "post-1", "user_id": userId, "channel_id": "chan-1",
                 "root_id": rootId, "message": message, "type": postType}
  var data = %* {"channel_type": channelType, "sender_name": "@alice",
                 "post": $post}
  if mentions.len > 0:
    data["mentions"] = %($(%mentions))
  $(%* {"event": "posted", "data": data, "seq": 7})

proc runTests*() =
  suite "mattermost — reading an event":

    test "a direct message becomes a post to answer":
      let p = parsePostedEvent(posted("oi, tudo bem?"), Bot)
      check p.isSome
      check p.get.id == "post-1" and p.get.userId == "alice-id"
      check p.get.channelId == "chan-1" and p.get.text == "oi, tudo bem?"
      check not p.get.isGroup

    test "the bot's own posts, system posts and other events are skipped":
      check parsePostedEvent(posted("eco", userId = Bot), Bot).isNone
      check parsePostedEvent(posted("alice joined", postType = "system_join_channel"), Bot).isNone
      check parsePostedEvent("""{"event":"hello","data":{},"seq":0}""", Bot).isNone
      check parsePostedEvent("""{"status":"OK","seq_reply":1}""", Bot).isNone
      check parsePostedEvent("not json", Bot).isNone
      check parsePostedEvent(posted("   "), Bot).isNone

    test "in a channel the bot answers only when mentioned":
      let plain = parsePostedEvent(posted("bom dia", channelType = "O"), Bot)
      check plain.isSome and plain.get.isGroup and not plain.get.mentioned
      check not shouldAnswer(plain.get)
      let called = parsePostedEvent(posted("@donkey resume isso", channelType = "O",
                                           mentions = @[Bot]), Bot)
      check called.get.mentioned and shouldAnswer(called.get)
      check shouldAnswer(parsePostedEvent(posted("oi"), Bot).get)   ## a DM always

    test "the bot's mention is taken out of the text":
      check stripMention("@donkey resume isso", "donkey") == "resume isso"
      check stripMention("olá @Donkey, tudo?", "donkey") == "olá , tudo?"
      check stripMention("@donkeyish fica", "donkey") == "@donkeyish fica"
      check stripMention("sem menção", "donkey") == "sem menção"

    test "what the socket queues: posts to answer, the mention taken out":
      let me = MattermostMe(id: Bot, username: "donkey")
      let dm = inboundPost(posted("oi"), me)
      check dm.isSome and dm.get.text == "oi"
      check inboundPost(posted("bom dia", channelType = "O"), me).isNone
      let called = inboundPost(posted("@donkey resume", channelType = "O",
                                      mentions = @[Bot]), me)
      check called.get.text == "resume"
      check inboundPost(posted("@donkey", channelType = "O", mentions = @[Bot]), me).isNone

  suite "mattermost — talking back":

    test "the socket URL follows the server URL":
      check websocketUrl("https://chat.example.com").get == "wss://chat.example.com/api/v4/websocket"
      check websocketUrl("https://chat.example.com/").get == "wss://chat.example.com/api/v4/websocket"
      check websocketUrl("http://localhost:8065").isErr   ## the token never goes in clear
      check websocketUrl("chat.example.com").isErr

    test "the authentication challenge carries the token":
      let j = parseJson(authChallenge("tok-1", 1))
      check j["action"].getStr == "authentication_challenge"
      check j["seq"].getInt == 1 and j["data"]["token"].getStr == "tok-1"

    test "a refused authentication is told apart from other replies":
      check authRefused("""{"status":"FAIL","seq_reply":1,"error":{"id":"api.web_socket_router.not_authenticated.app_error"}}""", 1)
      check not authRefused("""{"status":"OK","seq_reply":1}""", 1)
      check not authRefused("""{"status":"FAIL","seq_reply":5}""", 1)
      check not authRefused("""{"event":"hello","data":{}}""", 1)

    test "the client's ping is an action with its own sequence":
      let j = parseJson(pingAction(4))
      check j["action"].getStr == "ping" and j["seq"].getInt == 4

    test "a reply in a channel goes into the post's thread; a DM gets a plain post":
      let dm = parsePostedEvent(posted("oi"), Bot).get
      check replyTarget(dm) == "chan-1"
      let inChannel = parsePostedEvent(posted("@donkey oi", channelType = "O",
                                              mentions = @[Bot]), Bot).get
      check replyTarget(inChannel) == "chan-1:post-1"
      let inThread = parsePostedEvent(posted("@donkey e agora?", channelType = "O",
                                             mentions = @[Bot], rootId = "root-9"), Bot).get
      check replyTarget(inThread) == "chan-1:root-9"

    test "the post body names the channel and, in a thread, its root":
      let flat = parseJson(postBody("chan-1", "resposta"))
      check flat["channel_id"].getStr == "chan-1" and flat["message"].getStr == "resposta"
      check not flat.hasKey("root_id")
      let threaded = parseJson(postBody("chan-1:root-9", "resposta"))
      check threaded["channel_id"].getStr == "chan-1" and threaded["root_id"].getStr == "root-9"

    test "a long answer is split under the post limit":
      let parts = splitForMattermost("a".repeat(MattermostPostChars + 10))
      check parts.len == 2 and parts[0].len <= MattermostPostChars

    test "the bot's identity comes from users/me":
      let me = parseMe("""{"id":"botuid","username":"donkey","is_bot":true}""")
      check me.get.id == "botuid" and me.get.username == "donkey"
      check parseMe("""{"message":"invalid token","status_code":401}""").isErr

  suite "mattermost — catching up after a drop":

    test "a live post carries when it was written":
      let post = %* {"id": "p9", "user_id": "alice-id", "channel_id": "chan-1",
                     "message": "oi", "type": "", "create_at": 1_700_000_000_123}
      let frame = $(%* {"event": "posted", "data": {"channel_type": "D", "post": $post}})
      check parsePostedEvent(frame, Bot).get.createdMs == 1_700_000_000_123

    test "the bot's channels: id and type":
      let chans = parseChannels("""[{"id":"c1","type":"D"},{"id":"c2","type":"O"},{"x":1}]""")
      check chans == @[("c1", "D"), ("c2", "O")]

    test "posts since a time: oldest first, the bot's own and system posts out, mentions required in a channel":
      let me = MattermostMe(id: Bot, username: "donkey")
      let body = $(%* {"order": ["p3", "p2", "p1", "p0"], "posts": {
        "p0": {"id": "p0", "user_id": "alice-id", "channel_id": "c2", "message": "bom dia", "type": "", "create_at": 30},
        "p1": {"id": "p1", "user_id": "alice-id", "channel_id": "c2", "message": "@donkey resume", "type": "", "create_at": 10},
        "p2": {"id": "p2", "user_id": Bot, "channel_id": "c2", "message": "@donkey eco", "type": "", "create_at": 20},
        "p3": {"id": "p3", "user_id": "x", "channel_id": "c2", "message": "joined", "type": "system_join_channel", "create_at": 40}}})
      let posts = postsSince(body, "O", me, sinceMs = 5)
      check posts.len == 1
      check posts[0].id == "p1" and posts[0].text == "resume" and posts[0].isGroup
      let dm = postsSince(body.replace("\"c2\"", "\"d1\""), "D", me, sinceMs = 5)
      check dm.len == 2 and dm[0].id == "p1" and dm[1].id == "p0"   ## a DM needs no mention
      check postsSince(body, "O", me, sinceMs = 15).len == 0          ## p1 is older
      check postsSince("not json", "O", me, 0).len == 0

when isMainModule:
  runTests()
