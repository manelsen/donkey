# Merge plan — V4 foundations wave

Snapshot: worktree on `feat/interfaces-agent-api`, base `master` @ `418cf193`.
Purpose: land the foundations as a sequence of self-contained commits (one per
mission/story) and open a single PR. Nothing here is committed yet.

## Hard rules for the commit pass

1. Stage explicit paths (`git add -- <path>`), never `git add -A`.
2. Never commit compiled test binaries or `testresults/` (already ignored by
   `tests/**` and `testresults/`).
3. New files under `docs/` are ignored (`docs/*`): use `git add -f`.
   Test sources and fixtures are re-included by `!tests/**/*.nim` and
   `!tests/fixtures/**`, so they stage normally.
4. Every commit must compile and pass its own tests before the next one is
   created. If a mission cannot stand alone, it must be merged into the
   neighbouring commit and the message must say so.
5. Any change to an existing test must be declared in the commit body, with the
   reason (behaviour change vs. test accommodation). Narrowing an existing
   acceptance check is not allowed without that declaration.

## Commit order

| # | Commit | Paths |
|---|---|---|
| 1 | `test(infra): unique nimcache per test path` | `scripts/run_tests.sh` |
| 1b | `fix(cron): map day-of-week to cron numbering` | `src/donkey/core/cron.nim`, `tests/core/t_cron.nim` — committed in `80e08975`; before it `0` (Sunday) matched Monday, so every DOW schedule was off by one |
| 2 | `refactor(security): single MAC implementation` | `src/donkey/core/security/webhook_auth.nim`, `src/donkey/adapters/webhook/webhook_receiver.nim`, `tests/core/security/t_webhook_auth.nim` — characterization, no behaviour change |
| 3 | `feat(canais): LINE enum, capability and pairing (US-000)` | `src/donkey/core/types.nim`, `src/donkey/ports/channel.nim`, `src/donkey/ports/channel_capability.nim`, `src/donkey/app/outbound_runtime.nim`, `src/donkey.nim`, `src/donkey/adapters/state/pairing_store.nim`, `tests/ports/t_line_capability.nim`, `tests/adapters/state/t_pairing_line.nim` |
| 4 | `feat(canais): LINE webhook parser (US-001)` | `src/donkey/domain/channels/line_pure.nim`, `tests/fixtures/line/`, `tests/domain/channels/t_line_pure.nim` |
| 4b | `feat(canais): LINE replay, gates and routing (US-002)` | `src/donkey/domain/channels/line_policy.nim`, `tests/domain/channels/t_line_policy.nim` — no signature code: it lives in `core/security` and is consumed by US-005 |
| 4c | `feat(automacao): schedule spec, next run and bounded catch-up (US-001/002)` | `src/donkey/domain/automation/schedule_pure.nim`, `tests/domain/automation/t_schedule_spec.nim` — needs US-000 (`ckLine`) to compile |
| 5 | `feat(providers): compat adapter, NVIDIA, limits, Alibaba (US-001/002/003)` | `src/donkey/adapters/provider/compat_adapter.nim`, `src/donkey/domain/providers/profile_nvidia.nim`, `src/donkey/domain/providers/profile_alibaba.nim`, `src/donkey/domain/providers/model_limits.nim`, `src/donkey/core/providers/provider_defaults.nim`, `src/donkey/domain/providers/descriptors.nim`, `src/donkey/adapters/provider/runtime_builder.nim`, `tests/adapters/provider/t_compat_adapter.nim`, `tests/adapters/provider/t_compat_alibaba.nim`, `tests/provider/t_nvidia.nim`, `tests/domain/providers/t_model_limits.nim` |
| 6 | `feat(setup): provider menu derived from descriptors` | `src/donkey/app/setup_wizard.nim`, `tests/app/t_setup_provider_list.nim` |
| 7 | `feat(interfaces): gateway contract and ChatBridge (US-001)` | `src/donkey/domain/message.nim`, `src/donkey/domain/gateway/`, `src/donkey/app/chat_bridge.nim`, `tests/domain/gateway/t_chat_contract.nim`, `tests/app/t_chat_bridge.nim` |
| 8 | `feat(multiagente): pure fan-out plan and aggregation (US-001/002)` | `src/donkey/domain/subagent_pure.nim`, `tests/domain/t_fanout_plan.nim` |
| 9 | `feat(multiagente): fan-out supervisor (US-003)` | `src/donkey/app/subagent_runtime.nim`, `tests/app/t_fanout_runtime.nim` — blocked by B1 |
| 10 | `feat(durabilidade): turn journal FSM (US-001)` | `src/donkey/domain/session/turn_journal_pure.nim`, `tests/domain/session/t_turn_journal_pure.nim` |
| 11 | `feat(durabilidade): durable journal store (US-002)` | `src/donkey/adapters/state/turn_journal_store.nim`, `tests/adapters/state/t_turn_journal_store.nim` — needs US-001 `isTurnTerminal` |
| 12 | `docs: PRDs r2 and reviews` | `tasks/prd-{automacao,canais,durabilidade,interfaces,multiagente}.md`, `tasks/reviews/prd-*-r2.md`, `tasks/reviews/merge-v4-foundations.md` |
| 13 | `fix(ferramentas): media upload hardening` | `src/donkey/adapters/channel/telegram.nim`, `src/donkey/domain/channels/telegram_policy.nim`, `tests/adapters/channel/t_telegram_media_upload.nim`, `tests/domain/channels/t_telegram_upload_pure.nim`, `tests/channel/t_telegram.nim` — see B3 |

