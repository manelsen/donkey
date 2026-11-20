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
- **Hardened Execution Sandbox**: Shell execution can be isolated via an OCI container runtime (Docker/Podman) running under the daemon UID/GID with read-only rootfs, plus fast POSIX file manipulation via `wasmtime` subprocess applet dispatch (requires host subprocess execution support).
- **Autonomous Heartbeat & Contemplation**: Runs background scheduling loops that inspect checklists in `HEARTBEAT.md`, digest conversation memories into episodic journals, and deliver pro-active reminders across connected channels.
- **Multi-Channel & Multi-Provider**: Direct, first-class connectivity to Telegram, Discord, WeChat, Feishu, DingTalk, Slack, QQ, and Matrix, with active session routing for Anthropic, Gemini, MiniMax, ZAI, and OpenRouter (sessions selecting OpenAI, DeepSeek, or Ollama are currently mapped to ZAI coding by `buildProviderSpec`). Smart routing can try eligible providers on failure. For users without provider preferences, the setup wizard selects a fixed provider; OpenRouter is a fallback only when its key is configured.

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
    LLM["LLM Providers\nAnthropic · OpenAI · Gemini · DeepSeek\nMiniMax · Ollama · ZAI · OpenCode · Groq"]
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
- `TELEGRAM_BOT_TOKEN` (required to start the daemon) and at least one directly supported session provider key: Anthropic, OpenAI, DeepSeek, Gemini, MiniMax, ZAI, Groq, OpenCode (Go / Zen), OpenRouter, or a local Ollama instance

### 1. Build the Binary

> On a small server you can skip the build: CI publishes the optimized x86_64 Linux binary of `master` (built against glibc 2.28) as the `nightly` pre-release. `bash deploy/update.sh` downloads it, verifies the checksum, keeps the previous binary beside it as `donkey.prev`, installs it and restarts the user service; `bash deploy/update.sh --rollback` puts the previous one back. The binary goes where the installed service runs it from (its `ExecStart`), so a service created with `./donkey service install` in a checkout is updated in place; with no service installed it goes to `~/.local/bin/donkey`, and the `./donkey ...` commands below become `~/.local/bin/donkey ...`. Set `BINARY_DST=/path/to/donkey` to choose another location.

