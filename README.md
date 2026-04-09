# Donkey

AI agent system written in Nim. Self-hosted, multi-channel, multi-provider.
Designed to run on a VPS and scale down to a Raspberry Pi Zero.

## Requirements

- Nim 2.2+ with Nimble (`choosenim` recommended)
- At least one channel token, such as `TELEGRAM_BOT_TOKEN` or `DISCORD_BOT_TOKEN`
- At least one provider API key (see [Configuration](#configuration))
- `docker` or `podman` if you want the recommended hardened shell sandbox

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
| `ZHIPU_API_KEY` | For Zhipu | API key from api.z.ai |
| `OPENROUTER_API_KEY` | For OpenRouter | Fallback provider |
| `ANTHROPIC_API_KEY` | For Anthropic | claude-* models |
| `GEMINI_API_KEY` | For Gemini | gemini-* models |
| `MINIMAX_API_KEY` | For MiniMax | MiniMax-M2 |
| `DONKEY_MAGMA_SQLITE_PATH` | Optional | SQLite file used by the default MAGMA backend |
| `DONKEY_SQLITE_VEC_PATH` | Optional | Override path for a non-embedded `sqlite-vec` deployment |
| `DONKEY_PG_DSN` | For Multigraph Memory | PostgreSQL DSN used by the graph-backed memory runtime |
| `DONKEY_MASTER_KEY` | If using secrets | Master key for encrypted secrets |
| `DONKEY_HTTP_PORT` | Optional | HTTP gateway port. Set to `0` to disable it |

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

### Happy path

```bash
nimble build
./donkey setup
./donkey start
```

`setup` now writes both files into `~/.config/donkey/`, creates the local
state directories under `~/.donkey/`, auto-picks an OCI runtime when one is
available, and prints the exact `doctor`/`start` commands at the end.

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
