## Pure builders and parsers for the read-only dashboard surface.
##
## `buildSessionsJson` and `buildProvidersJson` format the state the daemon
## already collected; `parseSessionAction` / `parseSessionTaskPath` are the
## only input parsers. No I/O, no clock, no provider calls: invalid paging
## values are clamped instead of failing, so a bad query can never become 500.

import std/[json, options, strutils]
import ../../core/pipeops
import ../providers/descriptors
import ../../core/providers/smart_routing

const
  DashboardDefaultLimit* = 50
  DashboardMaxLimit* = 200
  SessionTaskPrefix* = "/api/sessions/"
  SessionTaskSuffix* = "/task"

type
  SessionDetail* = object
    ## One session row as the manager knows it. `restored` is metadata-only
    ## for the dashboard; the JSON exposes the inverse as `live`.
    sessionId*: string
    userId*: string
    channels*: seq[string]
    lastInboundEpochMs*: int64
    restored*: bool

  SessionActionKind* = enum
    sakNew

  SessionAction* = object
    kind*: SessionActionKind

# ── paging ────────────────────────────────────────────────────────────────────

func clampDashboardLimit*(raw: int): int =
  ## Missing/invalid (zero or negative) falls back to 50; anything above the
  ## cap is reduced to 200.
  if raw <= 0:
    DashboardDefaultLimit
  elif raw > DashboardMaxLimit:
    DashboardMaxLimit
  else:
    raw

func clampDashboardOffset*(raw, total: int): int =
  ## Negative offsets mean "from the start"; an offset past the end is pinned
  ## to the end so the slice is empty but the response stays valid.
  if raw <= 0:
    0
  elif raw >= total:
    total
  else:
    raw

# ── timestamps ───────────────────────────────────────────────────────────────

func pad2(value: int): string =
  if value < 10: "0" & $value else: $value

func pad4(year: int): string =
  if year < 10: "000" & $year
  elif year < 100: "00" & $year
  elif year < 1000: "0" & $year
  else: $year

func civilFromDays(days: int64): (int, int, int) =
  ## Days since 1970-01-01 -> civil (year, month, day). Pure arithmetic, so
  ## the module never needs a timezone or a clock.
  let z = days + 719468
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  let year = yoe + era * 400
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let day = doy - (153 * mp + 2) div 5 + 1
  let month = mp + (if mp < 10: 3 else: -9)
  (int(year + (if month <= 2: 1 else: 0)), int(month), int(day))

func isoUtc(unix: int64): string =
  if unix <= 0:
    return ""
  let days = unix div 86400
  let secs = unix mod 86400
  let (year, month, day) = civilFromDays(days)
  pad4(year) & "-" & pad2(month) & "-" & pad2(day) & "T" &
    pad2(int(secs div 3600)) & ":" & pad2(int((secs mod 3600) div 60)) &
    ":" & pad2(int(secs mod 60)) & "Z"

func isoUtcFromEpochMs(epochMs: int64): string =
  if epochMs <= 0:
    return ""
  isoUtc(epochMs div 1000)

# ── sessions ─────────────────────────────────────────────────────────────────

func buildSessionsJson*(rows: seq[SessionDetail];
                        limit, offset: int): string =
  ## Paged sessions. `limit` defaults to 50 and caps at 200; `offset` is
  ## clamped to `[0, rows.len]`.
  let effectiveLimit = clampDashboardLimit(limit)
  let total = rows.len
  let effectiveOffset = clampDashboardOffset(offset, total)
  var sessions = newJArray()
  var index = effectiveOffset
  var emitted = 0
  while index < total and emitted < effectiveLimit:
    let row = rows[index]
    var channels = newJArray()
    for channel in row.channels:
      channels.add(%channel)
    sessions.add(%*{
      "sessionId": row.sessionId,
      "userId": row.userId,
      "channels": channels,
      "lastInboundAt": isoUtcFromEpochMs(row.lastInboundEpochMs),
      "live": not row.restored,
    })
    inc index
    inc emitted
  $(%*{
    "sessions": sessions,
    "limit": effectiveLimit,
    "offset": effectiveOffset,
    "total": total,
  })

# ── providers ────────────────────────────────────────────────────────────────

