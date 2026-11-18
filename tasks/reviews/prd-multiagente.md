# Review — tasks/prd-multiagente.md

**Verdict: PASS WITH FIXES.** The cut is right (V4 §6 item 3 = fan-out; V4 §2 already scores
Multiagente "sem rooms/relay/Kanban"), the pure/effect split follows `subagent_pure` ×
`subagent_runtime`, and the barrier test is the correct proof of parallelism. US-001 can start;
**do not open US-002+ until fixes 1–8 are edited into the PRD.**

## Required fixes (blocking)

1. **US-003 "chama `mgr.spawn` sem esperar" is unimplementable**: `spawn` is `{.async.}` (`subagent_runtime.nim:339`) and the id only exists in `SubagentSpawnResult`. Require sequential `await mgr.spawn` (no internal `await`, so children still start together), collect ids/`failedSpawn`, and define **partial-spawn failure**: cancel+reap+remove paddocks of children already created, or fail the whole plan — pick one and test it.
2. **`aggregateFanout(plan, outcomes, fanoutId, policy)` cannot yield `fsrAggregateBudget`/`fsrSessionStop`** — no input carries them. Add a stop input (`stopRequested`, `aggregateDecision`) and define the missing `FanoutAggregate` (fields incl. `timedOut`, `totalTokens`, `stopReason`): US-003 returns a type no story defines and US-004's JSON omits `timed_out`.
3. **Stop reason must ignore `cancelledBySibling`**: in fail-fast the lowest-index outcome is usually a sibling cancellation, masking the real failure and possibly flipping the reason to `fsrSessionStop`; `fanoutShouldCancelSiblings` must not re-trigger on `ssCancelled` (else it re-cancels every 100 ms).
4. **`fsrAggregateBudget` is never enforced**: the ceiling is plan-time only and no story sums live usage. Add the check to the US-003/US-006 supervision loop (cancel all, that reason, test) or drop it from the enum. US-005's token sum proves the counter, not the trigger.
5. **Fail-fast cleanup races the child**: `cancelSubagent` sets status and calls `cleanupPaddock` while the future is only `cancelSoon()` (`:493-515`); a running child can recreate files after removal and "`subagents/` vazio" passes vacuously. Mark `usage.cancelled`, cancel futures, and `workspace.remove` only after each child future is finished/reaped.
6. **`wait=false` has no API and leaks a supervisor**: `Future[FanoutAggregate]` returns ids only at the end (US-004 is impossible as written), and `cancelAll` (`:527`) walks only `children`, so a detached fanout loop outlives shutdown past US-006's 2 s. Drop `wait=false` for the plural tool, or add `FanoutHandle`/a manager `fanouts` table charged to `maxConcurrent` and cancelled by `cancelAll`.
7. **US-005's "clock injetado" has no host**: no clock pattern exists and `newSubagentManager`/`NativeCtx` carry no `nowFn`. Name it (manager field, default `epochMs`) in US-003's signature, or make the throttle pure (`progressDue(lastMs, nowMs, 1000)` in `fanout_pure`).
8. **US-001 over-promises "falha fechado"**: `subagentRequestError` checks shape, not parent tools, so a plan can pass and `spawn` still return "tool 'x' is not available". Pass tool names into `planFanout` (pure, `seq[string]`) or limit the promise to shape/budget.

## Ownership, worktree, baseline

9. **US-004 collides with `prd-ferramentas` US-003/US-006** on `app/native_tools.nim`, `core/tooling/native_tool_dispatch.nim`, `app/session_bootstrap.nim`, `domain/more_tools.nim`; §5's "arquivos disjuntos" is false (`session_bootstrap` is provider US-001's). Declare the writer order (provider US-001 → ferramentas US-003/US-006 → multiagente US-004) and add `domain/subagent_pure.nim` (US-004 `SubagentHardDeniedTools`, US-005 `SubagentInfo.fanoutId`) to §4.1.
10. **§5 does not follow provider §5's parallel exception**: "`git status --short` limpo, senão pare" blocks today's tree, dirty with the provider mission (13 commits since `42b579a9`, new `t_provider_identity`/`t_descriptor_factory`, `quirks.nim` deleted). Copy provider step 1: stop only on a file *you* own, never stash/reset, list owned paths.
11. **242 is stale**: replace §10's hardcoded baseline with roadmap §5 — measure the full suite on start day, record it in the opening commit.
12. **US-007 gates fail on master**: `rg "rooms|relay|kanban" src/donkey` hits `adapters/channel/matrix.nim:8,173` (`/rooms/`); `rg spawn_subagents` "três pontos" misses `native_tool_dispatch.nim` and `SubagentHardDeniedTools` (5 points). Scope both to the mission's files.

## Non-blocking

- AgentEvent/SSE is additive and safe (`buildAgentEventsBody`→`toJson` has no allowlist; tests pin keys, not sets); conditional `fanoutId` keeps `t_agent_events` green. One `aekFanout` for start+done forces SSE consumers to parse `summary` — prefer `aekFanoutStart`/`aekFanoutDone`. Make `SubagentInfo.toJson`'s `fanout_id` conditional too.
- §8 lacks the rooms/relay/Kanban non-goal (only §3 has it); add it and say the mission does **not** close V4 item 3 nor move the scorecard.
- Barrier test must set `parent.asyncCompleteFn` (sync `completeFn` blocks the thread: deadlock, not timeout) and use ≥2 s (`clampSubagentLimits` floors at 1000 ms); `pruneChildren` (retention 64) can drop an unread outcome, so capture outcomes as children finish. Keep "never await each child via `awaitSubagent`" — aggregate from internal `rt.result`.

## Recommended story order

**US-001 → US-002 → US-003 → US-006 → US-005 → US-004 → US-007.** Stop/ceiling (006) must exist
before the tool exposes `wait=false` (004); observability (005) before the aggregate is debuggable
end-to-end; US-004 last because it is the only story crossing into ferramentas' files.