```bash
# Build development binary (embedded SQLite + sqlite-vec enabled by default)
nimble build

# Or compile optimized, stripped release binary (install dependencies first)
nimble install -y -d
# Linux (GNU linker with --gc-sections; on macOS, use -Wl,-dead_strip instead):
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

For a systemd user service with the native Lightpanda browser, run `bash deploy/install.sh --lightpanda --binary ./donkey` with a binary built from this checkout. For a Nightly that includes Lightpanda support, pass the binary path installed by `deploy/update.sh`. The installer verifies the upstream Lightpanda binary, installs it in `~/.local/bin`, and writes `DONKEY_BROWSER_BACKEND` and `DONKEY_BROWSER_PATH` to the service's `donkey.env`. The x86_64 Lightpanda binary requires glibc 2.35 or newer.

Lightpanda needs outbound DNS and HTTPS on the service host. Have the host firewall block browser traffic to private and reserved destinations. The `DONKEY_BROWSER_PROXY` setting is supported by Chromium and Edge.

### 3. Start the Daemon

> [!IMPORTANT]
> The embedded HTTP gateway listens on `127.0.0.1:8080` by default (containers and Hugging Face Spaces set `DONKEY_HTTP_BIND=0.0.0.0`), exposing `/api/status`, `/api/logs`, `/api/events`, and `/api/chat` without authentication (`/api/chat` accepts inbound messages with an optional `userId` and can create or dispatch to sessions if the user is not revoked, while `/api/events` streams live logs). Block direct external access to port 8080 with a firewall on any deployment where this port is accessible, and enforce authentication at the proxy layer if using a reverse proxy. On shared multi-user hosts, unprivileged local users can also connect directly to port 8080 and bypass proxy authentication; isolate network access strictly to the proxy process (e.g., via network namespaces) or disable the gateway entirely. Any `DONKEY_HTTP_PORT` variable already exported in the shell environment takes precedence over `.env` files; to reliably disable the gateway, run `DONKEY_HTTP_PORT=0 ./donkey start` or set `DONKEY_HTTP_PORT=0` in the environment file loaded by the daemon. Note that the daemon resolves `donkey.env` before loading `donkey.toml` by checking `$DONKEY_HOME/donkey.env` (defaulting to `~/.donkey/donkey.env`) and falling back to `~/.config/donkey/donkey.env`; placing `DONKEY_HTTP_PORT=0` only in a custom `home` path configured inside TOML will not take effect. Preserve existing credentials in the loaded file and unset any inherited shell variable (`unset DONKEY_HTTP_PORT`) before starting. For systemd, set it in the service's effective `EnvironmentFile` such as `~/.config/donkey/donkey.env` and restart.
>
> Even on a single-user host, a malicious web page can read `/api/logs` or inject messages into `/api/chat` (including via simple `text/plain` requests without CORS preflight, creating or invoking sessions for arbitrary non-revoked users) if the browser permits local network access. Isolate the gateway from the browser (e.g., via network namespaces) or disable it; blocking external firewall access alone is not sufficient.

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
├── PREFERENCES.md   # Model overrides, language, timezone (graph preferences take precedence; update via /models <provider> <model>)
├── HEARTBEAT.md     # Active checklist of background autonomous tasks
├── MEMORY.md        # Episodic reflections & long-term conversational memory
├── CONTACTS.md      # Social graph, relations, and mentions
├── solutions/       # Self-indexed technical solutions & code recipes
├── attachments/     # Inbound Telegram/Discord files, 0700/0600
├── sessions/        # Session transcripts & turn summaries
└── .secrets/        # User-encrypted API keys & tokens (AES-GCM via nimcrypto)
```

### The MAGMA Subsystem
1. **SQLite-First (Default)**: Embedded SQLite and `sqlite-vec` vector similarity search are compiled directly into the binary. Episodic memories, user preferences, and knowledge nodes live in `~/.donkey/state/magma.sqlite`. Profile texts, preferences, and memories are transmitted to OpenRouter to generate embeddings during writes and queries when embedding generation is active (e.g. via `OPENROUTER_API_KEY`); CLI operations like `ctl memory search` and `ctl memory import` may also transmit queries and non-empty context externally. Other configured services, such as Z.AI or external rerankers, may also transmit queries and candidate memory texts. Raw conversation transcripts are preserved in JSONL session files under `paddocks/<uuid>/sessions/`.
2. **Markdown Bootstrap & Export**: Markdown paddocks serve as the human-readable view, bootstrap source, and debug format. When MAGMA is active, runtime writes prioritize the graph. If opening or migrating the database raises an exception, `newMagmaAdapter` returns `nil`, and runtime profile or preference writes can fail when accessing the adapter before the `MdFileAdapter` Markdown fallback takes place. If a write propagates a catchable error, `MdFileAdapter` attempts to record the update in the paddock Markdown files. Some SQLite write errors are swallowed, so updates can be lost without a Markdown fallback. `loadContext` will prioritize graph content once MAGMA recovers. Before running `./donkey ctl memory export <uuid> [output_dir]`, back up and reconcile any paddock Markdown files that diverged during outages, as exporting will overwrite the target directory with the current MAGMA view (or omit `output_dir` to print to stdout). Note that `./donkey ctl memory import <uuid>` reads context before calling `deleteUser`; non-empty graph fields take precedence over divergent edits in Markdown files (only empty graph fields are populated from Markdown), and unexported nodes or relation edges (episodes, solutions) are permanently purged without recovering divergent file edits. Always take a full database backup before importing.
3. **PostgreSQL Multigraph Scaling**: For multi-agent graph querying at scale, Donkey supports PostgreSQL + `pgvector`. Ensure the `pgvector` extension is installed on your PostgreSQL server and that the database user configured in `DONKEY_PG_DSN` has permissions to execute `CREATE EXTENSION IF NOT EXISTS vector`. Install the `libpq` client development library on the build host first (for example, `libpq-dev` on Debian/Ubuntu). Compile with `nim c -d:withPostgres -u:withSqlite -o:donkey src/donkey.nim` and configure `DONKEY_PG_DSN`. Recompiling does not automatically transfer existing data from SQLite; operators must back up their database and migrate existing nodes and edges before switching backends (`./donkey ctl memory export <uuid>` exports only the three context Markdown files for an individual user, not the complete knowledge graph).

