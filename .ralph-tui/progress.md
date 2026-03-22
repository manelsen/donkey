# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

### chronos/timer Duration disambiguation
When both `std/times` and `chronos` are imported, `milliseconds()` is ambiguous (`TimeInterval` vs `Duration`). Fix: `import chronos/timer as ctimer` and call `ctimer.milliseconds(n.int64)` explicitly.

### Unused import removal
`strutils` is often accidentally imported; `nim check --mm:orc` with `--warningAsError:on` catches these. Always verify imports are used.

### pipeops / results import rule
`pipeops.nim` is the sole entry point for `results`. Domain and app code must `import ../core/pipeops` (not `import results` directly). pipeops re-exports results plus `|>`, `|>->`, `>>=`.

### Domain func + stdlib exceptions → Result
When a pure `func` needs to call stdlib procs that raise (e.g. `parseInt`, `parseHexInt`), wrap the call in try/except and return `Result[T, string]`. Never return a sentinel value (e.g. `int64.low`) from a domain func — callers use `.valueOr()` or `?` instead. This is the accepted pattern (see calc.nim, reminder.nim).

### Replacing try/except in func with pre-validation
For simple numeric parsing where the value is already structurally validated (e.g. a digit-only string slice), use `allCharsInSet({'0'..'9'})` instead of try/except. This keeps pure funcs exception-free entirely when the format guarantee already holds.

### Generic type parameter on non-generic funcs
`func foo*[M](depth: int; s: MailboxStats): MailboxStats` — the `[M]` is invalid when no generic is actually used in the signature. Nim gives `Error: cannot instantiate: 'M'` at the call site. Remove unused type params from function signatures.

### Inner func accessing outer var
An inner `func` that reads/writes an outer `var` is a side-effect; Nim rejects it with `'foo' can have side effects`. Workaround: use a module-level `proc` for the callback, or redesign the test to avoid shared mutable state.

### ok/err type inference in mixed-return procs
`ok(v)` and `err(msg)` only infer the Result type when the surrounding proc/func returns `Result[T, E]`. In a proc returning some other type (e.g. `DiagResult`), use `Result[string, string].ok(v)` / `Result[string, string].err(msg)`. The `ok[T, E](v)` generic syntax does NOT work with this results library version.

### Helper procs for Result construction in DiagResult converters
When a public proc returns a non-Result type (e.g. `DiagResult`) but needs to construct intermediate `Result[string, string]` values for `|>->` piping, extract the Result-building logic into a private helper proc. The helper returns `Result[string, string]`, so `ok(v)` / `err(msg)` work normally inside it.

---

## 2026-03-22 - US-004
- What was implemented: `donkey doctor` CLI command — system diagnostics tool checking for docker binary + compose plugin, pgvector/PostgreSQL (optional F2+), and API key environment variables.
- Files changed:
  - `src/donkey/core/diagnostics.nim` — new pure module: `DiagResult`, `DiagStatus`, and pipeline-friendly functions (`toDiagResult`, `markWarn`, `formatResult`, `countFailed`, `allPassed`, `formatReport`)
  - `src/donkey/app/doctor.nim` — new effectful module: `runDockerCmd`, `checkDockerCompose`, `checkDocker`, `checkApiKey`, `checkPgvector`, `runDoctorChecks`, `printDoctorReport`, `runDoctor`
  - `tests/core/t_diagnostics.nim` — 22 tests covering all pure functions and all three pipeops operators
  - `tests/app/t_doctor.nim` — 16 tests covering effectful checks, environment-independence, and `>>=` chaining
  - `src/donkey.nim` — added `import donkey/app/doctor`, `doctor` to help text, `doctor` command dispatch
- **Learnings:**
  - `ok[T, E](v)` syntax does NOT work with this results library — use `Result[T, E].ok(v)` at call sites where return type can't be inferred.
  - Helper procs returning `Result[string, string]` are the clean pattern when a public proc returns a non-Result type (e.g. `DiagResult`) but needs `|>->` piping; `ok(v)` / `err(msg)` work normally inside Result-returning procs.
  - `checkDockerCompose` with `{.gcsafe, raises: [].}` + `try/except` compiles correctly for `>>=` chaining.
  - `markWarn` only downgrades `dsErr` → `dsWarn`; `dsOk` passes through unchanged — important for test expectations when DSN is set vs not set.
