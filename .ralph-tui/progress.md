# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

### `|>->` requires piped value as LAST parameter
When designing functions for use with `|>->`, the piped subject must be the **last** parameter.
`arr |>-> maxNextOffset(offset)` expands to `maxNextOffset(offset, arr)` — not `maxNextOffset(arr, offset)`.
UFCS (`arr.f(x)`) applies the receiver as the **first** argument, so `|>->` and UFCS have opposite conventions.

### Pure parsing in `domain/channels/`
Adapter parsing logic (JSON → domain types) can be factored into `domain/channels/<channel>_pure.nim` with all `func`.
The adapter then calls the pure parser and handles only side-effectful work (HTTP, file_id resolution, ack calls).

### `>>=` with inline closures requires `{.gcsafe, raises: [].}`
The `>>=` template (pipeops.nim) type-checks `f` as `proc(x: T): Result[U, E] {.gcsafe, raises: [].}`.
Inline anonymous procs without those annotations compile only when inferred as gcsafe (no GC global capture).
Safer pattern: define a named helper `proc myHelper(x: T): Result[U, E] {.gcsafe, raises: [].}` and call it from the inline closure, so the closure itself is trivially gcsafe.

### `HttpResponse` not re-exported by `std_http`
`adapters/http/std_http.nim` imports but does NOT export `HttpResponse` from `ports/http`.
Any adapter module that references `HttpResponse` in signatures must `import ../../ports/http` directly.

---

## 2026-03-22 - US-017
- Implemented `src/donkey/adapters/channel/slack.nim` — Slack Events API webhook adapter
- Created `tests/channel/t_slack.nim` with 20 tests covering identity, construction, challenge parsing, and event routing

**What was implemented:**
- `SlackRawEventKind` enum: srMessage, srSlashCommand, srBlockAction
- `SlackRawEvent` object with kind, slackUserId, text, channelId, teamId, responseUrl, triggerId
- `gSlackEvents` — module-level `Channel[SlackRawEvent]` (same thread-safe pattern as Discord)
- `parseChallenge(payload)` — returns challenge string for url_verification; empty otherwise
- `pushEvent(payload)` — parses via slack_pure and enqueues events; ignores verification/unknown
- `openQueue()` / `tryRecvEvent()` — lifecycle and polling interface
- `postJson(endpoint, body)` — Slack Web API helper using `>>=` chain (`http.post >>= parseSlackBody`)
- `parseSlackBody(resp)` — named `{.gcsafe, raises: [].}` proc validates HTTP status + Slack "ok" field
- `dmChannelFor(slackUserId)` — lazy DM channel resolution via `conversations.open` (cached in `ref Table`)
- `send()`, `sendToChannel()`, `sendReturnId()`, `editMessage()`, `ack()` — ChannelPort procs
- `newSlackAdapter(botToken, identityPath, apiBase)` — constructor

**Files changed:**
- `src/donkey/adapters/channel/slack.nim` (new)
- `tests/channel/t_slack.nim` (new)

