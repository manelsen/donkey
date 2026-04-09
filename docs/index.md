# Donkey
An AI agent daemon for multi-channel messaging

## Overview

Donkey connects multiple messaging channels (Telegram, Discord, Slack, WeChat...) to various LLM providers. It uses a hexagonal architecture where the core domain is isolated from infrastructure concerns, ships SQLite-first by default, and treats outbound UI as a core presentation concern rather than adapter-local state.

## Features

- **Multi-Channel**: 12+ channel integrations (Telegram, Discord, Slack, WeChat, QQ, WhatsApp...)
- **Multi-Provider**: Connect to any LLM provider (Anthropic, OpenAI, OpenRouter, Gemini...)
- **Hooks System**: Intercept and modify message flow at any phase
- **Memory**: Persistent workspace memory with optional semantic retrieval
- **Pure Core**: Hexagonal architecture with pure functional cores

## Quick Example

```bash
nimble build
./donkey setup
./donkey start
```

## Installation

```bash
git clone https://github.com/manelsen/donkey.git
cd donkey
nimble build
```

See [Installation Guide](getting_started/installation.md) for detailed setup.

## Architecture

```
┌─────────────────────────────────────────┐
│              Channels                     │
│  (Telegram, Discord, Slack...)          │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Core                        │
│  Session, Orchestrator, Hooks            │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Providers                   │
│  (Anthropic, OpenAI, Gemini...)         │
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
# Start daemon
./donkey start

# Validate install
./donkey doctor

# User service
./donkey service install
./donkey service start

# Version
./donkey --version
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