### Attachments and Memory Ingestion

Inbound files are downloaded into `{paddock}/attachments/` and referenced by relative path in the user turn. Documents are read with `fs_read`/`text_read`; images use `inspect_image`. Channel file IDs are never forwarded to providers as image URLs.

The `memory_ingest` tool reads a workspace text file (or inline `text`) and appends it to memory in bounded chunks, so a large export does not need to fit in one model response. It appends memory; it does not overwrite `USER.md`. Paddocks, sessions, attachments, and known memory files are created with `0700`/`0600` on POSIX.

---

## 🛡️ Sandboxing & Tool Security

Donkey provides sandboxing for shell execution. MCP servers run directly on the host and inherit the daemon environment, which may contain credentials; install only trusted MCP servers, or isolate them externally. With `--dev-mode`, the default sandbox mode runs shell commands directly on the host. If `sandbox.allow_host_fallback = true` (allowed only in `--dev-mode`), certain OCI failures can also execute commands on the host; do not rely on container isolation in those configurations.

- **OCI Hardened Sandbox**: Shell executions normally run inside ephemeral Docker or Podman containers configured with:
  - Host daemon UID and GID matching (prevents host file ownership pollution)
  - Read-only root filesystem (`read_only_rootfs = true`)
  - Network access disabled by default (enabling network in donkey.toml requires --dev-mode)
  - Isolated temporary and paddock mounts

`donkey doctor` checks the OCI runtime, the Docker/Podman socket and its permissions. If it reports `socket access denied`, add the service user to the `docker` group and restart the user service (or reboot): `sudo usermod -aG docker $USER`.
- **WASM Applet Dispatch**: Fast execution of POSIX applets (cat, grep, sed, find) via `wasmtime` and `~/.donkey/busybox`.
- **Webhook TLS**: set both `DONKEY_WEBHOOK_TLS_CERT` and `DONKEY_WEBHOOK_TLS_KEY` (PEM paths) to serve `https://` directly from the webhook receiver. The certificate and key are reloaded when their files change; otherwise terminate TLS at a reverse proxy.
- **Web Egress (SSRF)**: `fetch`/`http_fetch` validate every redirect hop against the private/reserved address policy and resolve DNS through the adapter. **Deployment requirement:** unless the host firewall already blocks private/reserved destinations, set `DONKEY_WEB_PROXY` to a filtering egress proxy. Connection pinning against DNS rebinding requires that proxy or the firewall (the browser uses `DONKEY_BROWSER_PROXY`).
- **Encrypted secret vault**: store API keys and tokens as AES-256-GCM ciphertext in `{home}/.secrets/secrets.json` (`0600`); the key lives outside that directory at `{home}/.secret_key` (`0600`):
  ```bash
  ./donkey ctl secret set OPENROUTER_API_KEY        # reads one line from stdin, no echo
  printf '%s' "$BRAVE_API_KEY" | ./donkey ctl secret set BRAVE_API_KEY
  ./donkey ctl secret list                          # names only, never values
  ./donkey ctl secret import-env                    # encrypt current donkey.env
  ./donkey ctl secret remove BRAVE_API_KEY
  ```
  Never pass the secret as a command-line argument: it would be visible to `ps` and shell history. At daemon startup the vault decrypts entries into the environment only for variables that are not already set. After `import-env`, remove the imported lines from `donkey.env` (plaintext precedence) and restart. Back up `{home}/.secret_key` separately from `.secrets/`: copying `.secrets/` alone does not expose the values, but losing the key makes them unrecoverable. A full-home backup includes both files and must be protected as a secret. The vault protects data at rest, not against a process running as the same Unix user.
