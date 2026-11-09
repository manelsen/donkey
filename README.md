---
title: Donkey
sdk: docker
app_port: 8080
---

# Donkey 🫏

[![CI](https://github.com/manelsen/donkey/actions/workflows/ci.yml/badge.svg)](https://github.com/manelsen/donkey/actions/workflows/ci.yml)
[![Sync to Hugging Face Hub](https://github.com/manelsen/donkey/actions/workflows/sync-to-hub.yml/badge.svg)](https://github.com/manelsen/donkey/actions/workflows/sync-to-hub.yml)
[![CodeRabbit Reviews](https://img.shields.io/badge/CodeRabbit-Reviews-ff69b4?logo=coderabbit)](https://coderabbit.ai)
[![Nim 2.2+](https://img.shields.io/badge/Nim-2.2%2B-FFE953?logo=nim)](https://nim-lang.org)
[![Architecture: Hexagonal](https://img.shields.io/badge/Architecture-Hexagonal-blueviolet)](docs/ARCHITECTURE.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **A sovereign, ultra-lightweight autonomous AI agent daemon written in pure Nim.**  
> Built for long-running deployments on a VPS, homelab, laptop, or container with Chronos async I/O, strict hexagonal boundaries, sovereign dual-layer memory, and hardened sandboxing.

---

## ⚡ Why Donkey?

Most AI agent platforms are heavy, complex webs of Python interpreters, gigabyte-sized virtualenvs, and unpredictable Node runtimes. **Donkey takes the opposite path:**

- **Native Binary & Low Footprint**: Compiles to a compact native binary with deterministic ARC/ORC memory management (requires host OpenSSL libraries for HTTPS). Idles in single-digit megabytes of RAM.
- **Strict Hexagonal Architecture**: Business logic, planning, and memory algorithms remain 100% pure and decoupled from I/O through Nim structural typing (`concept`). Adapters can be plugged in or replaced without touching core code.
- **Sovereign Dual-Layer Memory (MAGMA)**: Out-of-the-box SQLite with embedded `sqlite-vec` vector similarity search, alongside human-inspectable Markdown paddocks (`USER.md`, `MEMORY.md`, `HEARTBEAT.md`). Scales seamlessly to PostgreSQL + `pgvector` multigraph when required.
- **Hardened Execution Sandbox**: Untrusted tool execution is safely isolated via an OCI container runtime (Docker/Podman) running under the daemon UID/GID with read-only rootfs, plus in-process WASM applet dispatch for fast, secure file manipulation.
- **Autonomous Heartbeat & Contemplation**: Runs background scheduling loops that inspect checklists in `HEARTBEAT.md`, digest conversation memories into episodic journals, and deliver pro-active reminders across connected channels.
- **Multi-Channel & Multi-Provider**: Direct, first-class connectivity to Telegram, Discord, WeChat, Feishu, DingTalk, Slack, QQ, and Matrix, with resilient failover between Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, Ollama, ZAI, and OpenRouter.

---

## 📐 Architecture

Donkey is engineered according to strict **Hexagonal Architecture (Ports and Adapters)** principles. Dependencies only flow inwards toward pure domain models.

```mermaid
flowchart TD
  subgraph Inbound["Inbound Channels (Adapters)"]
    TG["Telegram (Long Polling)"]
    DC["Discord Gateway"]
    WC["WeChat / WeCom"]
    FS["Feishu / DingTalk / QQ"]
    HTTP["HTTP Gateway / CLI"]
  end

  subgraph InPorts["Inbound Ports"]
    CP["ChannelCapabilityDescriptor\nChannelPort (concept)"]
  end

  subgraph Core["Pure Core & Domain Engine"]
    ORCH["OrchestratorAgent\n(Stateful User Session)"]
    ROUTER["Smart Routing & Failover\n(Quality-First Policy)"]
    HB["Heartbeat Daemon\n& Contemplation Loop"]
    TOOL["Tool Loop Runtime\n& AST Sanitizer"]
  end

  subgraph OutPorts["Outbound Ports"]
    PP["ProviderPort (concept)"]
    MP["MemoryRuntimePort (concept)"]
    SP["SandboxPort (concept)"]
  end

  subgraph Outbound["Outbound Adapters"]
    LLM["LLM Providers\nAnthropic · OpenAI · Gemini\nDeepSeek · MiniMax · Ollama · ZAI"]
    MAGMA["Dual Memory Runtime\nEmbedded SQLite-vec · Markdown\nPostgreSQL Multigraph"]
    SANDBOX["Hardened Sandbox\nOCI Container (Daemon UID/GID) · WASM Busybox"]
  end

  Inbound --> InPorts --> Core --> OutPorts --> Outbound
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the complete architectural specification.

---

## 🚀 Quickstart in 60 Seconds

### Prerequisites

- [Nim 2.2+](https://nim-lang.org/install.html) with Nimble (`choosenim` recommended)
- `ripgrep` (`rg`) for architectural boundary verification
- `docker` or `podman` (required for default OCI shell sandbox)
- `TELEGRAM_BOT_TOKEN` (required to start the daemon) and at least one provider API key (or local Ollama, which requires no key)

### 1. Build the Binary

```bash
# Build development binary (embedded SQLite + sqlite-vec enabled by default)
nimble build

# Or compile optimized, stripped release binary
nim c -d:release --opt:size \
  --passC:"-ffunction-sections -fdata-sections" \
  --passL:"-Wl,--gc-sections" \
  -o:donkey src/donkey.nim
strip donkey
```

### 2. Guided Setup

Run the interactive setup wizard to initialize configuration templates and state directories:

```bash
./donkey setup
```

The wizard configures `~/.config/donkey/donkey.toml`, provisions the state store in `~/.donkey/`, selects the available OCI sandbox runtime, and saves provider keys. Verify provider connectivity with `./donkey ctl provider test <name>`.

### 3. Start the Daemon

> [!IMPORTANT]
> The embedded HTTP gateway listens on `0.0.0.0:8080` by default, exposing `/api/status` and `/api/logs` without authentication. If you do not need the HTTP gateway or deploy without a reverse proxy, disable it before starting by setting `DONKEY_HTTP_PORT=0` in `~/.config/donkey/donkey.env` (or run `DONKEY_HTTP_PORT=0 ./donkey start`).

```bash
./donkey start
```

Run as a systemd background user service:

```bash
./donkey service install
./donkey service start
```

Verify instance health anytime:

```bash
./donkey doctor
```

---

## 🧠 Sovereign Memory: The Paddock System

Every user interacting with Donkey receives an isolated, human-readable directory called a **Paddock** located at `~/.donkey/paddocks/<user-id>/`:

```text
~/.donkey/paddocks/<uuid>/
├── USER.md          # User profile & instructions (MAGMA graph profile takes precedence)
├── PREFERENCES.md   # Model overrides, language, timezone, personality (TOML)
├── HEARTBEAT.md     # Active checklist of background autonomous tasks
├── MEMORY.md        # Episodic reflections & long-term conversational memory
├── CONTACTS.md      # Social graph, relations, and mentions
├── solutions/       # Self-indexed technical solutions & code recipes
├── sessions/        # Session transcripts & turn summaries
└── .secrets/        # User-encrypted API keys & tokens (AES-GCM via nimcrypto)
```

### The MAGMA Subsystem
1. **SQLite-First (Default)**: Embedded SQLite and `sqlite-vec` vector similarity search are compiled directly into the binary. Episodic memories, user preferences, and knowledge nodes live in `~/.donkey/state/magma.sqlite` (vector search requires `OPENROUTER_API_KEY` for embedding generation). Raw conversation transcripts are preserved in JSONL session files under `paddocks/<uuid>/sessions/`.
2. **Markdown Bootstrap & Export**: Markdown paddocks serve as the human-readable view, bootstrap source, and debug format. When MAGMA is active, runtime writes go to the graph and do not automatically update paddock Markdown files; use `./donkey ctl memory export <uuid> [output_dir]` to export the current MAGMA view into Markdown files (overwriting existing files in the target directory, or omit `output_dir` to print to stdout).
3. **PostgreSQL Multigraph Scaling**: For multi-agent graph querying at scale, Donkey supports PostgreSQL + `pgvector`. Compile with `nim c -d:withPostgres -u:withSqlite -o:donkey src/donkey.nim` and configure `DONKEY_PG_DSN`.

---

## 🛡️ Sandboxing & Tool Security

Donkey provides sandboxing for shell execution. MCP servers run directly on the host and inherit the daemon environment, which may contain credentials; install only trusted MCP servers, or isolate them externally.

- **OCI Hardened Sandbox**: Shell executions run inside ephemeral Docker or Podman containers configured with:
  - Host daemon UID and GID matching (prevents host file ownership pollution)
  - Read-only root filesystem (`read_only_rootfs = true`)
  - Network access disabled by default (enabling network in donkey.toml requires --dev-mode)
  - Isolated temporary and paddock mounts
- **WASM Applet Dispatch**: Fast execution of POSIX applets (cat, grep, sed, find) via `wasmtime` and `~/.donkey/busybox`.
- **Model Context Protocol (MCP)**: Native client support for external MCP tool servers:
  ```bash
  # Positional arguments only via CLI
  ./donkey ctl tool install <mcp-server-command> [positional-args...]
  ```
  > [!TIP]
  > Server flags like `--port=8000` are filtered out by the CLI option parser; configure MCP servers requiring flags directly in `~/.donkey/tools.toml`.

---

## 🌐 Supported Ecosystem

### Channels (Inbound)

| Channel | Mode | Features |
|:---|:---|:---|
| **Telegram** | Long Polling | Streaming responses, markdown formatting, reactions, inline keyboards |
| **Discord** | Gateway WebSockets | Slash commands, components, thread handling, bot mentions |
| **WeChat / WeCom**| Webhook / Event loop | Enterprise WeChat & personal bridge support |
| **Feishu / Lark** | Webhook / Event stream | Interactive cards, group chats, direct messages |
| **DingTalk** | Stream / Webhook | Corporate notifications, card callbacks |
| **QQ / OneBot** | WebSocket / HTTP | OneBot v11 protocol, group and private chat dispatch |
| **Slack** | Outbound only | Outbound messaging via Webhooks/API (inbound event loop integration pending) |
| **Matrix** | Webhook / AS push | Inbound via Application Service / HTTP pushEvent callback; outbound PUT event |
| **HTTP Gateway**| REST / SSE | Local webhooks, chat completions endpoint |

### Providers (Outbound)

| Provider | Default Tool Support | Streaming | Recommended Models |
|:---|:---:|:---:|:---|
| **Anthropic** | ✅ | ✅ | `claude-opus-4-6`, `claude-sonnet-4-6` |
| **OpenAI** | ✅ | ✅ | `gpt-4o`, `gpt-4o-mini` |
| **DeepSeek** | ✅ | ✅ | `deepseek-chat`, `deepseek-reasoner` |
| **Gemini** | ✅ | ❌ | `gemini-2.5-pro`, `gemini-2.5-flash` |
| **Ollama** | ✅ | ✅ | `qwen2.5-coder:32b`, `llama3.3:70b` |
| **MiniMax** | ✅ | ❌ | `MiniMax-Text-01`, `MiniMax-M2` |
| **ZAI / Zhipu** | ✅ | ❌ | `glm-4-plus`, `glm-4-flash` |
| **OpenRouter** | ✅ | ✅ | Universal routing fallback |

> Streaming indicates per-session `streamFn` availability in `buildProviderBundle` (`zai-anthropic` also provides streaming).

---

## 🛠️ CLI Reference

The `donkey ctl` utility provides complete instance governance:

```bash
# User and Paddock management
./donkey ctl user list
./donkey ctl user show <uuid>
./donkey ctl memory export <uuid> [output_dir]

# Tool and Extension management
./donkey ctl tool install <mcp-command> [args...]
./donkey ctl skill install <name> <script.ts>

# Provider Diagnostics
./donkey ctl provider test anthropic
./donkey ctl provider test deepseek
```

---

## 🧪 Development & Quality Assurance

Donkey follows disciplined Test-Driven Development (TDD) with strict architectural boundaries.

### Running Tests

```bash
# Run the default test suite in parallel across all CPU cores
bash scripts/run_tests.sh

# Target a specific module or test file
bash scripts/run_tests.sh tests/ports
bash scripts/run_tests.sh tests/app/t_orchestrator.nim

# Execute via Nimble
nimble test
```

> [!NOTE]
> Opt-in backends requiring special flags or active databases (SQLite store requiring `-d:withSqlite`, PostgreSQL/Age) and in-process wasm3 (`t_wasm.nim`) are excluded by default in `scripts/run_tests.sh`. WASM applet and shell composer suites run automatically when `~/.donkey/busybox` and `wasmtime` are present on the host.

### Verifying Architectural Boundaries

Core and Domain modules must never import Adapters. Run the automated boundary checker:

```bash
# Requires ripgrep (rg)
bash scripts/check_boundaries.sh
```

---

## 📄 License

Donkey is open-source software licensed under the [MIT License](LICENSE).
