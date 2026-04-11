# Donkey

AI agent system written in Nim. Self-hosted, multi-channel, multi-provider.
Designed to run on a VPS, a laptop, or a small Linux box with a SQLite-first local runtime.

## Requirements

- Nim 2.2+ with Nimble (`choosenim` recommended)
- At least one channel token, such as `TELEGRAM_BOT_TOKEN` or `DISCORD_BOT_TOKEN`
- At least one provider API key (see [Configuration](#configuration))
- `docker` or `podman` if you want the recommended hardened shell sandbox

## Build

```bash
# Development build (SQLite-first, fast path enabled by default)
nimble build

# Release build
nim c -d:release --opt:size \
  --passC:"-ffunction-sections -fdata-sections" \
  --passL:"-Wl,--gc-sections" \
  -o:donkey_release src/donkey.nim
strip donkey_release

# Run tests
nimble test
```

To build without SQLite support:

```bash
nimble build -u:withSqlite
```

## Configuration

The recommended explicit config path is `~/.config/donkey/donkey.toml`.
Keep tokens and keys in `~/.config/donkey/donkey.env`.

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

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | For Telegram | Telegram bot token |
| `DISCORD_BOT_TOKEN` | For Discord | Discord bot token |
| `ZAI_API_KEY` | Optional | ZAI generic provider |
| `ZAI_CODING_API_KEY` | Optional | Default tool-heavy provider path |
| `ZAI_ANTHROPIC_API_KEY` | Optional | Anthropic-compatible ZAI provider |
| `OPENROUTER_API_KEY` | For OpenRouter | Fallback provider |
| `OPENAI_API_KEY` | Optional | OpenAI provider |
| `DEEPSEEK_API_KEY` | Optional | DeepSeek provider |
| `ANTHROPIC_API_KEY` | For Anthropic | claude-* models |
| `GEMINI_API_KEY` | For Gemini | gemini-* models |
| `MINIMAX_API_KEY` | For MiniMax | MiniMax-M2 |
| `BRAVE_API_KEY` | Optional | Enables the `web_search` tool via Brave Search API |
| `DONKEY_MAGMA_SQLITE_PATH` | Optional | SQLite file used by the default MAGMA backend |
| `DONKEY_SQLITE_VEC_PATH` | Optional | Override path for a non-embedded `sqlite-vec` deployment |
| `DONKEY_PG_DSN` | For Multigraph Memory | PostgreSQL DSN used by the graph-backed memory runtime |
| `DONKEY_MASTER_KEY` | If using secrets | Master key for encrypted secrets |
| `DONKEY_HTTP_PORT` | Optional | HTTP gateway port. Set to `0` to disable it |

### SQLite-first default

The normal build is SQLite-first. It uses `~/.donkey/state/magma.sqlite`
automatically unless you override it. In this mode the build is self-contained:
SQLite base and `sqlite-vec` are compiled into the Donkey binary.

```bash
export DONKEY_MAGMA_SQLITE_PATH="$HOME/.donkey/state/magma.sqlite"
# Optional: enable sqlite-vec fast path
export DONKEY_SQLITE_VEC_PATH=/absolute/path/to/vec0
nim c -d:withSqlite src/donkey.nim
```

`DONKEY_SQLITE_VEC_PATH` is now mostly a fallback/override for non-embedded
deployments. In the normal `withSqlite` build, no system `libsqlite3` or
external vector extension is required at runtime.

### PostgreSQL for larger installs

If `DONKEY_PG_DSN` is set, Donkey can use PostgreSQL-backed MAGMA instead.
Keep this off unless you explicitly want the PostgreSQL runtime.

```bash
export DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'
```

### Per-user provider selection

Each user can override the provider in their `PREFERENCES.md`:

```toml
provider = "anthropic"
model    = "claude-haiku-4-5"
```

### Happy path

```bash
nimble build
./donkey setup
./donkey start
```

`setup` writes both files into `~/.config/donkey/`, creates the local
state directories under `~/.donkey/`, auto-picks an OCI runtime when one is
available, offers optional Brave Search setup for `web_search`, asks for the
instance-wide default provider/model, and prints the exact `doctor`/`start`
commands at the end.

If you prefer to edit templates manually, the example files live at:

- [deploy/donkey.toml.example](/home/micelio/git/donkey/deploy/donkey.toml.example)
- [deploy/donkey.env.example](/home/micelio/git/donkey/deploy/donkey.env.example)

If you do not want the HTTP gateway:

```bash
DONKEY_HTTP_PORT=0 ./donkey start
```

To run as a user service:

```bash
./donkey service install
./donkey service start
```

## Running

```bash
# Start daemon
export TELEGRAM_BOT_TOKEN=...
export ZAI_CODING_API_KEY=...
./donkey start

# Admin commands
./donkey ctl user list
./donkey ctl user show <uuid>
./donkey ctl tool install <mcp-server-command> [args...]
./donkey ctl skill install <deno-script.ts> [--allow-net ...]
./donkey ctl provider test zhipu
```

## User workspace

Each user gets a paddock at `~/.donkey/paddocks/<uuid>/`:

```
<uuid>/
  USER.md          # profile — editable directly, reread each conversation
  PREFERENCES.md   # provider, language, timezone (TOML)
  MEMORY.md        # episodic notes accumulated over sessions
  CONTACTS.md      # known people and relations
  SOLUTIONS.md     # indexed technical solutions
  sessions/        # per-session summaries
  .secrets/        # encrypted API keys (nimcrypto)
```

When neither `DONKEY_MAGMA_SQLITE_PATH` nor `DONKEY_PG_DSN` is configured,
these files are the live memory backend.

When `DONKEY_MAGMA_SQLITE_PATH` or `DONKEY_PG_DSN` is configured,
`Multigraph Memory` becomes the authoritative runtime store for profile,
preferences, and episodic memory. In that mode:

- conversations load context from the graph first
- runtime writes go to the graph, not to `USER.md`, `PREFERENCES.md`, or `MEMORY.md`
- Markdown remains useful for bootstrap, export, inspection, and debug
- `./donkey ctl memory export <uuid>` regenerates the Markdown view from the graph

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full technical overview.

Brief summary: hexagonal architecture, ports as Nim `concept` (structural typing),
Chronos for async I/O, one `OrchestratorAgent` per user session, and outbound
presentation treated as a shared core concern instead of adapter-local state.

## Current Runtime

- SQLite-first local runtime by default
- Embedded SQLite + `sqlite-vec` in the normal build
- Hardened OCI shell sandbox for production
- `doctor`, `setup`, `service install`, and `service start` as the primary ops path
- Multi-channel UI with shared outbound presentation surfaces, streaming, and reactions

## Development

```bash
# Run a single test file
testament r tests/app/t_orchestrator.nim

# Run a category
testament cat app
```

### Extending Donkey

- **Add a channel**: See [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-new-channel) for the step-by-step guide using `ChannelCapabilityDescriptor`.
- **Add a provider**: See [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-new-provider) for registering models via `ProviderCatalog` and implementing the adapter.
- **Add an MCP tool**: `donkey ctl tool install <command>`

See [CLAUDE.md](CLAUDE.md) for AI-assistant guidance and architectural decisions.
See [TODO.md](TODO.md) for the centralized backlog, including the Multigraph Memory-first migration plan.
