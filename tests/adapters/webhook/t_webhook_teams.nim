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

    test "the route counts as configured":
      check anyRouteConfigured(cfg)
      check not anyRouteConfigured(WebhookConfig())

when isMainModule:
  runTests()
