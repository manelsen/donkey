# Basic Concepts
Understanding Donkey's architecture

## The Big Picture

Donkey is an AI agent daemon that connects messaging channels to LLM providers. It handles the full lifecycle of a conversation: receiving messages, processing them through AI, executing tools, and sending responses.

## Hexagonal Architecture

Donkey uses hexagonal (ports & adapters) architecture to keep the core business logic isolated from infrastructure:

```
┌─────────────────────────────────────────┐
│              Channels                    │
│     Telegram, Discord, Slack, ...         │
└──────────────────┬──────────────────────┘
                   │ InboundMessage
                   ▼
┌─────────────────────────────────────────┐
│               Ports                      │
│   ChannelPort, ProviderPort, HookPort   │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│               Core                       │
│   Session, Orchestrator, Tool Loop      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Adapters                    │
│    LLM Providers, Memory, Tools          │
└─────────────────────────────────────────┘
```

### Why Hexagonal?

- **Testable**: Core logic has no external dependencies
- **Flexible**: Swap adapters without changing core
- **Maintainable**: Clear separation of concerns

## Key Concepts

### Session

A session represents a conversation with a user. Each user can have multiple sessions, one per channel.

```nim
type
  SessionId* = distinct string
  Session* = object
    id*: SessionId
    userId*: UserId
    channel*: ChannelKind
    messages*: seq[ChatMessage]
    createdAt*: DateTime
```

### Orchestrator

The orchestrator is the heart of message processing:

1. Receives inbound message
2. Routes to session
3. Executes pre-LLM hooks
4. Calls LLM with context
5. Executes tool calls if needed
6. Executes post-LLM hooks
7. Sends response

### Ports (Interfaces)

Ports define how the core interacts with the outside world:

| Port | Purpose |
|------|---------|
| `ChannelPort` | Send/receive messages |
| `ProviderPort` | Call LLM APIs |
| `HookPort` | Intercept message flow |
| `MemoryPort` | Persist data |
| `ToolPort` | Execute tools |

### Adapters

Adapters implement ports for specific technologies:

| Adapter | Implements | Technology |
|---------|------------|------------|
| `TelegramAdapter` | ChannelPort | Telegram Bot API |
| `DiscordAdapter` | ChannelPort | Discord WebSocket |
| `AnthropicAdapter` | ProviderPort | Anthropic API |
| `MdFileAdapter` | MemoryPort | Markdown files |

## Message Flow

When a user sends a message:

```
1. Channel receives message (Telegram, Discord, etc.)
           │
           ▼
2. Session ingress - create new session or reuse existing
           │
           ▼
3. Orchestrator receives message
           │
           ▼
4. Execute hpPreLlm hooks (context injection, validation...)
           │
           ▼
5. Build prompt with history and context
           │
           ▼
6. Call LLM (Anthropic, OpenAI, etc.)
           │
           ▼
7. Execute hpPostLlm hooks (response modification...)
           │
           ▼
8. Execute tool calls if needed (hpPreTool → tool → hpPostTool)
           │
           ▼
9. Execute hpPostResponse hooks
           │
           ▼
10. Send response via channel
```

## Hooks System

Hooks provide middleware-style interception:

```nim
type
  HookPhase* = enum
    hpPreLlm       # Before LLM call
    hpPostLlm      # After LLM response
    hpPreTool      # Before tool execution
    hpPostTool     # After tool result
    hpPostResponse # Before sending response
```

### Example: Spam Filter

```nim
proc spamFilter*(ctx: HookContext): HookResult =
  if "buy now" in ctx.message.toLower():
    return newHookResultRejected(ctx, "Spam detected")
  return newHookResultContinue(ctx)
```

## Memory System

Donkey uses two cooperating memory layers:

### F1: Workspace Memory (Markdown)

Each user has a paddock directory:

```
~/.donkey/paddocks/<user_id>/
├── USER.md          # Identity
├── MEMORY.md        # Memories
├── PREFERENCES.md   # Settings
└── NOTES.md        # Notes
```

### F2: Structured Memory (MAGMA)

By default this is SQLite-backed MAGMA stored under `~/.donkey/state/`.
PostgreSQL remains optional for larger installs, but it is no longer the
default path.

## Commands

Slash commands are parsed and routed:

| Route | Description | Example |
|-------|-------------|---------|
| `crLocal` | Handled locally | `/help`, `/start` |
| `crSessionTask` | Session operation | `/reset`, `/compact` |
| `crUi` | Interactive UI | `/models`, `/think` |
| `crStatus` | Status query | `/status` |
| `crPing` | Ping | `/ping` |

## Error Handling

Donkey uses `Result[T, E]` instead of exceptions:

```nim
type
  MyError* = object
    kind*: ErrorKind
    message*: string

proc fetchData*(url: string): FetchResult =
  if url.len == 0:
    return err(MyError(kind: ErrEmptyUrl, message: "URL required"))
  # ... success path
  return ok(data)
```

## Next Steps

- [Commands System](topics/commands.md)
- [Hooks System](topics/hooks.md)
- [Memory System](topics/memory.md)
- [Configuration Reference](reference/configuration.md)
