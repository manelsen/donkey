# Re-review r2 — `tasks/prd-canais.md`

**Verdict: PASS WITH FIXES.** The 9 prior fixes are in; four spec-level contradictions remain, all one-line.
No source/test/PRD changes made; no builds run.

## Checked
1 ✓ `lineTarget` strips `group:`/`room:`/`user:` (US-004:146), `replyTo` before `reverseChannel`,
  `to` never prefixed (:148, FR-5 :186); `reverseChannel` = `resolver.reverseChannel(userId, kind)` as slack.nim:173/qq.nim:183.
2 ✓ `WebhookAuthSpec.signedPayload` has `wspTimestampNewlineSecret`, which matches the real DingTalk MAC
  (`hmacSha256Base64(secret, ts & "\n" & secret)`, webhook_receiver.nim:345-346); DingTalk stays migrated (US-003:137), hex/shared-token gone.
3 ✓ `WebhookRequest`/`safeEquals`/`hmacSha256*`/`header`/`hasQuery` move to `webhook_ingress` + `export`, receiver re-exports,
  ingress has no receiver import (:135). `t_webhook_receiver.nim` builds `WebhookRequest` and calls `hmacSha256Hex` → satisfied by re-export;
  only other importer (`tests/stress/t_webhook_tls_stress.nim`) is unaffected.
4 ✓ US-000: `ckLine` appended, `$`, all 8 exhaustive `case`s (outbound_runtime.nim:61,78,112,134,165,183,203,224)
  + `outboundPortForChannel` (src/donkey.nim:1354-1371); registry entry is mandatory (array defaults to all-false, channel_capability.nim:94).
5 ✗ partial — default-deny wording and speaker identity each contradict the call they prescribe (fixes 1–3).
6 ✓ US-002 explicitly does not touch `line_pure.nim` (:125); no other shared file; serialization in §4.2.
7 ✓ `deliveryContext.isRedelivery` cited to `webhook.yml`, standby parsed then dropped, empty-events Verify + fixture,
  KAT recomputed with openssl: body `{"events":[]}` + `test-channel-secret` → `sKRrt+MTE71nWWZPaYrvYSdH9JGlgckmBidZxDuPgPc=` (matches).
8 ✓ Order US-000→…→US-007 (:89), single writer for `src/donkey.nim`/`outbound_runtime.nim`.

## Remaining fixes
1. **US-006:166 is self-defeating.** "vazio nega todo grupo" is attached to `groupChatAllowed(GroupGate(allowedChats: LINE_ALLOWED_GROUPS), chatId)`,
   but that function returns **true** when `allowedChats` is empty (`core/security/dm_policy.nim:45`). Require an explicit
   `if lineAllowedGroups.len == 0: deny` before the gate (keep the empty-list test at :169).
2. **US-006:169 contradicts US-006:166 / §9:196.** Identity is keyed by `(kind, rawId)` (`identity_resolver.nim:107-111`), so
   `rawId = senderId` gives **distinct** identities, not "dois speakers … compartilham identidade". Choose one and align the test:
   speaker identity (assert two identities, both replying to `chatId`) or `rawId = chatId` (one identity, speaker lost).
3. **`authorizeInbound(..., channelId = chatId)` (US-006:166) has no such parameter.** Signature is
   `(sm, gate, kind, rawId, text, linkSource, isGroup, chatId)` (`inbound_gate.nim:59-66`), and `chatId` is only consulted when `isGroup = true`.
   Put the mapping in US-001 `toInbound` (`rawChannelId = senderId`, `channelId = chatId`, `chatId = chatId`, `isGroup = sourceKind != lskUser`)
   and keep US-006 as `authorizeInbound(sm, gate, ckLine, senderId, text, isGroup = false)`.
4. **US-000 has no capability assertion.** The "unedited" tests only force `send` (`t_channel_capability.nim:37-42`);
   nothing proves the other five flags are false. Add `tests/ports/t_line_capability.nim` (new file, so the no-edit rule still holds).
5. Minor: §1:51-52 says `200 "ok"` but US-005:156 says "200 vazio" — pick one (LINE only needs 2xx; Hermes sends `ok`).
   Also pin `parseWebhook(payload: JsonNode)` so "payload inválido → @[]" (US-001:117) does not overlap "JSON inválido → 400" (US-005:157).
