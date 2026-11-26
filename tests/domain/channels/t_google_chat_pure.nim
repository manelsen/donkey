## Google Chat, the pure half (second round, front 1): reading an interaction
## event, the claims of Google's token, the service account and its token
## assertion, and the reply. Formats from "Receive and respond to interaction
## events", "Verify requests from Google Chat" and "Authenticate as a Chat
## app" (developers.google.com/workspace/chat).

import std/[base64, json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/google_chat_pure

proc event(text = "@Donkey resume isso"; argument = " resume isso"; space = "DM";
           kind = "MESSAGE"; senderType = "HUMAN"; thread = "spaces/S1/threads/T1"): string =
  $(%* {"type": kind, "eventTime": "2026-11-26T03:00:00Z",
        "message": {"name": "spaces/S1/messages/M1",
                    "sender": {"name": "users/111", "displayName": "Belle",
                               "type": senderType},
                    "text": text, "argumentText": argument,
                    "thread": {"name": thread},
                    "space": {"name": "spaces/S1", "type": space}},
        "space": {"name": "spaces/S1", "type": space}})

proc runTests*() =
  suite "google chat — reading an event":

    test "a message: who, where, the text without the mention":
      let e = parseChatEvent(event()).get
      check e.kind == "MESSAGE" and e.id == "spaces/S1/messages/M1"
      check e.sender == "users/111" and e.displayName == "Belle"
      check e.text == "resume isso" and e.space == "spaces/S1"
      check e.thread == "spaces/S1/threads/T1" and not e.isGroup

    test "a room is a group; without argumentText the text is used":
      let e = parseChatEvent(event("oi", "", space = "ROOM")).get
      check e.isGroup and e.text == "oi"

    test "only human messages with text are turns":
      check parseChatEvent(event(kind = "ADDED_TO_SPACE")).get.isTurn == false
      check parseChatEvent(event(senderType = "BOT")).get.isTurn == false
      check parseChatEvent(event("  ", "  ")).get.isTurn == false
      check parseChatEvent(event()).get.isTurn
      check parseChatEvent("not json").isErr

  suite "google chat — Google's token":

    let now = 1_800_000_000'i64
    proc claims(iss = ChatIssuer; aud = "123456789"; exp = now + 300; iat = now - 10): JsonNode =
      %* {"iss": iss, "aud": aud, "exp": exp, "iat": iat}

    test "issued by Chat for this project, and current":
      check checkChatClaims(claims(), "123456789", now).isOk
      check checkChatClaims(claims(iss = "someone@else"), "123456789", now).isErr
      check checkChatClaims(claims(aud = "999"), "123456789", now).isErr
      check checkChatClaims(claims(exp = now - 400), "123456789", now).isErr
      check checkChatClaims(claims(iat = now + 600), "123456789", now).isErr
      check checkChatClaims(claims(), "", now).isErr   ## no project: nothing passes

  suite "google chat — the service account":

    const Sa = """{"type":"service_account","client_email":"donkey@proj.iam.gserviceaccount.com",
                   "private_key":"-----BEGIN PRIVATE KEY-----\nAAA\n-----END PRIVATE KEY-----\n",
                   "token_uri":"https://oauth2.googleapis.com/token"}"""

    test "the account's email, key and token endpoint":
      let sa = parseServiceAccount(Sa).get
      check sa.clientEmail == "donkey@proj.iam.gserviceaccount.com"
      check "BEGIN PRIVATE KEY" in sa.privateKey
      check sa.tokenUri == "https://oauth2.googleapis.com/token"
      check parseServiceAccount("""{"client_email":"x"}""").isErr

    test "the assertion asks for the chat.bot scope, for one hour":
      let sa = parseServiceAccount(Sa).get
      let input = assertionSigningInput(sa, 1_800_000_000)
      let parts = input.split('.')
      check parts.len == 2
      proc dec(s: string): JsonNode =
        var t = s.replace('-', '+').replace('_', '/')
        while t.len mod 4 != 0: t.add '='
        parseJson(decode(t))
      check dec(parts[0])["alg"].getStr == "RS256"
      let c = dec(parts[1])
      check c["iss"].getStr == sa.clientEmail and c["scope"].getStr == ChatBotScope
      check c["aud"].getStr == sa.tokenUri
      check c["exp"].getInt - c["iat"].getInt == 3600
      check assertionJwt(input, "\x01\x02").startsWith(input & ".")
      check '=' notin assertionJwt(input, "\x01\x02")

    test "the token request and its answer":
      check "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer" in tokenForm("a.b.c")
      let t = parseAccessToken("""{"access_token":"ya29.x","expires_in":3599}""", 1_000_000).get
      check t.token == "ya29.x" and t.renewAtMs > 1_000_000
      check parseAccessToken("""{"error":"invalid_grant"}""", 0).isErr

  suite "google chat — replying":

    test "a reply goes into the thread of the message it answers":
      let e = parseChatEvent(event()).get
      check replyTarget(e) == "spaces/S1|spaces/S1/threads/T1"
      check messagesUrl("spaces/S1|spaces/S1/threads/T1") ==
        "https://chat.googleapis.com/v1/spaces/S1/messages?messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"
      let body = parseJson(messageBody("spaces/S1|spaces/S1/threads/T1", "feito"))
      check body["text"].getStr == "feito" and body["thread"]["name"].getStr == "spaces/S1/threads/T1"
      check not parseJson(messageBody("spaces/S1", "oi")).hasKey("thread")
      check messagesUrl("spaces/S1") == "https://chat.googleapis.com/v1/spaces/S1/messages"

    test "a target that is not a space is refused":
      check validTarget("spaces/S1|spaces/S1/threads/T1")
      check not validTarget("https://evil.example/x")
      check not validTarget("spaces/S1/../../x")

    test "a long reply is split under the message limit":
      check splitForChat("a".repeat(ChatTextChars + 1)).len == 2

proc withAttachments(attachments: JsonNode; text = ""): string =
  var j = parseJson(event(text, ""))
  j["message"]["attachment"] = attachments
  $j

proc runMediaTests*() =
  suite "google chat — attachments (E9.2)":
    let uploaded = %* [{"name": "spaces/S1/messages/M1/attachments/A1",
      "contentName": "foto.png", "contentType": "image/png", "source": "UPLOADED_CONTENT",
      "attachmentDataRef": {"resourceName": "AbC-123_xyz="}}]

    test "an uploaded file comes with the name to download it by":
      let e = parseChatEvent(withAttachments(uploaded)).get
      check e.attachments == @[ChatAttachment(resourceName: "AbC-123_xyz=", name: "foto.png",
                                              mimeType: "image/png")]
      check e.isTurn   ## a file with no text is still a turn

    test "a Drive file has no data to download: named only":
      let e = parseChatEvent(withAttachments(%* [{"contentName": "plano.gdoc",
        "contentType": "application/vnd.google-apps.document", "source": "DRIVE_FILE",
        "driveDataRef": {"driveFileId": "1x"}}], "veja")).get
      check e.attachments == @[ChatAttachment(name: "plano.gdoc",
        mimeType: "application/vnd.google-apps.document", drive: true)]

    test "only a well-formed resource name reaches the media URL":
      check mediaUrl("AbC-123_xyz=").get == "https://chat.googleapis.com/v1/media/AbC-123_xyz=?alt=media"
      check mediaUrl("../../v1/spaces").isErr
      check mediaUrl("").isErr

when isMainModule:
  runTests()
  runMediaTests()
