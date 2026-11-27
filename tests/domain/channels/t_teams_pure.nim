## Microsoft Teams, the pure half (PRD-roadmap E2.2–E2.3): reading an
## activity, the reply target, the reply body and the app token response.
## Formats from "Send and receive messages with the Bot Connector API" and
## "Authenticate requests with the Bot Connector API" (learn.microsoft.com,
## checked 25/11/2026).

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/teams_pure

const ServiceUrl = "https://smba.trafficmanager.net/amer/"

proc personal(text = "oi, tudo bem?"): JsonNode =
  %* {"type": "message", "id": "1700000000001", "timestamp": "2026-11-25T19:00:00Z",
      "serviceUrl": ServiceUrl, "channelId": "msteams",
      "from": {"id": "29:1abc", "name": "Belle", "aadObjectId": "aad-belle"},
      "conversation": {"conversationType": "personal", "id": "a:1xyz",
                       "tenantId": "tenant-1"},
      "recipient": {"id": "28:bot-app", "name": "Donkey"},
      "textFormat": "plain", "text": text,
      "channelData": {"tenant": {"id": "tenant-1"}}}

proc inChannel(text: string): JsonNode =
  result = personal(text)
  result["conversation"] = %* {"conversationType": "channel", "isGroup": true,
    "id": "19:chan@thread.tacv2;messageid=1700000000000", "tenantId": "tenant-1"}
  result["replyToId"] = %"1700000000000"

proc runTests*() =
  suite "teams — reading an activity":

    test "a personal message gives its sender, conversation and text":
      let a = parseActivity(personal()).get
      check a.kind == "message"
      check a.id == "1700000000001"
      check a.serviceUrl == ServiceUrl
      check a.conversationId == "a:1xyz" and a.conversationType == "personal"
      check a.fromId == "29:1abc" and a.fromName == "Belle"
      check a.aadObjectId == "aad-belle"
      check a.tenantId == "tenant-1"
      check a.text == "oi, tudo bem?"
      check not a.isGroup

    test "the sender is known by the Entra id when there is one":
      check parseActivity(personal()).get.senderKey == "aad-belle"
      var p = personal()
      p["from"].delete("aadObjectId")
      check parseActivity(p).get.senderKey == "29:1abc"

    test "in a channel the bot's mention is taken out of the text":
      let a = parseActivity(inChannel("<at>Donkey</at> resume a reunião")).get
      check a.text == "resume a reunião"
      check a.isGroup
      check a.replyToId == "1700000000000"

    test "another person's mention stays, as plain text":
      let a = parseActivity(inChannel("<at>Donkey</at> pergunta à <at>Belle</at> o prazo")).get
      check a.text == "pergunta à Belle o prazo"

    test "a few entities Teams escapes come back as characters":
      check parseActivity(personal("a &amp; b &lt;c&gt;&nbsp;d")).get.text == "a & b <c> d"

    test "an activity without the essentials is refused":
      check parseActivity(%* {"type": "message"}).isErr
      check parseActivity(%* []).isErr
      var p = personal()
      p.delete("serviceUrl")
      check parseActivity(p).isErr

    test "other activity types are read, so the runtime can skip them":
      var p = personal()
      p["type"] = %"conversationUpdate"
      p.delete("text")
      check parseActivity(p).get.kind == "conversationUpdate"

  suite "teams — the reply target":

    test "service, conversation and message travel together and come back":
      let target = replyTarget(ServiceUrl, "19:chan@thread.tacv2;messageid=1", "1700")
      let back = parseReplyTarget(target).get
      check back.serviceUrl == ServiceUrl
      check back.conversationId == "19:chan@thread.tacv2;messageid=1"
      check back.activityId == "1700"

    test "a target without a message id sends to the conversation":
      let back = parseReplyTarget(replyTarget(ServiceUrl, "a:1xyz", "")).get
      check back.activityId == ""

    test "a target that is not one is refused":
      check parseReplyTarget("").isErr
      check parseReplyTarget("a:1xyz").isErr
      check parseReplyTarget("|a|b").isErr

    test "the send address replies in the thread when there is a message":
      check activitiesUrl(ServiceUrl, "a:1xyz", "") ==
        "https://smba.trafficmanager.net/amer/v3/conversations/a%3A1xyz/activities"
      check activitiesUrl(ServiceUrl, "19:x@thread.tacv2;messageid=1", "1700") ==
        "https://smba.trafficmanager.net/amer/v3/conversations/" &
        "19%3Ax%40thread.tacv2%3Bmessageid%3D1/activities/1700"
      check activitiesUrl("https://smba.trafficmanager.net/amer", "a:1", "").startsWith(
        "https://smba.trafficmanager.net/amer/v3/")

    test "only a service on an allowed host is used":
      check serviceHostAllowed(ServiceUrl, @["smba.trafficmanager.net"])
      check not serviceHostAllowed("http://smba.trafficmanager.net/amer/", @["smba.trafficmanager.net"])
      check not serviceHostAllowed("https://evil.trafficmanager.net/", @["smba.trafficmanager.net"])
      check not serviceHostAllowed("https://smba.trafficmanager.net.evil.com/", @["smba.trafficmanager.net"])
      check serviceHostOf(ServiceUrl) == "smba.trafficmanager.net"

  suite "teams — sending":

    test "a reply is Markdown, in the thread":
      let body = messageBody("**pronto**", "1700")
      check body["type"].getStr == "message"
      check body["textFormat"].getStr == "markdown"
      check body["text"].getStr == "**pronto**"
      check body["replyToId"].getStr == "1700"
      check not messageBody("x", "").hasKey("replyToId")

    test "the app token request asks for the Bot Framework scope":
      let form = tokenForm("app-123", "s3cr&t")
      check "grant_type=client_credentials" in form
      check "client_id=app-123" in form
      check "client_secret=s3cr%26t" in form
      check "scope=https%3A%2F%2Fapi.botframework.com%2F.default" in form
      check tokenUrl("tenant-1") ==
        "https://login.microsoftonline.com/tenant-1/oauth2/v2.0/token"
      check tokenUrl("") ==
        "https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token"

    test "the token response gives the token and when to renew it":
      let t = parseTokenResponse("""{"token_type":"Bearer","expires_in":3600,
        "ext_expires_in":3600,"access_token":"abc"}""", nowMs = 1_000).get
      check t.token == "abc"
      check t.renewAtMs == 1_000 + (3600 - 300) * 1000
      check parseTokenResponse("""{"error":"invalid_client"}""", 0).isErr
      check parseTokenResponse("nope", 0).isErr

    test "long text is cut in pieces Teams accepts":
      let pieces = splitForTeams("a".repeat(TeamsChunkChars * 2 + 10))
      check pieces.len == 3
      for p in pieces:
        check p.len <= TeamsChunkChars
      check splitForTeams("curto") == @["curto"]

