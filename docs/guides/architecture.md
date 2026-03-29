# Architecture
Hexagonal architecture overview

## Overview

Donkey uses hexagonal (ports & adapters) architecture to keep business logic isolated from infrastructure.

## Layers

```
┌─────────────────────────────────────────┐
│           Shell / CLI                     │
│         src/donkey.nim                   │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│         Application Layer                 │
│         src/donkey/app/                 │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│           Core / Domain                   │
│         src/donkey/core/                 │
│         src/donkey/domain/               │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Ports                        │
│         src/donkey/ports/               │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│           Adapters                       │
│         src/donkey/adapters/            │
└─────────────────────────────────────────┘
```

## Core Layer

Pure domain logic with no external dependencies.

### `core/types.nim`

Foundational types:
- `UserId`, `SessionId`
- `ChannelKind`
- `LogLevel`

### `core/actor.nim`

Actor model primitives for session management.

### `core/session/`

Session management.

### `core/tooling/`

Tool execution logic.

### `core/onboarding/`

User onboarding state machine.

## Domain Layer

Business logic types.

### `domain/message.nim`

Message types:
- `ChatMessage`
- `InboundMessage`
- `OutboundMessage`
- `CompletionRequest`
- `CompletionResponse`

### `domain/personality.nim`

User personality traits.

## Ports Layer

Interface definitions (no implementations).

### `ports/channel.nim`

Messaging channel interface.

### `ports/provider.nim`

LLM provider interface.

### `ports/memory.nim`

Memory system interface.

### `ports/hook.nim`

Hook system interface.

### `ports/tool.nim`

Tool interface.

## Adapters Layer

Port implementations.

### `adapters/channel/`

Channel adapters:
- `telegram.nim`
- `discord.nim`
- `slack.nim`
- `wechat.nim`
- etc.

### `adapters/provider/`

LLM provider adapters:
- `anthropic.nim`
- `openai.nim`
- `openrouter.nim`
- `gemini.nim`
- etc.

### `adapters/memory/`

Memory adapters:
- `md_file.nim` - Markdown workspace
- `postgres.nim` - PostgreSQL semantic

## Application Layer

### `app/orchestrator.nim`

Session actor, message orchestration, LLM loop.

### `app/session_manager.nim`

Session lifecycle management.

### `app/native_tools.nim`

Built-in tools (shell, git, fetch).

## Data Flow

```
Channel Adapter
    ↓
Session Ingress
    ↓
Orchestrator
    ↓
Pre-LLM Hooks
    ↓
LLM Provider
    ↓
Post-LLM Hooks
    ↓
Tool Execution
    ↓
Post-Tool Hooks
    ↓
Response Hooks
    ↓
Channel Adapter
```

## Design Principles

### 1. Pure Core

Core has no dependencies on:
- `asyncdispatch`
- `chronos`
- `ws`
- `httpclient`
- External packages

### 2. Result[T, E] Pattern

No exceptions in adapters:

```nim
proc fetchData*(): Result[Data, Error] =
  if invalid:
    return err(Error(message: "Invalid"))
  return ok(data)
```

### 3. Dependency Injection

Ports are interfaces, adapters are injected:

```nim
proc processMessage*(
  provider: ProviderPort,
  memory: MemoryPort,
  hooks: seq[HookPort]
) = ...
```

### 4. Actor Model

Sessions are actors with mailboxes:

```nim
type
  Session* = ref object
    inbox: AsyncQueue[Envelope]
    state: SessionState
```

## Key Design Decisions

See `docs/adr/` for architectural decisions:

| ADR | Decision |
|-----|----------|
| ADR-001 | Nim + Chronos (not asyncdispatch) |
| ADR-002 | Result[T,E] no exceptions |
| ADR-003 | Docker sandbox for bash |
| ADR-004 | Structured function calling |
| ADR-005 | Paddock isolation |
| ADR-006 | Tool call repetition detection |

## Testing

Tests mirror source structure:

```
tests/
├── core/          # Core tests
├── ports/         # Port tests
├── adapters/      # Adapter tests
└── domain/        # Domain tests
```

## Quality Gates

```bash
# Compile
nim c --mm:orc src/donkey

# Boundary check
bash scripts/check_boundaries.sh

# Tests
nimble test
```

## Related

- [Contributing Guide](contributing.md)
- [ADR Documents](../adr/)
