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

### raises:[] on func calling isPrivateIp → wrap in try/except ValueError
`isPrivateIp` propagates the `{.raises: [ValueError].}` effect from `parseInt` in `parseIpv4` even though pre-validation makes it unreachable. A `func` annotated `{.raises: [].}` that calls `isPrivateIp` must wrap the call in `try/except ValueError as e: err(e.msg)` inside the `func` body. This is safe and keeps the public API exception-free.

### |>-> + >>= in same expression requires parentheses
`"x" |>-> f("ctx") >>= g` is a parse error — `|>->` tries to consume `f("ctx") >>= g` as its callable. Always parenthesize the `|>->` sub-expression first: `("x" |>-> f("ctx")) >>= g`.

### nativesockets DNS resolution pattern
`getAddrInfo(host, Port(0), AF_UNSPEC, SOCK_STREAM)` returns a `ptr AddrInfo` linked list. Iterate with `.ai_next`; call `getAddrString(it.ai_addr)` to get the IP as a string. Always `defer: freeAddrInfo(info)` immediately after the call — the defer fires even on early `return`.

### Helper procs for Result construction in DiagResult converters
When a public proc returns a non-Result type (e.g. `DiagResult`) but needs to construct intermediate `Result[string, string]` values for `|>->` piping, extract the Result-building logic into a private helper proc. The helper returns `Result[string, string]`, so `ok(v)` / `err(msg)` work normally inside it.

### |>-> inside boolean `and` requires parentheses
`cond and x |>-> f(y)` is a parse error — `|>->` binds `f(y) and ...` as its callable. Always write `cond and (x |>-> f(y))`.

### ok() type inference in test blocks
`ok("value") >>= f` fails in a test block because there is no surrounding Result-returning proc to infer from. Use `Result[string, string].ok("value")` explicitly. The `ok[T, E](v)` generic form does NOT work with this results library.

### Multi-line |>-> chain requires operator at end of line or parentheses
Nim does not allow a line to begin with a binary operator as a continuation (invalid indentation error). For multi-line `|>->` chains, either put the operator at the end of the preceding line (`x |>-> f(...) |>->`) or parenthesize the first call: `(x |>-> f(...)) |>-> g(...)`.

---

## 2026-03-22 - US-009
- What was implemented: Cross-channel identity domain in `src/donkey/domain/identity.nim`. Pure functions for mapping platform IDs to storage keys and validating identity artifacts. Provides `channelKey(kind, rawId)` (last-arg for `|>->`), `parseChannelKind(s)` (Result for `>>=`), `parseChannelKey(key)` (parses "telegram:12345" → `Result[(ChannelKind, string), string]`), `validateRawId(rawId)` (unary for `|>` and `>>=`), `isValidLinkCode(code)` (pure bool for `|>`), and `validateLinkCode(code)` (Result for `>>=`).
- Files changed:
  - `src/donkey/domain/identity.nim` — new pure domain module (all three pipeops operators used in design)
  - `tests/domain/t_identity.nim` — 40 tests across 10 suites covering all functions and all three pipeops operators
- **Learnings:**
  - `func` with `Result` return type using `?` operator for propagation works cleanly for multi-step parsing (parseChannelKey calls parseChannelKind with `?`).
  - `notin` for `string` membership check works against a `const string` (e.g. `c notin LinkCodeAlpha`) — no import needed.
  - `|>` on a func returning `bool` works fine (isValidLinkCode) — pipeops is not limited to string/Result types.
  - Keep `LinkCodeAlpha` constant in domain — both domain validation and adapter UUID generation can share it without duplication.
---

## 2026-03-22 - US-008
- What was implemented: Response sanitizer in `src/donkey/core/output_sanitizer.nim`. Provides `stripTagPair(open, close, text)` (last-arg for `|>->`), `stripThoughtTags(text)` (strips `<thinking>` and `<think>` blocks, designed for `|>`), `maskSecrets(text)` (replaces secret tokens with `[REDACTED]` using the same tokenizer as `secret_scan`, designed for `|>`), and `cleanResponse(text)` (main entry point chaining `text |> stripThoughtTags |> maskSecrets`).
- Files changed:
  - `src/donkey/core/output_sanitizer.nim` — new pure module (37 tests passing)
  - `tests/core/t_output_sanitizer.nim` — 37 tests across 8 suites covering all functions and all three pipeops operators
- **Learnings:**
  - Multi-line `|>->` chains: cannot start a continuation line with `|>->` — Nim reports invalid indentation. Fix: put `|>->` at the end of the preceding line, or wrap the first call in parens: `(x |>-> f(...)) |>-> g(...)`.
  - `func` can freely mutate its implicit `result` variable in a loop — this is not a side-effect restriction. Pattern `result = text; for pair in pairs: result = result |>-> f(pair[0], pair[1])` compiles cleanly.
  - Iterating an array of tuples with `for pair in ThoughtTagPairs: let (open, close) = pair` is cleaner than `for (open, close) in ...` which may have parsing edge cases.
  - `>>=` pipeline test pattern confirmed: `Result[string, string].ok(cleaned) >>= checkForSecrets` — must use full type annotation in test blocks.
