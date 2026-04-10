# Donkey — Architecture

## Overview

Donkey follows **hexagonal architecture** (ports & adapters). The domain core is
pure Nim `func` — zero side effects, zero I/O, fully unit-testable. The effectful
shell lives in adapters, wired together by the application layer via Chronos async.

For outbound UI specifically, see [docs/architecture.md](/home/micelio/git/donkey/docs/architecture.md).
That document defines the ownership boundary for presentation surfaces,
replaceable menus, non-editable fallbacks, and streaming/status state.

```
┌─────────────────────────────────────────────────────────────┐
│ INBOUND ADAPTERS                                            │
│   TelegramAdapter ─┐                                        │
│   DiscordAdapter  ─┼→ IdentityResolver → SessionManager     │
│   [future]        ─┘                                        │
├─────────────────────────────────────────────────────────────┤
│ APPLICATION LAYER  (Chronos, effectful)                     │
│   startDaemon → OrchestratorAgent (one per user session)    │
│     ├── MemoryAgent  → MemoryPort  → MdFileAdapter          │
│     ├── ToolAgent    → ToolPort    → McpClientAdapter       │
│     └── [workers]   → ProviderPort → ZhipuAdapter / …      │
│                        HttpPort    → StdHttpAdapter          │
├─────────────────────────────────────────────────────────────┤
│ DOMAIN CORE  (Nim `func`, zero side effects)                │
│   buildPrompt · parseOnboardingResponse · needsOnboarding   │
│   addUser · addAssistant · addToolResult · trimTo           │
├─────────────────────────────────────────────────────────────┤
│ OUTBOUND ADAPTERS                                           │
│   ProviderPort → Zhipu / OpenRouter / Anthropic / Gemini    │
│   ChannelPort  → TelegramAdapter                            │
│   MemoryPort   → MdFileAdapter (F1) / SQLite MAGMA / Postgres MAGMA │
│   HttpPort     → StdHttpAdapter (VPS) / ChronosHttp (IoT)  │
└─────────────────────────────────────────────────────────────┘
```

## Ports

Ports are Nim `concept` — structural typing verified at compile time.
Adapters do not declare conformance; the compiler verifies it.

| Port | Key operations | Adapters |
|------|----------------|----------|
| `ProviderPort` | `complete(CompletionRequest) → Result[CompletionResponse, string]`, `caps()` | Zhipu, OpenRouter, Anthropic, Gemini, MiniMax |
| `ChannelPort` | `send(OutboundMessage) → Result[void, string]`, `receive() → Result[seq[InboundMessage], string]`, `ack(string)` | TelegramAdapter |
| `MemoryPort` | `hasProfile`, `loadContext`, `saveUserMd`, `appendMemory`, `savePreferences` | MdFileAdapter, SQLite MAGMA runtime, Postgres MAGMA runtime |
| `ToolPort` | `listTools() → Result[seq[ToolSchema], string]`, `invoke(ToolCall) → Result[ToolResult, string]` | McpClientAdapter |
| `HttpPort` | `get(url, headers) → Result[HttpResponse, string]`, `post(url, body, headers) → Result[HttpResponse, string]` | StdHttpAdapter, ChronosHttpAdapter (IoT, planned) |

`HttpPort` is internal to adapters — not exposed to the application layer.
All I/O is `Result[T, string]`; exceptions never cross port boundaries.

## Multi-agent model

One `OrchestratorAgent` is spawned per active user session. Workers
(`MemoryAgent`, `ToolAgent`) run as persistent Chronos coroutines for the
lifetime of the session.

```
startDaemon (sync loop)
  │
  ├─ channel.receive()          ← blocking HTTP long-poll (acceptable F4)
  │
  └─ waitFor dispatchMsg(...)   ← runs Chronos event loop
       │
       └─ OrchestratorAgent     ← asyncSpawn'd on first message
            ├─ MemoryAgent       ← asyncSpawn'd by orchestrator
            └─ ToolAgent         ← asyncSpawn'd by orchestrator
```

Agents communicate exclusively through `AsyncQueue[AgentMessage]`. No shared
state. Cancel cascades: `amkCancel` to orchestrator → forwarded to workers.

```nim
type AgentMessageKind* = enum amkTask, amkResult, amkError, amkCancel

type AgentMessage* = object
  id*:       string          # correlation id
  kind*:     AgentMessageKind
  taskKind*: string          # "userMsg" | "loadCtx" | "saveMem" | "invokeTool"
  userId*:   string
  payload*:  string          # task input
  text*:     string          # result text
  error*:    string          # error description
```

## Provider tool-call loop

For each incoming user message the orchestrator runs up to `MaxToolRoundsOrch`
(5) rounds:

```
1. Load context from MemoryAgent (loadCtx)
2. Build prompt (history + context + tools)
3. Call provider (safeComplete)
4a. No tool calls → record assistant text → done
4b. Tool calls → dispatch each to ToolAgent (invokeTool) → add results to history → goto 2
4c. Empty response → inject re-prompt → goto 2
5. If rounds exhausted → send amkError
```

## HttpPort and IoT target

All provider and channel adapters hold an `http: StdHttpAdapter` field.
`StdHttpAdapter` is a zero-field stateless value type wrapping `std/httpclient`.

To target Raspberry Pi Zero (or any musl/static build):

1. Implement `ChronosHttpAdapter` in `src/donkey/adapters/http/chronos_http.nim`
   using `chronos/apps/http/httpclient` + `nim-bearssl` (no OpenSSL dependency):
   ```nim
   type ChronosHttpAdapter* = object
   proc get*(a: ChronosHttpAdapter; url: string; headers: seq[HttpHeader]): Result[HttpResponse, string]
   proc post*(a: ChronosHttpAdapter; url, body: string; headers: seq[HttpHeader]): Result[HttpResponse, string]
   ```
2. Pass `http: newChronosHttpAdapter()` to adapter constructors — no other code changes.
3. Build with musl for a fully static binary:
   ```bash
   CC=musl-gcc nim c -d:release --opt:size --passL:"-static" src/donkey.nim
   strip donkey
   # Result: ~1MB static binary, zero runtime dependencies
   ```

## Memory — two cooperating layers

**F1:** Markdown files in the user paddock.

```
~/.donkey/paddocks/<uuid>/
  USER.md          # identity + profile (OpenClaw format, YAML frontmatter)
  PREFERENCES.md   # TOML: provider, model, language, timezone
  MEMORY.md        # append-only episodic notes
  sessions/<id>.md # per-session summary
```

Files remain human-editable and useful for inspection/debugging.

**F2 (current default):** MAGMA graph state backed by SQLite.
- default database path: `~/.donkey/state/magma.sqlite`
- SQLite base and `sqlite-vec` are embedded in the binary
- Markdown and MAGMA are kept in sync by the runtime

**F2 optional:** PostgreSQL-backed MAGMA for larger installs.
- enabled only when `DONKEY_PG_DSN` is set
- no longer the default installation path

## Provider quirks

Each adapter absorbs its own API peculiarities:

| Adapter | Quirk |
|---------|-------|
| `OpenRouterAdapter` | Sends `HTTP-Referer` and `X-Title` headers |
| `ZhipuAdapter` | GLM tool-call format; native tools (`web_search`, `code_interpreter`) via `caps()` |
| `GeminiAdapter` | Role `"model"` not `"assistant"`; `systemInstruction` top-level; auth via `?key=` query param; history must alternate user/model turns |
| `AnthropicAdapter` | `system` top-level; `x-api-key` + `anthropic-version` headers; `tool_use`/`tool_result` content blocks |
| `MiniMaxAdapter` | OpenAI-compatible (M2 series) |

## Error handling

All I/O returns `Result[T, string]`. The `?` operator propagates errors up.
`try/except` is only used inside adapters to convert exceptions to `Result`.

```nim
# Inside adapter — exceptions caught here, never escape
proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  let resp = ? a.http.post(url, body, headers)    # ? propagates HttpPort errors
  if resp.status < 200 or resp.status >= 300:
    return err("Zhipu API error " & $resp.status)
  try:
    ok(parseZhipuResponse(parseJson(resp.body)))  # JSON parse can throw
  except CatchableError as e:
    err(e.msg)

# Caller uses valueOr / isOkOr / ? — never catches exceptions
let reply = runner.complete(req).valueOr:
  log.error(error)
  return
```

## Testing

```bash
nimble test                           # full suite
testament r tests/app/t_orchestrator.nim  # single file
testament cat app                     # category
```

**Chronos async test pattern** — avoid GC-safety errors:

```nim
# ✗ Wrong: outer var captured by async proc
test "example":
  var got: AgentMessage           # GC-managed var in test scope
  proc doTest() {.async.} =
    got = await queue.get()       # ERROR: not GC-safe
  waitFor doTest()

# ✓ Correct: return value through Future, pass data as parameters
test "example":
  proc doTest(dir: string): Future[AgentMessage] {.async.} =
    let mem = MdFileAdapter(paddocksDir: dir)   # created inside async proc
    return await queue.get()
  let got = waitFor doTest(tmpDir)              # assertions outside async
  check got.kind == amkResult
```

See `CLAUDE.md` for the full list of Chronos async macro restrictions.