proc runMediaTests*() =
  suite "teams — attachments in (E9.4)":
    test "a file in a personal chat comes with its pre-authenticated download URL":
      var p = personal("veja")
      p["attachments"] = %* [{"contentType": "application/vnd.microsoft.teams.file.download.info",
        "name": "plano.pdf", "content": {"downloadUrl": "https://contoso.sharepoint.com/x/plano.pdf?tempauth=abc",
                                          "fileType": "pdf"}}]
      let a = parseActivity(p).get
      check a.attachments == @[TeamsAttachment(fileId: "file:https://contoso.sharepoint.com/x/plano.pdf?tempauth=abc",
                                               name: "plano.pdf", mimeType: "application/pdf")]

    test "an inline image comes with its content URL, fetched with the bot's token":
      var p = personal("")
      p["attachments"] = %* [{"contentType": "image/png",
        "contentUrl": "https://smba.trafficmanager.net/amer/v3/attachments/A1/views/original"},
        {"contentType": "text/html", "content": "<p>oi</p>"}]
      let a = parseActivity(p).get
      check a.attachments == @[TeamsAttachment(
        fileId: "image:https://smba.trafficmanager.net/amer/v3/attachments/A1/views/original",
        mimeType: "image/png")]   ## the HTML copy of the message is not an attachment

    test "a file only from SharePoint, an image only from the Bot Framework service":
      check teamsDownload("file:https://contoso.sharepoint.com/x/a.pdf", @["smba.trafficmanager.net"]).get ==
        (url: "https://contoso.sharepoint.com/x/a.pdf", withToken: false)
      check teamsDownload("image:https://smba.trafficmanager.net/amer/v3/attachments/A1", @["smba.trafficmanager.net"]).get ==
        (url: "https://smba.trafficmanager.net/amer/v3/attachments/A1", withToken: true)
      check teamsDownload("file:https://evil.example/a.pdf", @["smba.trafficmanager.net"]).isErr
      check teamsDownload("image:https://evil.example/a.png", @["smba.trafficmanager.net"]).isErr
      check teamsDownload("file:http://contoso.sharepoint.com/a.pdf", @["smba.trafficmanager.net"]).isErr
      check teamsDownload("other", @["smba.trafficmanager.net"]).isErr
      check teamsDownload("file:", @["smba.trafficmanager.net"]).isErr
      check teamsDownload("image:https:", @["smba.trafficmanager.net"]).isErr
      check hostOfUrl("") == "" and hostOfUrl("ht") == ""   ## never a crash on short input

when isMainModule:
  runTests()
  runMediaTests()
