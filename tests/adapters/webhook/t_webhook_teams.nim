## `/webhook/teams` on the shared receiver (PRD-roadmap E2.2): only a request
## the Bot Connector signed for this bot reaches the queue; everything else
## gets the status the Bot Framework documents (401, or 403 for a channel the
## key does not endorse).

import std/[json, strutils, tables, unittest]
import donkey/core/pipeops
import donkey/adapters/channel/teams
import donkey/adapters/webhook/webhook_ingress
import donkey/adapters/webhook/webhook_receiver
import ../channel/teams_jwt_vectors

const
  ServiceUrl = "https://smba.trafficmanager.net/amer/"
  Jwks = """{"keys":[{"kty":"RSA","kid":"k1","n":"""" & vecN &
         """","e":"AQAB","endorsements":["msteams"]}]}"""

proc activity(channelId = "msteams"; serviceUrl = ServiceUrl): string =
  $(%* {"type": "message", "id": "1700", "serviceUrl": serviceUrl,
        "channelId": channelId,
        "from": {"id": "29:1abc", "name": "Belle", "aadObjectId": "aad-belle"},
        "conversation": {"conversationType": "personal", "id": "a:1xyz"},
        "recipient": {"id": "28:app-123", "name": "Donkey"},
        "text": "oi"})

proc request(token: string; body = activity(); httpMethod = "POST"): WebhookRequest =
  var headers = initTable[string, string]()
  if token.len > 0:
    headers["authorization"] = "Bearer " & token
  WebhookRequest(httpMethod: httpMethod, path: TeamsPath, headers: headers, body: body)

proc drain(): int =
  while true:
    let (has, _) = tryRecvActivity()
    if not has:
      return
    inc result

let cfg = WebhookConfig(teamsAppId: "app-123")
let noFetch: KeyFetch = proc(): Result[string, string] {.gcsafe.} = err("offline")

proc handle(req: WebhookRequest; fetch = noFetch): WebhookResponse =
  handleTeamsAt(cfg, req, VecNowSec, fetch)

proc runTests*() =
  suite "webhook — teams":
    setup:
      resetBotKeys()
      seedBotKeys(Jwks, nowMs = VecNowSec * 1000)
      discard drain()

    test "without an App ID the route is not there":
      check handleTeamsAt(WebhookConfig(), request(vecGood), VecNowSec, noFetch).status == 404

    test "only POST":
      check handle(request(vecGood, httpMethod = "GET")).status == 405

    test "a signed activity for this bot is queued and answered 200":
      check handle(request(vecGood)).status == 200
      let (has, a) = tryRecvActivity()
      check has
      check a.text == "oi" and a.senderKey == "aad-belle"
      check a.serviceUrl == ServiceUrl

    test "no token is a 401, and nothing is queued":
      check handle(request("")).status == 401
      check drain() == 0

    test "a token for another bot is a 401":
      check handle(request(vecOtherAud)).status == 401
      check drain() == 0

    test "a forged signature is a 401":
      check handle(request(vecForged)).status == 401

    test "a token for another service url than the activity's is a 401":
      check handle(request(vecGood, activity(serviceUrl = "https://evil.example/"))).status == 401

    test "a channel the key does not endorse is a 403":
      check handle(request(vecGood, activity(channelId = "webchat"))).status == 403
      check drain() == 0

    test "a body that is not an activity is a 400":
      check handle(request(vecGood, "not json")).status == 400
      check handle(request(vecGood, "{}")).status == 400

    test "an unknown key fetches the keys once more before refusing":
      var calls = 0
      let fetch: KeyFetch = proc(): Result[string, string] {.gcsafe.} =
        inc calls
        ok(Jwks)
      ## Long after the seed: an unknown key may ask again.
      let late = VecNowSec + 600
      check handleTeamsAt(cfg, request(vecUnknownKid), late, fetch).status == 401
      check calls == 1

    test "a request without a well-formed token never makes the daemon fetch keys":
      resetBotKeys()
      var calls = 0
      let fetch: KeyFetch = proc(): Result[string, string] {.gcsafe.} =
        inc calls
        ok(Jwks)
      check handleTeamsAt(cfg, request(""), VecNowSec, fetch).status == 401
      check handleTeamsAt(cfg, request("not.a-jwt"), VecNowSec, fetch).status == 401
      check calls == 0
      check handleTeamsAt(cfg, request(vecGood), VecNowSec, fetch).status == 200
      check calls == 1

    test "a token for another configured app is that bot's activity":
      ## E3.6: several App IDs share the route; the token's audience says
      ## which bot the activity is for.
      let multi = WebhookConfig(teamsAppId: "app-123",
                                teamsApps: @[TeamsApp(appId: "app-999", bot: "vendas")])
      check handleTeamsAt(multi, request(vecOtherAud), VecNowSec, noFetch).status == 200
      let (has, a) = tryRecvActivity()
      check has and a.bot == "vendas"
      check handleTeamsAt(multi, request(vecGood), VecNowSec, noFetch).status == 200
      let (has2, b) = tryRecvActivity()
      check has2 and b.bot == ""

    test "a token for an app nobody configured is still a 401":
      let multi = WebhookConfig(teamsAppId: "app-123",
                                teamsApps: @[TeamsApp(appId: "app-555", bot: "x")])
      check handleTeamsAt(multi, request(vecOtherAud), VecNowSec, noFetch).status == 401
      check drain() == 0

    test "bots alone, without a default app, mount the route":
      let onlyBots = WebhookConfig(teamsApps: @[TeamsApp(appId: "app-999", bot: "vendas")])
      check anyRouteConfigured(onlyBots)
      check handleTeamsAt(onlyBots, request(vecOtherAud), VecNowSec, noFetch).status == 200
      check tryRecvActivity()[1].bot == "vendas"
      check handleTeamsAt(onlyBots, request(vecGood), VecNowSec, noFetch).status == 401

    test "the route counts as configured":
      check anyRouteConfigured(cfg)
      check not anyRouteConfigured(WebhookConfig())

proc runCardTests*() =
  suite "webhook — teams card actions (Teams complete, part 4)":
    setup:
      resetBotKeys()
      seedBotKeys(Jwks, nowMs = VecNowSec * 1000)
      discard drain()

    test "a card click is queued and answered with the invoke response Teams needs":
      var j = parseJson(activity())
      j["type"] = %"invoke"
      j["name"] = %"adaptiveCard/action"
      j["value"] = %* {"action": {"type": "Action.Execute", "verb": "donkey", "data": {"donkey": "apr:abc:y"}}}
      let r = handle(request(vecGood, body = $j))
      check r.status == 200
      check parseJson(r.body)["statusCode"].getInt == 200
      check parseJson(r.body)["type"].getStr == "application/vnd.microsoft.activity.message"
      let (has, a) = tryRecvActivity()
      check has and a.name == "adaptiveCard/action"

when isMainModule:
  runTests()
  runCardTests()
