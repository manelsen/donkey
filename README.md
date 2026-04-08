# Donkey

AI agent system written in Nim. Self-hosted, multi-channel, multi-provider.
Designed to run on a VPS and scale down to a Raspberry Pi Zero.

## Requirements

- Nim 2.2+ with Nimble (`choosenim` recommended)
- A Telegram bot token (`TELEGRAM_BOT_TOKEN`)
- At least one provider API key (see [Configuration](#configuration))

## Build

```bash
# Development build (fast, Multigraph Memory enabled by default)
nimble build

# Release build (stripped, ~550KB)
nim c -d:release --opt:size \
  --passC:"-ffunction-sections -fdata-sections" \
  --passL:"-Wl,--gc-sections" \
  -o:donkey_release src/donkey.nim
strip donkey_release

# Run tests
nimble test
```

To build a Markdown-only binary without PostgreSQL support:

```bash
nimble build -u:withPostgres
```

## Configuration

Donkey reads `~/.donkey/donkey.toml` by default. Override with `--config <path>`.

```toml
# donkey.toml
home     = "~/.donkey"          # base directory
paddocks = "~/.donkey/paddocks" # user workspaces
logLevel = "info"
```

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Telegram bot token |
| `ZHIPU_API_KEY` | For Zhipu | API key from api.z.ai |
| `OPENROUTER_API_KEY` | For OpenRouter | Fallback provider |
| `ANTHROPIC_API_KEY` | For Anthropic | claude-* models |
| `GEMINI_API_KEY` | For Gemini | gemini-* models |
| `MINIMAX_API_KEY` | For MiniMax | MiniMax-M2 |
| `DONKEY_MAGMA_SQLITE_PATH` | Optional | SQLite file used by the default MAGMA backend |
| `DONKEY_SQLITE_VEC_PATH` | Optional | Path to the `sqlite-vec` extension binary for SQLite vector search |
| `DONKEY_PG_DSN` | For Multigraph Memory | PostgreSQL DSN used by the graph-backed memory runtime |
| `DONKEY_MASTER_KEY` | If using secrets | Master key for encrypted secrets |

### SQLite default

SQLite-backed MAGMA is now the default local path. If Donkey is built with
`-d:withSqlite`, it will use `~/.donkey/state/magma.sqlite` automatically unless
you override it. In this mode the build is self-contained: SQLite base and
`sqlite-vec` are compiled into the Donkey binary.

```bash
export DONKEY_MAGMA_SQLITE_PATH="$HOME/.donkey/state/magma.sqlite"
# Optional: enable sqlite-vec fast path
export DONKEY_SQLITE_VEC_PATH=/absolute/path/to/vec0
nim c -d:withSqlite src/donkey.nim
```

`DONKEY_SQLITE_VEC_PATH` is now mostly a fallback/override for non-embedded
deployments. In the normal `withSqlite` build, no system `libsqlite3` or
external vector extension is required at runtime.

### PostgreSQL via Docker

The recommended path for `Multigraph Memory` is to run PostgreSQL + `pgvector`
in Docker instead of installing PostgreSQL on the host.

```bash
# Start only the database service
docker compose up -d postgres

# Donkey running on the host
export DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'

# Build with Multigraph Memory enabled (default)
nim c src/donkey.nim
```

If Donkey itself is running inside the same compose network, keep using:

```bash
export DONKEY_PG_DSN='host=postgres user=postgres password=donkey_pass dbname=donkey port=5432'
```

The bundled compose file persists database state in the named volume
`donkey_pgdata`.

If `5432` is already occupied on the host, override the published port:

```bash
export DONKEY_PG_PORT=5433
docker compose up -d postgres
export DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5433'
```

### Per-user provider selection

Each user can override the provider in their `PREFERENCES.md`:

```toml
provider = "anthropic"
model    = "claude-haiku-4-5"
```

## Running

```bash
# Start daemon (Telegram long-polling)
export TELEGRAM_BOT_TOKEN=...
export ZHIPU_API_KEY=...
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
Chronos for async I/O, one `OrchestratorAgent` per user session.

## Development

```bash
# Run a single test file
testament r tests/app/t_orchestrator.nim

# Run a category
testament cat app

# Add a provider: implement ProviderPort, add to buildCompleteFn in src/donkey.nim
# Add a channel:  implement ChannelPort, add to startDaemon in src/donkey.nim
# Add an MCP tool: donkey ctl tool install <command>
```

See [CLAUDE.md](CLAUDE.md) for AI-assistant guidance and architectural decisions.
See [TODO.md](TODO.md) for the centralized backlog, including the Multigraph Memory-first migration plan.
