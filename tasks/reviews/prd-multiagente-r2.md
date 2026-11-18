# Re-review — tasks/prd-multiagente.md (r2)

**Verdict: PASS WITH FIXES.** R1 1–7 are materially fixed: `spawn` is `{.async.}` with no internal
`await` (`subagent_runtime.nim:339-480`), sequential `await mgr.spawn`, no per-child `awaitSubagent`
(US-003); `FanoutSignal`/`FanoutAggregate`/`timed_out` with precedence spawn>stop>budget>failure (US-002);
runtime ceiling at tick+completion (US-004); settle-before-`remove` spy test (US-004); `FanoutState` in
`mgr.fanouts` in both modes + `cancelAll` over fanouts ≤2 s; pure `fanoutProgressDue` with existing
`epochMs()` (`core/pipeops.nim:46`), no new `NativeCtx` clock. §5 parallel exception, measured baseline and
matrix `/rooms/` scoping are correct. Remaining items are execution blockers, not redesign.

## Remaining fixes

1. **Order is never stated and contradicted twice.** §1's "na ordem" reads numeric 001→007; §4.1 orders
   `subagent_runtime.nim` US-003→004→005→006 and `subagent_pure.nim` US-005→US-006. State
   **001→002→003→006→005→004→007** in §1/§4.1, fix both sequences; "a tool é a penúltima" is false.
2. **US-006 `wait=false` cites US-004**, which now runs after it. Repoint to US-003 (already registers
   `FanoutState` in both modes with deadline/fail-fast); /stop+shutdown coverage lands in US-004.
3. **US-003 partial-spawn loses the created ids.** `Result[FanoutHandle, string]` has no children, so
   `spawnFanout` cannot build `children = criados e cancelados`. Add `createdIds`/failed index to a
   start-result, or register the failed `FanoutState` and return its id in the error; test it.
4. **Budget sums only live ids**, so finished tokens leave the total and 15 then 10 evades a 20 ceiling.
   Sum all children of the fanout (finished + live), keep the 10+15→`fsrAggregateBudget` test.
5. **Double `remove`, unsatisfiable `childSettled`.** US-004 keeps removal in `runChild`'s `finally`
   (`:306`) and adds it to `settleChild`; a cancelled future unwinds there, so `#remove > #create`;
   `cancelAll:554` also removes. Pick one site (post-settlement reaper) and define `childSettled` as terminal
   status **and** `future.finished()` (false inside `runChild`'s `finally`).
6. **US-007 "5 pontos" rg is unachievable.** Literal `spawn_subagents` will appear 3× (more_tools const,
   `AgentNativeTools`, `SubagentHardDeniedTools`); native_tools/session_bootstrap use `SpawnSubagentsToolName`
   (today's `spawn_subagent`: 2 literal lines). Gate on `"spawn_subagents|SpawnSubagentsToolName"`, expect
   5 files, or enumerate the sites.
7. **Capture-on-finish belongs to US-003.** `awaitFanout` is created there but US-005 owns outcome capture;
   with retention 64 an earlier fanout can prune before US-005. Move the criterion into US-003.
8. **Ownership text stale.** `native_tool_dispatch.nim` is not ferramentas US-003/US-006; `session_bootstrap`
   collides with ferramentas **US-003 only**; ferramentas is merged (`418cf193`), only provider US-001
   pending. Also say the `fanouts` table is bookkeeping and only live children count toward `maxConcurrent`
   (US-003 "contado em maxConcurrent" + "não conta em dobro" contradict).
9. Non-blocking: map `ssTimedOut`→`fsrChildTimedOut`; build an explicit `SubagentRequest` for
   `subagentRequestError(task, 0)`; the 2 s fallback that removes anyway contradicts "`settled=true` in every
   `remove`" — make it a test failure or drop the gate.