---

## 2026-03-22 - US-003
- What was implemented: `src/donkey/core/actor.nim` — pure actor model mailbox types and resilience logic (BEAM/Pincer-inspired). Provides `Envelope[M]`, `DeadLetter[M]`, `MailboxPolicy`, `MailboxStats`, and pipeline-friendly pure functions (`incrementAttempt`, `toDeadLetter`, `trackSent/Received/Dropped`, `updateMaxDepth`, `applyPolicy`, `shouldRetry`, `isExpired`). All operators demonstrated: `|>` for unary transforms, `|>->` for last-arg composition, `>>=` for Result chaining.
- Files changed:
  - `src/donkey/core/actor.nim` — new module
  - `tests/core/t_actor.nim` — 30 tests across 6 suites
- **Learnings:**
  - `core/` boundary rule blocks Chronos/asyncsync — actor mailbox async transport stays in `app/`; `core/actor.nim` provides the pure domain model (Envelope, DeadLetter, MailboxStats) that the app-layer AsyncQueue wraps.
  - `500_i64` syntax is invalid in Nim — use plain `500` and let type inference work (or cast explicitly: `int64(500)`).
  - `strutils` must be imported in tests to get `contains(string, string)` — otherwise the `results` `Opt.contains` overload takes precedence and causes a type mismatch.
  - `func` cannot read outer `var` (side effect); the `>>=` template requires `{.gcsafe, raises: [].}` so inner test funcs must be pure and self-contained.
---

## 2026-03-22 - US-002
- What was implemented: Eradicated try/except from domain layer; enforced pipeops topology (all domain code imports via `pipeops`, not `results` directly).
- Files changed:
  - `src/donkey/domain/calc.nim` — `import results` → `import ../core/pipeops`
  - `src/donkey/domain/reminder.nim` — added `import ../core/pipeops`; changed `parseIsoWhen` return type from `int64` (sentinel) to `Result[int64, string]`; replaced try/except in `parseWhen` relative-offset branch with `allCharsInSet` digit guard; updated caller to use `.valueOr(base + 3_600)` pipeline style
  - `src/donkey/domain/builtin_tools.nim` — replaced try/except in `isPrivateUrl` with `allCharsInSet({'0'..'9'})` pre-validation
- **Learnings:**
  - Sentinel return values (`int64.low`) in domain funcs are the real anti-pattern — not just try/except per se. Callers shouldn't need to know magic values; they should use Result's `.valueOr()` or `?`.
  - `allCharsInSet({'0'..'9'})` from `std/strutils` eliminates try/except entirely for digit validation, keeping funcs clean.
  - `func` in Nim CAN have try/except (it only forbids side effects); returning `Result` from such funcs is the correct architecture per CLAUDE.md.
  - Boundary checker and 50 testament tests all pass after changes.
---

## 2026-03-22 - US-001
- What was implemented: Strict compilation flags (`--styleCheck:error`, `--warningAsError:on`, `--panics:on`) were already present in `config.nims`. Fixed all resulting errors/warnings so the codebase compiles clean.
- Files changed:
  - `src/donkey/adapters/tool/mcp_client.nim` — renamed `result_node` → `resultNode` (snake_case style error)
  - `src/donkey/config/tools_registry.nim` — removed unused `strutils` import
  - `src/donkey/adapters/provider/zhipu.nim` — removed unused `strutils` import
  - `src/donkey/adapters/provider/gemini.nim` — removed unused `uri` import
  - `src/donkey/adapters/provider/minimax.nim` — removed unused `strutils` import
  - `src/donkey/app/heartbeat.nim` — removed unused `strutils` import
  - `src/donkey.nim` — fixed deprecated `sleepAsync(int)` by adding `import chronos/timer as ctimer` and using `ctimer.milliseconds(n.int64)`
- **Learnings:**
  - `nim check --mm:orc` with `config.nims` active is the right command to surface all errors
  - `XDeclaredButNotUsed` is a Hint (not Warning), so `warningAsError:on` does NOT promote it to an error — unused variables declared with `let` in loops are tolerated
  - Chronos `Duration` disambiguates from `std/times.TimeInterval` via qualified import alias
  - All 29+ testament tests pass after fixes
---