---

## 2026-03-22 - US-007
- What was implemented: Shannon entropy analysis added to `src/donkey/core/security/secret_scan.nim`. Added `calculateEntropy()` (Shannon formula using `std/math.log2`), `entropyAbove(threshold, s)` (last-arg for `|>->`), `scanHighEntropy()` (detects random-looking tokens above `EntropyThreshold = 3.5` bits/char), `checkForSecrets()` (Result gate for `>>=` chaining), `skHighEntropy` enum variant. All three pipeops operators demonstrated in production code and tests. Existing prefix-mask and contextual-key scanners unchanged.
- Files changed:
  - `src/donkey/core/security/secret_scan.nim` — added entropy functions, `checkForSecrets`, `skHighEntropy`; added `import std/math` and `import ../pipeops`
  - `tests/core/t_secret_scan.nim` — added suites: `calculateEntropy`, `entropyAbove`, high-entropy detection, pipeops operators (8 new tests); added `import std/sequtils` and `import donkey/core/pipeops`
- **Learnings:**
  - `|>->` inside an `and` expression must be parenthesized: `a and (x |>-> f(y))` — without parens, `|>->` tries to consume `f(y) and ...` as its callable and gives a type mismatch.
  - `ok("value")` cannot infer Result type in test blocks (no surrounding proc with Result return type) — must use `Result[string, string].ok("value")` explicitly. The `ok[T, E](v)` form does NOT work.
  - `filterIt` requires `import std/sequtils` even when `strutils` is already imported.
  - Shannon entropy with `std/math.log2` is pure and compiles in `func` without any exception annotation issues.
---

## 2026-03-22 - US-006
- What was implemented: DNS resolver adapter with SSRF protection. `src/donkey/core/dns.nim` — pure module with `blockIfPrivate` (unary, for `|>` and `>>=`) and `labelledBlock` (last-arg, for `|>->`). `src/donkey/adapters/network/dns_resolver.nim` — `safeResolve` proc using `nativesockets.getAddrInfo` + `getAddrString`, iterates all resolved IPs and blocks if any is private.
- Files changed:
  - `src/donkey/core/dns.nim` — new pure module
  - `src/donkey/adapters/network/dns_resolver.nim` — new adapter
  - `tests/core/t_dns.nim` — 29 tests across 4 suites covering all three pipeops operators
  - `tests/adapters/network/t_dns_resolver.nim` — 10 tests covering SSRF blocking, |>, >>=, |>->
- **Learnings:**
  - `nativesockets.getAddrString*` and `freeAddrInfo` are exported from `std/nativesockets` in Nim 2.2 — use `getAddrInfo(host, Port(0), AF_UNSPEC, SOCK_STREAM)` + iterate linked list via `.ai_next` for multi-address resolution.
  - `defer: freeAddrInfo(info)` fires even on early `return` inside a `try` block — safe pattern for cleaning up `ptr AddrInfo`.
  - `{.raises: [].}` on a `func` that calls `isPrivateIp` fails because `parseInt` in `parseIpv4` is statically marked as raising `ValueError`, even though pre-validation makes it unreachable. Fix: wrap the call in `try/except ValueError` inside the `func` body.
  - Combined `|>->` + `>>=` in a single expression requires explicit parentheses: `("ip" |>-> f("ctx")) >>= g` — without parens, `|>->` tries to consume `f("ctx") >>= g` as its callable argument and fails.
---

## 2026-03-22 - US-005
- What was implemented: `src/donkey/core/network.nim` — pure SSRF IP validator. Provides `parseIpv4` (dotted-quad → `Result[array[4, uint8], string]`), `isPrivateOctets` (covers RFC 1918 + CGNAT + loopback + link-local + bogon + reserved ranges), `isPrivateIpv6` (textual prefix matching for ::1, fe80::, fc/fd ULA, ::ffff:), and `isPrivateIp` (unified entry point returning `Result[bool, string]`, designed for `|>` and `>>=` piping).
- Files changed:
  - `src/donkey/core/network.nim` — new pure module
  - `tests/core/t_network.nim` — 36 tests across 5 suites covering all functions and all three pipeops operators
- **Learnings:**
  - `strutils` must be imported in tests even when `contains(string, string)` seems obvious — `results` `Opt.contains` overload wins otherwise (same gotcha as US-003).
  - Using `int(o[0])` casts before range checks avoids `uint8` literal arithmetic issues entirely — cleaner than `16u8..31u8` range syntax.
  - Pre-validation with `allCharsInSet({'0'..'9'})` + `len > 3` guard makes `parseInt` safe inside `func` without try/except — keeps the function clean.
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