- **Model Context Protocol (MCP)**: Native client support for external MCP tool servers:
  ```bash
  # Positional arguments only via CLI
  ./donkey ctl tool install <mcp-server-command> [positional-args...]
  ```
  > [!TIP]
  > Server flags like `--port=8000` are filtered out by the CLI option parser; configure MCP servers requiring flags directly in `tools.toml` under your configured home directory (`cfg.home/tools.toml`, which defaults to `~/.donkey/tools.toml`).

---

## 🌐 Supported Ecosystem

### Channels (Inbound)

| Channel | Mode | Features |
|:---|:---|:---|
| **Telegram** | Long Polling | Streaming responses, markdown formatting, reactions, inline keyboards |
| **Discord** | Gateway WebSockets | Slash commands, components, thread handling, bot mentions |
| **WeChat / WeCom**| Webhook / Event loop | Enterprise WeChat & personal bridge support |
| **Feishu / Lark** | Webhook + API | Events API at `/webhook/feishu`, verification token + optional `FEISHU_ENCRYPT_KEY` (AES-256-CBC), DM gate; interactive cards not supported |
| **DingTalk** | Outbound API | Inbound requires an integration that calls `pushEvent` |
| **QQ / OneBot** | WebSocket / HTTP | OneBot v11 protocol, group and private chat dispatch |
| **Slack** | Webhook / Socket Mode | Events API, Slash Commands and Interactivity at `/webhook/slack`, or Socket Mode; requires `SLACK_BOT_TOKEN` plus `SLACK_APP_TOKEN` for Socket Mode or `SLACK_SIGNING_SECRET` for webhook mode |
| **Matrix** | Outbound PUT | Inbound requires an integration that calls `pushEvent` |
| **HTTP Gateway**| REST / SSE | Local webhooks; note: open `/api/events` streams occupy the single accept thread (blocking concurrent `/api/chat` or status calls for up to 5h until disconnected) |

> **Slack inbound setup:** for Socket Mode, enable **Socket Mode** in the Slack app, create an app-level token with the `connections:write` scope, and set `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` (xapp-...). No public URL is needed. Alternatively set `SLACK_BOT_TOKEN` + `SLACK_SIGNING_SECRET` and `DONKEY_WEBHOOK_PORT`, then point Event Subscriptions, Slash Commands and Interactivity to the same `https://<public-host>/webhook/slack` URL. In webhook mode the receiver listens on `DONKEY_WEBHOOK_HOST:DONKEY_WEBHOOK_PORT` (default `127.0.0.1`). By default it speaks HTTP, so expose it through an HTTPS reverse proxy; alternatively set `DONKEY_WEBHOOK_TLS_CERT` and `DONKEY_WEBHOOK_TLS_KEY` to terminate TLS in the receiver (certificate files are reloaded when they change). Slack does not call a loopback HTTP endpoint directly.

> **Feishu inbound setup:** set `FEISHU_APP_ID`, `FEISHU_VERIFICATION_TOKEN` and `DONKEY_WEBHOOK_PORT` (the receiver is disabled while the port is unset); optionally set `FEISHU_ENCRYPT_KEY` for AES-256-CBC payload encryption. Point Event Subscriptions to `https://<public-host>/webhook/feishu` and forward it through an HTTPS reverse proxy to `DONKEY_WEBHOOK_HOST:DONKEY_WEBHOOK_PORT` (default host `127.0.0.1`), or set `DONKEY_WEBHOOK_TLS_CERT`/`DONKEY_WEBHOOK_TLS_KEY` to serve TLS directly.