Declared behaviour deltas for commit 13 (must be in the commit body):
- a custom `apiBase` now restricts egress to its own host instead of disabling
  the allowlist; `tests/channel/t_telegram.nim` TG-022 was renamed and its
  assertion updated accordingly (the old assertion pinned the insecure
  behaviour);
- `DONKEY_TELEGRAM_API_BASE` with non-loopback `http://` now fails at
  construction;
- non-`http(s)` media strings are local paths (neutral text when unavailable),
  never sent to the chat;
- remote photo→document fallback only on photo-specific errors;
- uploads may wait up to 5 s while a flood window is active.

Still deferred in this area: confining absolute media paths to the paddock root
(needs `src/donkey.nim`, a different owner).

Ordering is a dependency chain, not a preference:
- 3 → 4 → 4b (`ckLine` → parser → policy).
- 5 is atomic: profiles, limits, defaults, descriptors and factory are consumed
  together; a partial stage does not compile.
- 7 is atomic: `message.nim` fields are read by `chat_bridge` and
  `chat_response`.
- 8 → 9, 10 → 11.
- 3 must come before 7: both touch `src/donkey.nim` (see the hazard below).
- **Canais US-000 before Automação.** `t_schedule_spec.nim` now iterates every
  `ChannelKind` to prove channel validation is not hardcoded, so it needs
  `ckLine` from `core/types.nim`; committing Automação before Canais US-000
  leaves a red commit.

**Hazard — `src/donkey.nim` mixes two missions.** The file now carries both the
Canais US-000 one-liner (`of ckLine: ports.line`, hunk `@@ -1371`) and the
Interfaces US-002 bridge wiring (imports, `gApiChatBridge`, `apiChatNowMs/Nap`,
gateway route). A plain `git add src/donkey.nim` would put Interfaces work in the
Canais commit. Stage by hunk for whichever mission goes second, e.g.
`git add -p src/donkey.nim` and select only the `ckLine` hunk for the Canais
commit, then `git add src/donkey.nim` for Interfaces.

## Blockers before the commit pass

- **B1 — Multiagente US-003: RESOLVED in the tree.** The supervisor landed with
  `FanoutHandle`/`FanoutStart`/`FanoutState` and a single removal owner
  (`finalizeChild`); 4 suites green, 6 consecutive runs without flake. It
  exports the `mgr.fanouts`/`mgr.children` fields instead of accessors — a
  post-merge test-seam refactor, not a blocker.
- **B6 — Durabilidade US-001: RESOLVED in the tree.** Streamed finals are now
  resendable (`sendQueuedReply` for both sources, CP-5), `tevCommitted` requires
  `isTurnTerminal`, delivery events are phase-gated, `rsStreamed` is sticky, and
  the test file is the PRD name (`t_turn_journal_pure.nim`, 41 tests). Two
  known deviations: `deliveryId` must stay a shared field (Nim 2.2 rejects the
  same field name in two case branches and the adapter reads it from `else`),
  and the PRD's CP-4-streamed bullet says `tpsAccepted` where it means
  `tpsReplyReady` — the implementation follows CP-3 for the accepted case.
- **B2 — Providers US-004 red.** `tests/domain/providers/t_compat_reasoning_off.nim`
  requires `CompatProfile.reasoningOffExtras` + merge in
  `buildCompatRequestBody`; must land with the providers fix or stay out.
- **B7 — Durabilidade US-002 store alignment: in progress.** The store had a
  local `isTurnTerminal` that diverged from the pure one (no phase requirement,
  `rdsQueued` not terminal) and its test fixture never journaled
  `tevReplyReady`. Both must be fixed before commit 11; `rg "func isTurnTerminal"
  src/` must return exactly one definition.
- **B3 — Telegram hardening: RESOLVED in the tree.** It is a Ferramentas fix,
  reviewed against `tasks/reviews/prd-ferramentas-r2.md`; the deltas are listed
  next to commit 13 above. Two existing acceptance checks were narrowed because
  they pinned the old behaviour (`tests/channel/t_telegram.nim` TG-022 allowlist;
  photo→document fallback limited to photo errors) and both are declared there.
- **B5 — `constantTimeEquals`/`safeEquals` duplication: being resolved.**
  `core/security/webhook_auth.nim` becomes the single definition site and
  `line_policy` stops verifying signatures (commit 2 + 4b).
- **B4 — Doc drift.** `tasks/prd-multiagente.md` "Estado" says the fan-out
  runtime does not exist; `tasks/prd-providers.md` US-005 requires
  `tests/app/t_provider_breadth_surface.nim`, which does not exist yet.

## Do not present as done

- Interfaces US-001 is a library with no consumer in `src/` until US-002 wires
  `/v1/chat/completions`. Do not describe it as an endpoint.
- **Known limitation in `ChatBridge`:** after `MaxOrphanTtlMs` the key is
  reclaimed, so a terminal from the abandoned turn that arrives later is
  indistinguishable from the new turn's and can be appended to it. Fixing it
  needs a per-registration turn token (additive API), which belongs with
  US-002/US-003 rather than mid-flight. Until then the window is bounded by the
  600 s TTL.
- `durable_file` extraction, a real `ports/turn_journal.nim` and cross-process
  journal writers are deferred, documented in the store header.
- Duplicated helpers to converge after the merge: endpoint literals in
  descriptors vs. profiles, `redactSecrets` vs `redactForClient`,
  `truncateUtf8` vs `clipToBytes`, `constantTimeEquals` vs `safeEquals`, and the
  fourth private `getStr` copy in `line_pure`.
