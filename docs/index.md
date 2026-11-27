# Donkey
An AI agent daemon for multi-channel messaging

## Overview

Donkey connects multiple messaging channels to various LLM providers. It uses a hexagonal architecture where the core domain is isolated from infrastructure concerns, ships SQLite-first by default, and treats outbound UI as a shared presentation concern rather than adapter-local state.

## Features

- **Multi-Channel (19)**: Telegram, Discord, Slack, WhatsApp, Microsoft Teams, Google Chat, Mattermost, WeCom, WeChat, QQ, Feishu, DingTalk, LINE, Matrix, Signal, IRC, SMS, Email and CLI; attachments in on most, files out where the adapter uploads (`send_file`)
- **Multi-Provider**: OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, ZAI, Groq, Ollama, OpenCode Go and Zen, NVIDIA, Alibaba, Fireworks, Mistral, Bedrock and Azure OpenAI, each with its own adapter
- **SQLite-first Memory**: MAGMA, a temporal graph in embedded SQLite (+ `sqlite-vec`); PostgreSQL + pgvector optional
- **Long conversations**: an append-only history, prompt caching and step compaction
- **Self-improvement**: learned skills per person, background review, curator, `/insights`
- **Pure Core**: Hexagonal architecture with pure functional cores, enforced by architecture tests
- **Operational Surface**: `setup`, `doctor`, `service`, `ctl`, the management TUI, metrics and traces

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
- [Channels](topics/channels.md) - The 19 channel adapters, their settings and what each carries
- [Commands](topics/commands.md) - Slash command system
- [Sessions](topics/sessions.md) - Sessions, the append-only history, compaction, transcripts and recovery
- [Providers](topics/providers.md) - Provider descriptors, compat profiles, limits and adding a provider
- [Memory](topics/memory.md) - MAGMA, recall and the paddock files
- [Conversation search](topics/conversation-search.md) - Searching old conversations
- [Media](topics/media.md) - Inline images, transcripts, voice replies and send_file
- [Named agents](topics/named-agents.md) - Agents with their own role, provider and notes
- [Learned skills](topics/learned-skills.md) - Skills the agent learns per person, the review and the curator
- [Schedules](topics/schedules.md) - Cron, intervals and one-off schedules
- [GitHub and git](topics/github-and-git.md) - The read-only github and git_inspect tools
- [Metrics](topics/metrics.md) - Prometheus metrics, per-turn traces, OpenTelemetry and insights
- [Error policy](topics/error-policy.md) - How errors are reported and kept
- [Hooks](topics/hooks.md) - Message flow interception
- [Interfaces](topics/interfaces.md) - OpenAI-compatible API, SSE, dashboard and the worker budget
- [Outbound Presentation](architecture.md) - UI surface ownership, fallback policy, and streaming/status model
- [Architecture](ARCHITECTURE.md) - Ports and adapters, layers, the tool loop

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

The most used; the full list is in [Commands](topics/commands.md).

| Command | Description |
|---------|-------------|
| `/start`, `/help`, `/menu` | Start, help, the command menu |
| `/new` | Start a new session |
| `/compact` | Turn the old part of the conversation into a summary now |
| `/continue <code>` | Link this channel to you on another channel |
| `/model`, `/think` | Switch model, set thinking level |
| `/tasks`, `/agents` | Your task board, the active agents |
| `/learn`, `/refine`, `/insights` | Learned skills and your usage report |
| `/memory`, `/forget` | Memory tools |

## Links

- [GitHub](https://github.com/manelsen/donkey)
- [Architecture](architecture.md)
- [Contributing](contributing.md)
