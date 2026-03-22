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
