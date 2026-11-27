## Teams inbound runtime (PRD-roadmap E2.4): the verified activities the
## webhook queued become session turns on the daemon loop. Only messages with
## text are turns; a redelivered activity is a turn once; a group outside the
## allowed chats is dropped; `/continue` links the identity locally.

import std/[json, os, strutils, unittest]
import donkey/adapters/channel/teams
import donkey/adapters/channel/teams_runtime
import donkey/domain/channels/teams_pure
import donkey/adapters/channel/outbound_builder
import donkey/ports/channel_capability
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/core/security/dm_policy
import donkey/domain/message
import donkey/ports/http

const ServiceUrl = "https://smba.trafficmanager.net/amer/"

let rtLog = newLogger("test.teams_runtime", lvlError)

type Sink = ref object
  turns: seq[InboundMessage]
  replies: seq[OutboundMessage]

proc fallbackFor(s: Sink): proc(msg: InboundMessage) {.gcsafe.} =
  result = proc(msg: InboundMessage) {.gcsafe.} =
    {.cast(gcsafe).}:
      s.turns.add msg

proc replyFor(s: Sink): proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
  result = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      s.replies.add msg
    ok()

var seq0 = 0
proc newAdapter(): TeamsAdapter =
  inc seq0
  let dir = getTempDir() / ("donkey_teams_rt_" & $seq0)
  removeDir(dir)
  createDir(dir)
  newTeamsAdapter("app-123", "pw", "tenant-1", dir / "ids.tsv",
                  dir / "conversations.json",
                  http = HttpRuntimePort(post: proc(url, body: string;
                    headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
                    if url.startsWith("https://login.microsoftonline.com/"):
                      return ok(HttpResponse(status: 200,
                        body: """{"access_token":"t","expires_in":3600}"""))
                    ok(HttpResponse(status: 201))))

proc message(id: string; text = "oi"; group = false; kind = "message"): TeamsActivity =
  TeamsActivity(kind: kind, id: id, serviceUrl: ServiceUrl, channelId: "msteams",
    conversationId: (if group: "19:team@thread.tacv2;messageid=9" else: "a:1xyz"),
    conversationType: (if group: "channel" else: "personal"), isGroup: group,
    fromId: "29:1abc", fromName: "Belle", aadObjectId: "aad-belle", text: text)

proc drained(): bool =
  not tryRecvActivity()[0]

proc runTests*() =
  suite "teams runtime":
    setup:
      while tryRecvActivity()[0]: discard

    test "a message becomes a turn that answers in its thread":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700", "resume a reunião"))
      check drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog) == 1
      check s.turns.len == 1
      let m = s.turns[0]
      check m.channel == ckTeams
      check m.text == "resume a reunião"
      check m.rawChannelId == "aad-belle"
      check m.channelId == replyTarget(ServiceUrl, "a:1xyz", "1700")
      check not m.isGroup
      check ($m.userId).len > 0
      check drained()

    test "the same activity delivered twice is one turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700"))
      pushActivity(message("1700"))
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1

    test "activities that are not messages with text are consumed and dropped":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1", kind = "conversationUpdate", text = ""))
      pushActivity(message("2", kind = "typing", text = ""))
      pushActivity(message("3", text = "   "))
      check drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog) == 0
      check s.turns.len == 0
      check drained()

    test "a group the operator did not allow is dropped":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      sm.configureGroupGate(GroupGate(allowedChats: @["19:other@thread.tacv2"]))
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700", group = true))
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0

    test "an allowed group is a turn, marked as a group":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      sm.configureGroupGate(GroupGate(allowedChats: @["19:team@thread.tacv2"]))
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700", group = true))
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 1 and s.turns[0].isGroup

    test "the conversation is remembered for sends without a target":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700"))
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check a.send(OutboundMessage(userId: s.turns[0].userId, channel: ckTeams,
                                   text: "lembrete")).isOk

    test "/continue with a bad code is answered locally, not a turn":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      pushActivity(message("1700", "/continue ZZZZZZ"))
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check s.turns.len == 0
      check s.replies.len == 1
      check s.replies[0].channel == ckTeams
      check s.replies[0].replyTo == replyTarget(ServiceUrl, "a:1xyz", "1700")

    test "an app's activity becomes a turn of that bot, answered by its adapter":
      ## E3.6: the route tagged the activity with the app it was sent to.
      var a = newAdapter()
      var vendas = newAdapter()
      vendas.resolver = a.resolver
      let pv = addr vendas
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      var noted: seq[string]
      var act = message("1800", "quero comprar")
      act.bot = "vendas"
      pushActivity(act)
      var lost = message("1801", "de um app que saiu")
      lost.bot = "gone"
      pushActivity(lost)
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog,
        pickBot = proc(bot: string): ptr TeamsAdapter {.gcsafe.} =
          (if bot == "vendas": pv else: nil),
        noteInbound = proc(userId: UserId; bot: string) {.gcsafe.} =
          {.cast(gcsafe).}:
            noted.add bot)
      check s.turns.len == 1
      check s.turns[0].bot == "vendas"
      check noted == @["vendas"]
      ## the conversation is the app's, kept by its adapter
      check vendas.send(OutboundMessage(userId: s.turns[0].userId, channel: ckTeams,
                                        text: "lembrete")).isOk
      check a.send(OutboundMessage(userId: s.turns[0].userId, channel: ckTeams,
                                   text: "lembrete")).isErr

    test "the seen list stays bounded":
      var seen: TeamsSeen
      for i in 0 ..< TeamsSeenCapacity + 50:
        check markSeen(seen, $i)
      check seen.ids.len == TeamsSeenCapacity
      check not markSeen(seen, $(TeamsSeenCapacity + 49))
      check markSeen(seen, "0")   ## long gone