### DM pairing

Set `dm_policy = "pairing"` under `[security]` (or `DONKEY_DM_POLICY=pairing`) to require operator approval for new DM senders:

1. The unknown user sends `/pair`; the daemon stores a pending request with a 6-digit code.
2. The operator lists requests with `./donkey ctl pair list`.
3. The operator approves with `./donkey ctl pair approve <code>` (or rejects with `./donkey ctl pair reject <code>`).

Approval mints the identity UUID and writes it to `state/dm_allowlist.txt`; the user's next message is accepted. Requests expire after 10 minutes and are rate-limited to one request per identity per minute.

### Tool approvals

Risky native tools pause and ask the requesting user before executing. The default list is `bash`, `edit_file`, `rm`, `mv` and `cp`; read-only tools run directly.

- `DONKEY_APPROVAL_TOOLS=bash,edit_file` changes the list; `*` covers every native/MCP/skill tool and `none` disables the gate.
- `DONKEY_APPROVAL_LARGE_WRITES=summary` lets large `fs_write`/`text_replace` actions show a `path`/bytes/sha1/preview summary instead of forcing the model to split the file. The default is `reject`; `bash`, `execute_code`, and `edit_file` remain full-display-only.
- `DONKEY_SUPPRESS_TOOL_PROGRESS=1` hides the per-tool `🔧 tool [n]` messages; final answers and approval prompts are still sent.
- `DONKEY_APPROVAL_TIMEOUT_SEC` controls the wait (default 300s); timeout means deny.
- The request appears in the chat with `/approve <id>` and `/deny <id>`; Telegram, Discord and Slack also render inline **Aprovar/Negar** buttons.
- The operator can use `./donkey ctl approval list [user]`, `./donkey ctl approval approve <id>` or `./donkey ctl approval deny <id>`.
- Requests are stored in `state/approvals.json`; terminal decisions are kept for one hour and pending requests expire without granting access.

### Providers (Outbound)

| Provider | Default Tool Support | Streaming | Recommended Models |
|:---|:---:|:---:|:---|
| **Anthropic** | ✅ | ✅ | `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-fable-5-2` |
| **OpenAI** | ✅ | ✅ | `gpt-6-astra`, `gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-luna` |
| **DeepSeek** | ✅ | ✅ | `deepseek-v4-pro`, `deepseek-4.1-flash` |
| **OpenCode Go** | ✅ | ✅ | `deepseek-4.1-flash`, `deepseek-v4-pro`, `claude-sonnet-5-5`, `kimi-k3.1-pro` |
| **OpenCode Zen** | ✅ | ✅ | `deepseek-4.1-flash`, `deepseek-v4-pro`, `gpt-6.1-sol`, `claude-opus-5-5` |
| **Groq** | ✅ | ✅ | `llama-3.3-70b-versatile`, `llama-3.1-8b-instant` |
| **Gemini** | ✅ | ❌ | `gemini-4-argon`, `gemini-3.1-pro`, `gemini-3.8-flash` |
| **Ollama** | ✅ | ✅ | `llama4:scout`, `llama3.3:70b`, `qwen2.5-coder:32b` |
| **MiniMax** | ✅ | ❌ | `MiniMax-Text-01`, `MiniMax-M2` |
| **ZAI / Zhipu** | ✅ | ❌ | `glm-5.1`, `glm-5`, `glm-4.7` |
| **OpenRouter** | ✅ | ✅ | Universal routing fallback |

> [!NOTE]
> In the daemon runtime, sessions receive the global OpenRouter `streamFn` when `OPENROUTER_API_KEY` is configured. Streaming happens only on the first tool-loop round and is subject to the tool gate: with no tools registered it streams whenever `streamFn` exists; with tools registered it streams only when the provider supports streaming tool calls (OpenRouter) and tool progress is not suppressed — `DONKEY_SUPPRESS_TOOL_PROGRESS=1` closes that gate even for a text-only reply. Adapter-level streaming flags in the table indicate `buildProviderBundle` support (`zai-anthropic` also provides streaming).

