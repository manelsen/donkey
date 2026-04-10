# Donkey
An AI agent daemon for multi-channel messaging

## Overview

Donkey connects multiple messaging channels to various LLM providers. It uses a hexagonal architecture where the core domain is isolated from infrastructure concerns, ships SQLite-first by default, and treats outbound UI as a shared presentation concern rather than adapter-local state.

## Features

- **Multi-Channel**: Telegram, Discord, QQ, Slack, WeChat, Feishu, Matrix, and more
- **Multi-Provider**: ZAI, OpenRouter, Anthropic, OpenAI, Gemini, DeepSeek, MiniMax, Ollama
- **SQLite-first Memory**: Embedded SQLite + `sqlite-vec` in the normal build
- **Pure Core**: Hexagonal architecture with pure functional cores
- **Operational Surface**: `setup`, `doctor`, `service`, TUI dashboard, and heartbeat automation

## Quick Example

```bash
nimble build
./donkey setup
./donkey start
```

## Happy Path

```bash
nimble build
./donkey setup
./donkey doctor
./donkey start
```

See [Installation Guide](getting_started/installation.md) for detailed setup.

## Architecture

```
┌─────────────────────────────────────────┐
│            Channels + UI                  │
│ (Telegram, Discord, QQ, Slack...)        │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│       Core / Sessions / Outbound         │
│  Orchestrator, routing, presentation     │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│    Providers / Memory / Tool Runtimes    │
│ SQLite-first MAGMA, tools, providers     │
└─────────────────────────────────────────┘
```

## Documentation

### Getting Started
- [Installation](getting_started/installation.md) - Install and configure Donkey
- [Quickstart](quickstart.md) - First bot in 5 minutes
- [Basic Concepts](getting_started/basic_concepts.md) - Core architecture

### Topics
- [Commands](topics/commands.md) - Slash command system
- [Hooks](topics/hooks.md) - Message flow interception
- [Memory](topics/memory.md) - Persistent storage
- [Sessions](topics/sessions.md) - Session management
- [Outbound Presentation](architecture.md) - UI surface ownership, fallback policy, and streaming/status model

### Reference
- [Configuration](reference/configuration.md) - Complete configuration reference
- [API Reference](reference/README.md) - Public API documentation

## Command Line

```bash
./donkey setup
./donkey doctor
./donkey start
./donkey service install
./donkey service start
```

## Configuration

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/donkey.log"

[sandbox]
mode = "oci"
runtime = "docker"
image = "alpine"
allow_host_fallback = false
allow_network = false
read_only_rootfs = true
```

Optional instance defaults:

```toml
[donkey]
default_provider = "zai-coding"
default_model = "glm-4.7"
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/start` | Start conversation |
| `/help` | Show help |
| `/reset` | Reset session |
| `/models` | Switch model |
| `/think` | Set thinking level |
| `/memory` | Memory tools |
| `/compact` | Compact context |

## Links

- [GitHub](https://github.com/manelsen/donkey)
- [Architecture](architecture.md)
- [Contributing](contributing.md)