proc runMediaTests*() =
  suite "teams runtime — attachments in (E9.4)":
    setup:
      while tryRecvActivity()[0]: discard

    test "the first attachment goes to the turn; the others are named; no text is needed":
      var a = newAdapter()
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      var act = message("1800", "")
      act.attachments = @[
        TeamsAttachment(fileId: "file:https://contoso.sharepoint.com/x/a.pdf", name: "a.pdf",
                        mimeType: "application/pdf"),
        TeamsAttachment(fileId: "image:https://smba.trafficmanager.net/x", mimeType: "image/png")]
      pushActivity(act)
      check drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog) == 1
      let m = s.turns[0]
      check m.mediaUrl == "file:https://contoso.sharepoint.com/x/a.pdf"
      check m.mediaFileName == "a.pdf" and m.mediaMimeType == "application/pdf"
      check "image/png" in m.text

    test "the registry and the port: attachments in":
      check supports(ckTeams, cfDownloadFile)
      check supports(ckTeams, cfSendFile)   ## files out since Teams complete
      check teamsOutboundPort(nil).downloadFile("file:x").isErr

proc runConsentTests*() =
  suite "teams runtime — a file consent answer (Teams complete)":
    setup:
      while tryRecvActivity()[0]: discard

    test "the answer reaches the adapter, uploads the file, and is not a turn":
      let dir = getTempDir() / "donkey_teams_rt_consent"
      removeDir(dir); createDir(dir / "attachments")
      writeFile(dir / "attachments" / "relatorio.pdf", "%PDF")
      var puts = 0
      var posts: seq[string]
      var a = newTeamsAdapter(appId = "app-123", appPassword = "pw", tenantId = "tenant-1",
        identityPath = dir / "ids.tsv", conversationsPath = dir / "conv.json",
        http = HttpRuntimePort(
          post: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
            if url.startsWith("https://login.microsoftonline.com/"):
              return ok(HttpResponse(status: 200, body: """{"access_token":"t","expires_in":3600}"""))
            {.cast(gcsafe).}: posts.add body
            ok(HttpResponse(status: 201)),
          put: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
            {.cast(gcsafe).}: inc puts
            ok(HttpResponse(status: 201))))
      check a.send(OutboundMessage(channel: ckTeams, replyTo: replyTarget(ServiceUrl, "a:1xyz", "act-1"),
        mediaUrl: dir / "attachments" / "relatorio.pdf", mediaRoot: dir)).isOk
      let pending = parseJson(posts[0])["attachments"][0]["content"]["acceptContext"]["pending"].getStr
      var sm: SessionManager
      sm.init()
      var seen: TeamsSeen
      let s = Sink()
      var inv = message("inv-1", "", kind = "invoke")
      inv.name = "fileConsent/invoke"
      inv.value = $(%* {"action": "accept", "context": {"pending": pending},
        "uploadInfo": {"name": "relatorio.pdf", "uploadUrl": "https://contoso-my.sharepoint.com/u",
                       "contentUrl": "https://contoso-my.sharepoint.com/f", "uniqueId": "U", "fileType": "pdf"}})
      pushActivity(inv)
      discard drainTeamsEvents(a, sm, seen, fallbackFor(s), replyFor(s), rtLog)
      check puts == 1 and s.turns.len == 0

    test "Teams is offered send_file":
      check supports(ckTeams, cfSendFile)

when isMainModule:
  runTests()
  runMediaTests()
  runConsentTests()
