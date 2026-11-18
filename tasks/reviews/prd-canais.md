# Review — `tasks/prd-canais.md`

**Verdict: PASS WITH FIXES.** Scope and channel choice are right; 9 defects, one (`to` target) fails against the real LINE API. *The PRD was edited while I read it; this covers the current version with the Hermes citations (§1).*

## LINE protocol
**Verified in Hermes:** base64 HMAC-SHA256 over the **raw body** in `X-Line-Signature`, constant-time compare (`adapter.py:138-147,508`); `events[]` with `type`, `webhookEventId`, `replyToken`, `source.*`, `message{type,id,text}` (`:514-567,200-209`); push `POST /v2/bot/message/push`, Bearer, `to` = `U…/C…/R…` (`:53-54,247-248`); 5000 hard / 4500 chunk / ≤5 bubbles (`:58-60,117-135`, `line.md:198`); dedupe by `webhookEventId`, no TTL, cap 1000 (`:420-421,524-527`); 200 on success. 403 instead of Hermes' 401 is fine.
- **`to` is wrong.** US-004 sends `rawId`, i.e. `"group:C…"`/`"room:R…"`; LINE accepts only `C…`/`R…` (Hermes pushes the source id), and §1 itself says `to` is `U/C/R`. Add `lineTarget(rawId)` that strips the prefix; assert `to == "C…"`.
- "LINE retries for up to 1 day" is a Hermes *comment*; LINE docs say count/interval are undisclosed and redelivery is opt-in, only on non-2xx. Keep 24 h, cite docs.
- `deliveryContext.isRedelivery` **exists** (developers.line.biz, `line-openapi` `webhook.yml`); absence in Hermes proves nothing, and the flag is useless against replay (the captured body replays with it). Resolve §11 now, drop `lekRedelivery`.
- `mode == "standby"` means "another module answers, don't send"; the async push answers anyway. Parse it or document the deviation.
- Console "Verify" posts an **empty-events** body and must get 200: add `webhook_empty_events.json` + docs line.
- `LineEventKind` mixes source and content with no precedence (a group sticker is both `lekGroupText` and `lekNonText`). Define precedence + test, or split the type.
- Signature test is tautological (`signatureValid(expectedSignature(...))`); add one hardcoded KAT and the empty-secret case (Hermes rejects it).

## Stories, TDD, fixtures
Fixture plan under `tests/fixtures/line/` matches `fixtures/{telegram,discord}` ✓.
- **US-001 cannot end green with `types.nim` alone:** 8 exhaustive `case`s in `app/outbound_runtime.nim` stop compiling, and `tests/ports/t_channel_capability.nim` + `t_outbound_builder_caps.nim` assert `send` for **every** `ChannelKind`. US-001 must add `LineCapability` (send=true, rest false).
- US-001/US-002 are not disjoint: US-002 edits `line_pure.nim`. Put signature helpers in `line_policy.nim` (US-002's file) or serialize the stories.
- A cache mutator as `func` is impractical; keep the decision pure and use a `proc` for insert/evict. Pass `nowSec` into `drainLineEvents` (no `epochTime` in tests).
- US-004 ← US-003 is unnecessary (it needs only US-001); reuse `LineParseResult` instead of a parallel `LineEvent` that re-carries `eventId`.

## Hexagonal purity and security
Purity is right (domain parse/policy, HTTP+queue in adapter, gate before mint, dedupe in runtime). Gaps:
- **Group default is open:** empty `GroupGate` allows every group (`dm_policy.nim:45`), fed by `DONKEY_TELEGRAM_ALLOWED_GROUPS` (`src/donkey.nim:1822`), with default `DmPolicyOpen`. Any LINE group that adds the bot gets a turn and a minted group identity. Decide: document + test, or default-deny LINE groups.
- `pairing_store.nim` `parseChannelName` lacks `"line"`, so a LINE `/pair` is written then silently dropped on load. Add it + test, or use `ilsNone`.
- Group identity = chat loses the speaker: set `rawChannelId = senderId` and test that two speakers in one group share one identity (explicit trade-off).
- **Import cycle:** `decideIngress(spec, req: WebhookRequest)` needs `WebhookRequest`, today in `webhook_receiver`, which would import ingress. Move request + `safeEquals` + `hmacSha256*` into `webhook_ingress` and `export` them; untouched `t_webhook_receiver.nim` calls `hmacSha256Hex` and builds `WebhookRequest`.
- `WebhookAuthSpec` cannot express DingTalk: it MACs `timestamp & "\n" & secret`, not the body (`webhook_receiver.nim:345-346`). Add `signedPayload` (body | timestampNewlineSecret); drop `wasHmacSha256Hex`/`wasSharedToken` (no consumer this mission).

## Ownership and wiring
- `ports/channel_capability.nim` collides with ferramentas US-005 (`cfSendVoice`): safe only because roadmap order is ferramentas #2 → canais #5. Never concurrently.
- `app/outbound_runtime.nim` collides with durabilidade (`deliveryId`); roadmap order 5 → 7 is correct — do not parallelize canais with durabilidade.
- **Missing wiring owner:** `app/gateway_drainer.nim` (field, `initGatewayDrainer`, drain proc, `drainGatewayEvents`), `DaemonAdapters` field + construction (`src/donkey.nim:541-548`) and the ctx drain closure (~1597). US-005/006 list only types, `DaemonEnv` and `startOptionalWebhookReceiver` — ~6 sites, not 3. `src/donkey.nim` also holds the replay cache.

## Non-goals, rollout, first channel
- No rollout section: public HTTPS URL, console steps, "Verify" POST, redelivery toggle, how to disable. Add to US-007.
- US-006 says "comandos" without a bound (`slack_runtime`'s switch is ~200 lines). Choose reuse, a subset (`/continue` only) or none (DingTalk precedent), and test it.
- Scope creep: none. One migrated channel is the right proof; do not add hex/shared-token auth for untouched channels.
- **LINE is the right first channel:** only candidate whose inbound auth is a pure function of raw body + static secret, with a static-Bearer POST and overridable base, matching the existing DingTalk/Slack adapter/test harness. IRC has no webhook; Teams/Google Chat need remote JWKS; Twilio needs a paid account. It also gives the ingress the right pair: body-MAC (LINE) + timestamp-MAC (DingTalk).

## Required fixes
1. `lineTarget`: send `C…`/`R…`, never `group:`/`room:`; add the test.
2. `signedPayload` in `WebhookAuthSpec`; delete unused schemes.
3. Move `WebhookRequest`/helpers to `webhook_ingress` + `export`; no cycle.
4. US-001 owns enum completion: `outbound_runtime` cases + `LineCapability` registry.
5. Resolve redelivery/standby/precedence; drop `lekRedelivery`; KAT + empty-events fixture.
6. Split US-002's signature code out of `line_pure.nim`, or serialize 001/002.
7. Decide group default; add `"line"` to pairing; set `rawChannelId = senderId`.
8. Enumerate wiring (`gateway_drainer`, `DaemonAdapters`, drain closure).
9. Bound US-006 commands; add the rollout section.

## Story order
US-000 enum+capability (serialized) → US-001 parse → US-002 sig/policy → US-003 ingress → US-004 adapter → US-005 route/env → US-006 runtime+wiring → US-007 docs/rollout.
