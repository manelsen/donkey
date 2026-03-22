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