func descriptorAvailable(availability: ProviderAvailability;
                         id: string): bool =
  ## Descriptor ids are canonical; aliases are resolved before this call.
  case id
  of "openrouter": availability.openrouter
  of "openai": availability.openai
  of "deepseek": availability.deepseek
  of "ollama": availability.ollama
  of "groq": availability.groq
  of "opencode-go": availability.opencodeGo
  of "zen": availability.zen
  of "anthropic": availability.anthropic
  of "zai-anthropic": availability.zaiAnthropic
  of "gemini": availability.gemini
  of "minimax": availability.minimax
  of "zai": availability.zai
  of "zai-coding": availability.zaiCoding
  of "nvidia": availability.nvidia
  of "mistral": availability.mistral
  of "alibaba": availability.alibaba
  of "fireworks": availability.fireworks
  else: false

func canonicalProviderId(name: string): string =
  let descriptor = providerDescriptor(name)
  if descriptor.isSome:
    descriptor.get().id
  else:
    ""

func providerHealth(available: bool; cooldownUntil: int64;
                    calls, err: int): string =
  if not available:
    "missing"
  elif cooldownUntil > 0:
    "cooling"
  elif calls > 0 and err > 0:
    "degraded"
  else:
    "ok"

func buildProvidersJson*(availability: ProviderAvailability;
                         cooldowns: seq[ProviderCooldown];
                         metrics: seq[ProviderFeedback]): string =
  ## One entry per `providerDescriptor`, canonical ids only. Health is
  ## availability first (`missing`), then an active cooldown (`cooling`), then
  ## errors (`degraded`), else `ok`.
  var providers = newJArray()
  for descriptor in providerDescriptors():
    let available = descriptorAvailable(availability, descriptor.id)
    var cooldownUntil: int64 = 0
    for cooldown in cooldowns:
      if canonicalProviderId(cooldown.providerName) == descriptor.id:
        cooldownUntil = max(cooldownUntil, cooldown.untilUnix)
    var calls = 0
    var okCalls = 0
    var errCalls = 0
    var latencyWeighted = 0'i64
    for metric in metrics:
      if canonicalProviderId(metric.providerName) != descriptor.id:
        continue
      calls += metric.calls
      okCalls += metric.okCalls
      errCalls += metric.errCalls
      latencyWeighted += int64(metric.avgLatencyMs) * int64(metric.calls)
    let avgLatency = if calls > 0: int(latencyWeighted div calls) else: 0
    providers.add(%*{
      "id": descriptor.id,
      "available": available,
      "cooldownUntil": isoUtc(cooldownUntil),
      "calls": calls,
      "ok": okCalls,
      "err": errCalls,
      "avgLatencyMs": avgLatency,
      "health": providerHealth(available, cooldownUntil, calls, errCalls),
    })
  $providers

# ── action body ──────────────────────────────────────────────────────────────

proc parseSessionAction*(body: string): Result[SessionAction, string] =
  ## Allowlist of exactly one management action: `{"action":"new"}`.
  if body.len == 0:
    return err("empty body")
  var node: JsonNode
  try:
    node = parseJson(body)
  except JsonParsingError:
    return err("invalid JSON")
  if node.kind != JObject:
    return err("expected JSON object")
  let actionNode = node.getOrDefault("action")
  if actionNode.isNil or actionNode.kind != JString:
    return err("missing action")
  let action = actionNode.getStr().strip()
  case action
  of "new":
    ok(SessionAction(kind: sakNew))
  else:
    err("unknown action: " & action)

# ── task path ────────────────────────────────────────────────────────────────

func parseSessionTaskPath*(path: string): Result[string, string] =
  ## `/api/sessions/<raw-user-id>/task` -> raw user id. The id is the internal
  ## session key (usually a UUID) and is never passed through `apiUserId`, so a
  ## slash, dot-segment or percent escape is refused outright.
  if not path.startsWith(SessionTaskPrefix):
    return err("not a session task path")
  let rest = path[SessionTaskPrefix.len .. ^1]
  if rest.len <= SessionTaskSuffix.len or
     not rest.endsWith(SessionTaskSuffix):
    return err("not a session task path")
  let raw = rest[0 ..< rest.len - SessionTaskSuffix.len]
  if raw.len == 0:
    return err("empty user id")
  if raw == "." or raw == "..":
    return err("invalid user id")
  for c in raw:
    if c in {'/', '%', '?', '#'}:
      return err("invalid user id")
  ok(raw)
