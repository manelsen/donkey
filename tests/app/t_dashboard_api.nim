## US-004 — dashboard read endpoints.
##
## Drives the same response builders the HTTP connection handler uses: sessions
## paging/clamping and provider health. Hooks are fakes; there is no socket.

import std/[json, strutils, unittest]
import donkey/core/providers/smart_routing
import donkey/domain/gateway/dashboard_pure
import donkey/app/http_gateway

var fakeRuns {.threadvar.}: int

proc fakeSessions(): seq[SessionDetail] {.gcsafe.} =
  inc fakeRuns
  @[
    SessionDetail(sessionId: "s1", userId: "api:alice",
                  channels: @["ckCli"], lastInboundEpochMs: 1_700_000_000_000,
                  restored: false),
    SessionDetail(sessionId: "s2", userId: "local:webui",
                  channels: @["ckCli", "ckTelegram"],
                  lastInboundEpochMs: 1_700_000_100_000, restored: true),
  ]

proc fakeProviders(): string {.gcsafe.} =
  buildProvidersJson(
    ProviderAvailability(openai: true, fireworks: true),
    @[ProviderCooldown(providerName: "openai", untilUnix: 1_900_000_000)],
    @[ProviderFeedback(providerName: "fireworks", calls: 2, okCalls: 1,
                       errCalls: 1, avgLatencyMs: 800)])

suite "GET /api/sessions":

  test "returns 200 with the session rows":
    fakeRuns = 0
    let res = handleSessionsRequest(fakeSessions, 50, 0)
    check res.status == 200
    check res.contentType == "application/json"
    let j = parseJson(res.body)
    check j{"sessions"}.len == 2
    check j{"sessions"}[0]{"userId"}.getStr() == "api:alice"
    check j{"sessions"}[1]{"live"}.getBool() == false
    check fakeRuns == 1

  test "defaults the limit to 50 when the query is absent":
    let res = handleSessionsRequest(fakeSessions, 0, 0)
    let j = parseJson(res.body)
    check res.status == 200
    check j{"limit"}.getInt() == 50

  test "caps an absurd limit at 200":
    let j = parseJson(handleSessionsRequest(fakeSessions, 1_000_000, 0).body)
    check j{"limit"}.getInt() == 200

  test "clamps a negative offset and never fails with 500":
    let res = handleSessionsRequest(fakeSessions, 50, -40)
    let j = parseJson(res.body)
    check res.status == 200
    check j{"offset"}.getInt() == 0
    check j{"sessions"}.len == 2

  test "clamps an absurd offset instead of erroring":
    let res = handleSessionsRequest(fakeSessions, 50, high(int))
    let j = parseJson(res.body)
    check res.status == 200
    check j{"offset"}.getInt() == 2
    check j{"sessions"}.len == 0

  test "answers 503 when the hook is not wired":
    let res = handleSessionsRequest(nil, 50, 0)
    check res.status == 503
    check res.body.contains("not configured")

suite "GET /api/providers":

  test "returns 200 with the provider shape":
    let res = handleProvidersRequest(fakeProviders)
    check res.status == 200
    check res.contentType == "application/json"
    let j = parseJson(res.body)
    check j.kind == JArray
    var openai = newJNull()
    var fireworks = newJNull()
    for item in j:
      if item{"id"}.getStr() == "openai":
        openai = item
      elif item{"id"}.getStr() == "fireworks":
        fireworks = item
    check openai{"health"}.getStr() == "cooling"
    check openai{"available"}.getBool() == true
    check fireworks{"health"}.getStr() == "degraded"
    check fireworks{"calls"}.getInt() == 2
    check fireworks{"ok"}.getInt() == 1
    check fireworks{"err"}.getInt() == 1

  test "answers 503 when the hook is not wired":
    let res = handleProvidersRequest(nil)
    check res.status == 503
    check res.body.contains("not configured")