---

## 🛠️ CLI Reference

The `donkey ctl` utility provides complete instance governance:

```bash
# User and Paddock management
./donkey ctl user list
./donkey ctl user show <uuid>
./donkey ctl memory ingest <uuid> <path-inside-paddock>
./donkey ctl memory export <uuid> [output_dir]

# Tool and Extension management
./donkey ctl tool install <mcp-command> [args...]
./donkey ctl skill install <name> <script.ts>

# Provider Diagnostics
./donkey ctl provider test anthropic
./donkey ctl provider test gemini
```

---

## 🧪 Development & Quality Assurance

Donkey follows disciplined Test-Driven Development (TDD) with strict architectural boundaries.

### Running Tests

```bash
# Run the default test suite (grouped compilation, one process per file)
bash scripts/run_tests.sh

# Fall back to one compiler invocation per file
TEST_RUNNER=legacy bash scripts/run_tests.sh

# Target a specific module or test file
bash scripts/run_tests.sh tests/ports
bash scripts/run_tests.sh tests/app/t_orchestrator.nim

# Execute via Nimble
nimble test
```

`tests/test_groups.tsv` maps each grouped test file to a group. Files that
cannot share a binary (profile-gated backends, stress, executable-location
dependencies) stay in the per-file fallback and are documented in
`tests/test_group_exceptions.tsv`.

To compare two runs case by case, point the runner at empty report directories
and use the comparator:

```bash
TEST_REPORT_DIR=/tmp/tests-before bash scripts/run_tests.sh tests/core
TEST_REPORT_DIR=/tmp/tests-after  bash scripts/run_tests.sh tests/core
python3 scripts/compare_test_reports.py /tmp/tests-before /tmp/tests-after
```

> [!NOTE]
> `scripts/run_tests.sh` always skips `t_sqlite_store`, even when targeted directly (`withSqlite` is enabled by default in `config.nims`). Run this suite directly:
>
> ```bash
> nim c --hints:off --mm:orc -u:withPostgres -r tests/adapters/memory/t_sqlite_store.nim
> ```
>
> PostgreSQL/Age tests and in-process wasm3 (`t_wasm.nim`) are excluded by default in `scripts/run_tests.sh`. WASM applet and shell composer suites run automatically when `~/.donkey/busybox` and `wasmtime` are present on the host.

### Test runner performance

Measured with Nim 2.2.12, `JOBS=4`, the same checkout and the same test
fixtures. Cold runs used separate empty `XDG_CACHE_HOME` trees; warm runs
reused them.

| Mode | Cold | Warm | Compilations (cold) |
|---|---:|---:|---:|
| `TEST_RUNNER=legacy` | 730.76 s | 92.04 s | 294 |
| `grouped` (4 groups, default) | 233.31 s | 48.68 s | 20 |

The original target was **3×** in both scenarios. The default grouped mode
reaches **3.13× cold** and **1.89× warm**. The warm ceiling is the remaining
test runtime after the orchestrator debounce fixture, not scheduling; this
delivery accepts a 4-minute cold and 1-minute warm ceiling.

The gcov audit compiled both modes with
`--lineDir:on --passC:--coverage --passL:--coverage`. It recorded zero gcov
errors. The 447 line and 344 branch differences are instrumentation
attribution changes (inlining and dead-code elimination between translation
units), not lost tests: both modes run the same 5,528 cases, and
function-level counts confirm that the affected functions execute in grouped
mode.

### Verifying Architectural Boundaries

Core and Domain modules must never import Adapters. Run the automated boundary checker:

```bash
# Requires ripgrep (rg)
bash scripts/check_boundaries.sh
```

---

## 📄 License

Donkey is open-source software licensed under the [MIT License](LICENSE).
