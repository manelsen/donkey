# Donkey

AI agent system written in Nim. Self-hosted, multi-channel, multi-provider.
Designed to run on a VPS and scale down to a Raspberry Pi Zero.

## Requirements

- Nim 2.2+ with Nimble (`choosenim` recommended)
- A Telegram bot token (`TELEGRAM_BOT_TOKEN`)
- At least one provider API key (see [Configuration](#configuration))

## Build

```bash
# Development build (fast, with -d:testing)
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
| `DONKEY_PG_DSN` | For Multigraph Memory | PostgreSQL DSN used by the graph-backed memory runtime |
| `DONKEY_MASTER_KEY` | If using secrets | Master key for encrypted secrets |

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

When `DONKEY_PG_DSN` is not configured, these files are the live memory backend.

When `DONKEY_PG_DSN` is configured and Donkey is compiled with `-d:withPostgres`,
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
