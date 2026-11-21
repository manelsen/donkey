## US-004 — pure dashboard builders and route parsers.
##
## Shapes, clamping, provider health and the action/path parsers. No I/O, no
## clock: the module only formats what the wiring already collected.

import std/[json, strutils, unittest]
import results
import donkey/core/providers/smart_routing
import donkey/domain/providers/descriptors
import donkey/domain/gateway/dashboard_pure

func row(id, user: string; epochMs: int64 = 0; restored = false): SessionDetail =
  SessionDetail(
    sessionId: id,
    userId: user,
    channels: @["ckCli"],
    lastInboundEpochMs: epochMs,
    restored: restored,
  )

# ── sessions ──────────────────────────────────────────────────────────────────

func allAvailable(): ProviderAvailability =
  ProviderAvailability(
    openrouter: true, anthropic: true, openai: true, deepseek: true,
    zaiAnthropic: true, gemini: true, minimax: true, zai: true,
    zaiCoding: true, groq: true, ollama: true, opencodeGo: true,
    zen: true, nvidia: true, alibaba: true, fireworks: true,
  )

func findProvider(j: JsonNode; id: string): JsonNode =
  for item in j:
    if item{"id"}.getStr() == id:
      return item
  newJNull()


proc runTests*() =
  suite "buildSessionsJson":

    test "defaults the limit to 50 and keeps the rows":
      let body = buildSessionsJson(@[row("s1", "api:a"), row("s2", "api:b")], 0, 0)
      let j = parseJson(body)
      check j{"limit"}.getInt() == 50
      check j{"offset"}.getInt() == 0
      check j{"total"}.getInt() == 2
      check j{"sessions"}.len == 2

    test "caps the limit at 200":
      let rows = @[row("s1", "api:a")]
      check parseJson(buildSessionsJson(rows, 10_000, 0)){"limit"}.getInt() == 200
      check parseJson(buildSessionsJson(rows, -3, 0)){"limit"}.getInt() == 50

    test "clamps a negative offset to zero":
      let rows = @[row("s1", "api:a"), row("s2", "api:b")]
      let j = parseJson(buildSessionsJson(rows, 2, -9))
      check j{"offset"}.getInt() == 0
      check j{"sessions"}.len == 2

    test "clamps an absurd offset instead of failing":
      let rows = @[row("s1", "api:a"), row("s2", "api:b")]
      let j = parseJson(buildSessionsJson(rows, 50, high(int)))
      check j{"offset"}.getInt() == 2
      check j{"sessions"}.len == 0

    test "slices by offset and limit":
      var rows: seq[SessionDetail]
      for i in 0 ..< 5:
        rows.add(row("s" & $i, "api:u" & $i))
      let j = parseJson(buildSessionsJson(rows, 2, 1))
      check j{"sessions"}.len == 2
      check j{"sessions"}[0]{"sessionId"}.getStr() == "s1"
      check j{"sessions"}[1]{"sessionId"}.getStr() == "s2"

    test "emits the declared row shape with an ISO timestamp":
      let body = buildSessionsJson(
        @[SessionDetail(sessionId: "s1", userId: "api:alice",
                        channels: @["ckCli"], lastInboundEpochMs: 1_700_000_000_000,
                        restored: false),
          SessionDetail(sessionId: "s2", userId: "local:webui",
                        channels: @["ckCli"], lastInboundEpochMs: 0,
                        restored: true)],
        50, 0)
      let j = parseJson(body)
      let live = j{"sessions"}[0]
      check live{"sessionId"}.getStr() == "s1"
      check live{"userId"}.getStr() == "api:alice"
      check live{"channels"}.kind == JArray
      check live{"channels"}[0].getStr() == "ckCli"
      check live{"lastInboundAt"}.getStr().endsWith("Z")
      check live{"lastInboundAt"}.getStr().startsWith("2023-11-14")
      check live{"live"}.getBool() == true
      let restored = j{"sessions"}[1]
      check restored{"live"}.getBool() == false
      check restored{"lastInboundAt"}.getStr() == ""

  # ── providers ────────────────────────────────────────────────────────────────

  suite "buildProvidersJson":

    test "lists descriptor ids in canonical form":
      let j = parseJson(buildProvidersJson(allAvailable(), @[], @[]))
      check j.kind == JArray
      check j.len == providerDescriptors().len
      for descriptor in providerDescriptors():
        check findProvider(j, descriptor.id).kind == JObject

    test "maps metrics through aliases onto the canonical id":
      let metrics = @[ProviderFeedback(providerName: "nim", calls: 4,
                                       okCalls: 4, errCalls: 0,
                                       avgLatencyMs: 900)]
      let j = parseJson(buildProvidersJson(allAvailable(), @[], metrics))
      let nvidia = findProvider(j, "nvidia")
      check nvidia{"calls"}.getInt() == 4
      check nvidia{"ok"}.getInt() == 4
      check nvidia{"err"}.getInt() == 0
      check nvidia{"avgLatencyMs"}.getInt() == 900
      check nvidia{"health"}.getStr() == "ok"

    test "derives health from availability, cooldowns and errors":
      var av = allAvailable()
      av.openrouter = false
      let cooldowns = @[ProviderCooldown(providerName: "anthropic",
                                         untilUnix: 1_900_000_000)]
      let metrics = @[ProviderFeedback(providerName: "openai", calls: 5,
                                       okCalls: 3, errCalls: 2,
                                       avgLatencyMs: 1200)]
      let j = parseJson(buildProvidersJson(av, cooldowns, metrics))
      check findProvider(j, "openrouter"){"health"}.getStr() == "missing"
      check findProvider(j, "openrouter"){"available"}.getBool() == false
      check findProvider(j, "anthropic"){"health"}.getStr() == "cooling"
      check findProvider(j, "anthropic"){"cooldownUntil"}.getStr().len > 0
      check findProvider(j, "openai"){"health"}.getStr() == "degraded"
      check findProvider(j, "openai"){"available"}.getBool() == true
      check findProvider(j, "deepseek"){"health"}.getStr() == "ok"
      check findProvider(j, "deepseek"){"cooldownUntil"}.getStr() == ""

    test "an unavailable provider stays missing even with a cooldown":
      var av = allAvailable()
      av.fireworks = false
      let cooldowns = @[ProviderCooldown(providerName: "fireworks",
                                         untilUnix: 1_900_000_000)]
      let j = parseJson(buildProvidersJson(av, cooldowns, @[]))
      check findProvider(j, "fireworks"){"health"}.getStr() == "missing"

  # ── action body ──────────────────────────────────────────────────────────────

  suite "parseSessionAction":

    test "accepts the new action":
      let parsed = parseSessionAction("""{"action":"new"}""")
      check parsed.isOk
      check parsed.get().kind == sakNew

    test "trims the action value":
      check parseSessionAction("""{"action":" new "}""").isOk

    test "rejects an unknown action":
      for body in ["""{"action":"reset"}""", """{"kind":"reset"}""",
                   """{"action":"stop"}"""]:
        check parseSessionAction(body).isErr

    test "rejects empty, malformed and non-object bodies":
      for body in ["", "not json", "[]", """{"action":1}""", "{}"]:
        check parseSessionAction(body).isErr

  # ── task path ────────────────────────────────────────────────────────────────

  suite "parseSessionTaskPath":

    test "extracts the raw user id without the api: prefix":
      let parsed = parseSessionTaskPath(
        "/api/sessions/6f1d3c2a-0b7e-4c55-9a11-3d2f9e8a7b60/task")
      check parsed.isOk
      check parsed.get() == "6f1d3c2a-0b7e-4c55-9a11-3d2f9e8a7b60"
      check not parsed.get().startsWith("api:")

    test "preserves the raw case":
      check parseSessionTaskPath("/api/sessions/AbC-123/task").get() == "AbC-123"

    test "rejects slashes, empty ids and path segments":
      for path in ["/api/sessions//task", "/api/sessions/a/b/task",
                   "/api/sessions/./task", "/api/sessions/../task",
                   "/api/sessions/%2F/task"]:
        check parseSessionTaskPath(path).isErr

    test "rejects paths outside the route":
      for path in ["/api/sessions/abc", "/api/sessions/abc/task/",
                   "/api/session/abc/task", "/api/sessions/abc/other"]:
        check parseSessionTaskPath(path).isErr

when isMainModule:
  runTests()
