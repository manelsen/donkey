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
│   [19 channels]   ─┘                                        │
├─────────────────────────────────────────────────────────────┤
│ APPLICATION LAYER  (Chronos, effectful)                     │
│   startDaemon → OrchestratorAgent (one per user session)    │
│     ├── MemoryAgent  → MemoryPort  → MAGMA / MdFileAdapter  │
│     ├── ToolAgent    → ToolPort    → McpClientAdapter       │
│     └── tool loop   → ProviderPort → one adapter/provider  │
│                        HttpPort    → StdHttpAdapter          │
├─────────────────────────────────────────────────────────────┤
│ DOMAIN CORE  (Nim `func`, zero side effects)                │
│   buildPrompt · parseOnboardingResponse · needsOnboarding   │
│   addUser · addAssistant · addToolResult · compaction_pure  │
├─────────────────────────────────────────────────────────────┤
│ OUTBOUND ADAPTERS                                           │
│   ProviderPort → one adapter per provider (descriptor table)│
│   ChannelPort  → one adapter per channel (19)               │
│   MemoryPort   → SQLite MAGMA (default) / Postgres / MdFile │
│   HttpPort     → StdHttpAdapter over deadline_transport     │
└─────────────────────────────────────────────────────────────┘
```

## Ports

Ports are Nim `concept` — structural typing verified at compile time.
Adapters do not declare conformance; the compiler verifies it.

| Port | Key operations | Adapters |
|------|----------------|----------|
| `ProviderPort` | `complete(CompletionRequest) → Result[CompletionResponse, string]`, `caps()` | One per provider, chosen by `domain/providers/descriptors.nim`: OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, Zhipu/ZAI, Ollama, Bedrock and the OpenAI-compatible family (`compat_adapter`) |
| `ChannelPort` | `send(OutboundMessage) → Result[void, string]`, `receive() → Result[seq[InboundMessage], string]`, `ack(string)` | One per channel in `adapters/channel/`; the daemon reaches them through `OutboundChannelPort` (`outbound_builder`), and `ports/channel_capability` says what each can do |
| `MemoryPort` | `hasProfile`, `loadContext`, `saveUserMd`, `appendMemory`, `savePreferences` | MdFileAdapter, SQLite MAGMA runtime, Postgres MAGMA runtime |
| `ToolPort` | `listTools() → Result[seq[ToolSchema], string]`, `invoke(ToolCall) → Result[ToolResult, string]` | McpClientAdapter |
| `HttpPort` | `get(url, headers) → Result[HttpResponse, string]`, `post(url, body, headers) → Result[HttpResponse, string]` | StdHttpAdapter over `deadline_transport` (Chronos + BearSSL, a deadline per request) |

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

## HttpPort and the transport

Provider and channel adapters reach HTTP through `HttpPort` (an
`HttpRuntimePort` of closures), never `std/httpclient`. `StdHttpAdapter`
(`adapters/http/std_http.nim`) adds the allowlist, a circuit breaker per
host, retries with backoff and the 429/409 handling; each attempt runs in
`deadline_transport`, a pool of threads each with its own Chronos loop, TLS
by BearSSL, and a deadline that covers the whole request (connection,
headers and every read of the body). The caller blocks only until the
deadline and never runs a Chronos loop of its own.

The channels that keep a connection open use `std/net`, which links the
host's OpenSSL for TLS: the WebSocket client (`adapters/channel/ws_client`,
behind `adapters/network/persistent_socket`) for Slack Socket Mode, Discord,
QQ official and Mattermost, and IRC's own socket. A build without OpenSSL
would need those sockets on BearSSL too.

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
