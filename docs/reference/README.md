# API Reference
Complete documentation for all public APIs

## Overview

This reference documents all public APIs in Donkey. Types and functions marked with `*` are exported.

## Core Modules

### Ports (Interfaces)

| Module | Description |
|--------|-------------|
| [hook](hook.md) | Hook system interface |
| [channel](channel.md) | Channel abstraction |
| [provider](provider.md) | LLM provider interface |
| [memory](memory.md) | Memory system interface |
| [tool](tool.md) | Tool abstraction |

### Core

| Module | Description |
|--------|-------------|
| [types](types.md) | Core types (UserId, SessionId...) |
| [session](session.md) | Session management |
| [orchestrator](orchestrator.md) | Message orchestration |

### Domain

| Module | Description |
|--------|-------------|
| [message](message.md) | Message types |
| [agent_message](agent_message.md) | Internal agent messages |

### Commands

| Module | Description |
|--------|-------------|
| [command_routing](command_routing.md) | Command parsing and routing |
| [command_catalog](command_catalog.md) | Command metadata catalog |

## Adapters

### Channel Adapters

| Adapter | File | Description |
|---------|------|-------------|
| Telegram | `adapters/channel/telegram.nim` | Telegram Bot API |
| Discord | `adapters/channel/discord.nim` | Discord WebSocket |
| Slack | `adapters/channel/slack.nim` | Slack API |

### Provider Adapters

| Adapter | File | Description |
|---------|------|-------------|
| Anthropic | `adapters/provider/anthropic.nim` | Claude API |
| OpenAI | `adapters/provider/openai.nim` | GPT API |
| OpenRouter | `adapters/provider/openrouter.nim` | Multi-provider |
| Gemini | `adapters/provider/gemini.nim` | Google AI |

### Memory Adapters

| Adapter | File | Description |
|---------|------|-------------|
| MdFile | `adapters/memory/md_file.nim` | Markdown files |
| Postgres | `adapters/memory/postgres.nim` | PostgreSQL + pgvector |

## Configuration

| Document | Description |
|----------|-------------|
| [Configuration](configuration.md) | Complete donkey.toml reference |
| [Types](types.md) | Configuration types |

## Examples

### Creating a Hook

```nim
import donkey/ports/hook

proc myHook*(ctx: HookContext): HookResult =
  # Process context
  var modified = ctx
  modified.metadata["processed"] = "true"
  newHookResultContinue(modified)

# Register hook
let definition = HookDefinition(
  name: "my_hook",
  phase: hpPreLlm,
  handler: myHook
)
executor.registerHook(definition)
```

### Using Memory

```nim
import donkey/adapters/memory/md_file

let memory = newMdFileAdapter("~/.donkey/paddocks")
let userDoc = memory.readUserDoc(userId, "MEMORY.md")
```

### Configuration Loading

```nim
import donkey/config/loader

let config = loadConfig("~/.config/donkey/donkey.toml").get()
```