**Learnings:**
- Disk full (100%) caused spurious compile failure — cleaned nimcache (209M) to free space
- The `ref Table` pattern for DM channel caching (same as Discord's `dmChannels`) works correctly with value receivers because mutations go through the ref
- `parseSlackBody` as a named `{.gcsafe, raises: [].}` proc enables clean `>>= parseSlackBody` chaining without lambda wrapping
- Slack webhook ack is implicit (HTTP 200 response from the HTTP layer) — `ack()` is a no-op
- `gSlackEvents.open()` must be wrapped in `{.cast(gcsafe).}` in `openQueue()` (same pattern as Discord)
- `export identity_resolver` in the adapter avoids double-import for downstream modules

---

## 2026-03-22 - US-016
- Implemented `src/donkey/domain/channels/slack_pure.nim` — pure (all `func`) parser for Slack Events API webhook payloads
- Created `tests/domain/channels/t_slack_pure.nim` with 40 tests covering all event kinds
- Added `ckSlack` to `ChannelKind` enum in `core/types.nim` and updated `outbound_runtime.nim`, `outbound.nim`, and `ports/channel.nim` accordingly

**What was implemented:**
- `SlkEventKind` enum: sekMessage, sekSlashCommand, sekBlockAction, sekVerification, sekUnknown
- `SlkParseResult` type with kind, rawId, text, channelId, teamId, eventTs, responseUrl, triggerId, challenge
- `parseEvent(payload)` — single dispatcher; routes by top-level `type` field
- `toInbound(r, userId)` — domain conversion to InboundMessage (uses `eventTs` as `channelId` for dedup)
- `isVerification(r)` — predicate; true when challenge ack is required
- Internal helpers: `extractField` (for `|>->` piping), `extractUserId` (handles both string and `{id}` object), `parseMessageEvent` (designed for `|>->` with teamId as first arg), `parseSlashCommand`, `parseBlockActions`

**Files changed:**
- `src/donkey/domain/channels/slack_pure.nim` (new)
- `tests/domain/channels/t_slack_pure.nim` (new)
- `src/donkey/core/types.nim` (added ckSlack)
- `src/donkey/ports/channel.nim` (added slack field to OutboundChannelPorts)
- `src/donkey/app/outbound_runtime.nim` (added ckSlack cases)
- `src/donkey/core/outbound/outbound.nim` (added ckSlack to isImplementedOutboundChannel)

**Learnings:**
- When a multi-arg helper needs to be used with `|>->`, make the piped subject the LAST parameter — `parseMessageEvent(teamId, event)` not `parseMessageEvent(event, teamId)`, then `event |>-> parseMessageEvent(teamId)` works correctly
- `|>` cannot be used with partial application like `event |> parseMessageEvent(teamId)` — that expands to `parseMessageEvent(teamId)(event)` which fails; use `|>->` instead when extra args are needed
- Adding a new `ChannelKind` enum variant requires updating several files: `core/types.nim` (`$`), `ports/channel.nim` (OutboundChannelPorts struct), `app/outbound_runtime.nim` (all case statements), `core/outbound/outbound.nim` (isImplementedOutboundChannel set)
- The `extractUserId` helper that handles both `"user": "U..."` (string) and `"user": {"id": "U..."}` (object) is needed because Slack uses different user formats in event callbacks vs block_actions payloads
---

## 2026-03-22 - US-015
- Refactored `src/donkey/adapters/channel/discord.nim` to use `discord_pure.parseDispatch` and pipeops operators
- Created `tests/channel/t_discord.nim` with 15 tests covering identity resolution, adapter construction, and dispatch routing

**What was implemented:**
- Added imports: `discord_pure` and `ports/http` (needed for `HttpResponse` in `>>=` helper procs)
- Replaced inline `handleDispatch` (150 lines) with a clean `case r.kind` dispatch using `parseDispatch(t, d)`
- Added `extractJsonId(j)` pure func for `|>` piping from JSON → id string
- Added `parseJsonBody(resp)` and `extractId(resp)` helper procs for `>>=` chaining
- Refactored `getAppId` to single-line: `a.http.get(...) >>= extractId`
- Refactored `sendReturnId` to use `>>= extractId` instead of manual parse
- Refactored `dmChannelFor` to use `parseJson(resp.body) |> extractJsonId`
- Fixed unused `DiscordGatewayUrl` constant by using it in `runGatewaySession` host extraction

**Files changed:**
- `src/donkey/adapters/channel/discord.nim` (refactored)
- `tests/channel/t_discord.nim` (new)

**Learnings:**
- `parseJsonBody >>= extractId` pattern is cleaner than inline try/except for JSON id extraction
- `DsEventKind` (discord_pure) maps to `DiscordEventKind` (adapter) via: dekMessage→deMessage, dekButtonClick→deButtonClick, dekModalSubmit→deInteraction, dekSlashCommand with needsModal→deModalRequest, dekSlashCommand with "/" content→deMessage, dekSlashCommand without "/"→deInteraction (/continue code)
- Unused module-level constants (e.g. `DiscordGatewayUrl`) generate a Hint (not warning), but it's cleaner to use them
- `extractId` as a named `{.gcsafe, raises: [].}` proc makes it directly usable in `>>=` without a lambda wrapper
---

## 2026-03-22 - US-014
- Implemented `src/donkey/domain/channels/discord_pure.nim` — pure (all `func`) parser for Discord gateway dispatch events
- Created `tests/domain/channels/t_discord_pure.nim` with 40 tests covering all event kinds

**What was implemented:**
- `DsEventKind` enum: dekMessage, dekSlashCommand, dekButtonClick, dekModalSubmit, dekUnknown
- `DsParseResult` type with kind, rawId, content, channelId, messageId, interactionId, interactionToken, needsModal
- `parseDispatch(t, d)` — single dispatch parser; routes by event type using `|>` for internal helpers
- `toInbound(r, userId)` — domain conversion to InboundMessage
- `hasInteraction(r)` — predicate; true when interaction ack is required
- Internal helpers: `extractDiscordUser`, `findOption` (designed for `|>->` piping), `buildSlashContent`, `parseMessageCreate`, `parseInteractionCreate`, `parseApplicationCommand`, `extractModalCode`

**Files changed:**
- `src/donkey/domain/channels/discord_pure.nim` (new)
- `tests/domain/channels/t_discord_pure.nim` (new)

**Learnings:**
- `findOption` was designed as `findOption(name, opts)` so `opts |>-> findOption(name)` works (piped value last)
- Guild context interactions carry `member.user` instead of top-level `user` — extractDiscordUser handles both
- Discord op=0 dispatches arrive as `(t, d)` pairs, not a single node; `parseDispatch(t, d)` is the natural API rather than forcing a unary pipe
- `|>` still useful internally: `d |> parseMessageCreate`, `d |> extractDiscordUser`, `d |> extractModalCode`
---

## 2026-03-22 - US-012
- Implemented `src/donkey/domain/channels/telegram_pure.nim` — pure (all `func`) parser for Telegram Bot API updates
- Created `tests/domain/channels/t_telegram_pure.nim` with 25 tests covering all update kinds

**What was implemented:**
- `TgParseResult` type with kind, rawId, sessionKey, text, channelId, callbackId, hasMedia, mediaFileId
- `parseUpdate(JsonNode): TgParseResult` — single update parser using `|>` pipeline
- `parseUpdates(JsonNode): seq[TgParseResult]` — batch parser filtering unknowns
- `toInbound(r, userId, mediaUrl): InboundMessage` — domain conversion
- `maxNextOffset(currentOffset, updates): int64` — offset calc for polling; designed for `|>->`
- `hasCallbackId(r): bool` — predicate for ack-required updates

**Files changed:**
- `src/donkey/domain/channels/telegram_pure.nim` (new)
- `tests/domain/channels/t_telegram_pure.nim` (new)

**Learnings:**
- `|>->` macro puts the piped value as the LAST argument — functions designed for it must have the "subject" as last param (opposite of UFCS)
- `func` works fine with `JsonNode` in Nim — no side effects despite GC types
- `warningAsError` is on globally via `config.nims`; unused imports cause build failure
- Test files need explicit `import donkey/core/pipeops` to use `|>` — not re-exported by the module under test
---

## 2026-03-22 - US-013
- Refactored `src/donkey/adapters/channel/telegram.nim` to use `telegram_pure.nim` and pipeops operators

**What was implemented:**
- Added `import ../../domain/channels/telegram_pure` and `import ../../ports/http`
- Extracted `parseTgResp(meth, resp)` as a named `{.gcsafe, raises: [].}` helper
- Refactored `post` to use `>>=`: `http.post(...) >>= proc(resp): ... = parseTgResp(meth, resp)`
- Refactored `getFileUrl` to use `>>=`: `post("getFile", ...) >>= proc(resp): ok(base & ... & path)`
- Refactored `receive` to use pure parser: `updates |> parseUpdates`, `r.toInbound(userId, mediaUrl)`, `updates |>-> maxNextOffset(a.offset)`
- Removed redundant `extractMediaUrl` proc (replaced by `r.hasMedia` / `r.mediaFileId` from pure parser)

**Files changed:**
- `src/donkey/adapters/channel/telegram.nim` (refactored)

**Learnings:**
- `>>=` with inline closures that capture outer locals: define a named `{.gcsafe, raises: [].}` proc and delegate to it — the inline closure becomes a trivial one-liner that is provably gcsafe
- `HttpResponse` is NOT re-exported by `std_http` — must import `ports/http` directly when referencing it in signatures
- The pure parser (`telegram_pure`) cleanly replaces the manual for-loop in `receive`; adapter only handles side-effectful work (ack, file URL resolution, identity)
---
