# Installation
How to install and configure Donkey with the current SQLite-first runtime.

## Requirements

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Nim | 2.2 | 2.2+ |
| RAM | 512 MB | 1 GB |
| Disk | 1 GB | 5 GB |
| OS | Linux/macOS/Windows | Linux |

### Runtime Dependencies

| Dependency | Purpose | Install |
|------------|---------|---------|
| OCI runtime | Hardened shell sandbox | `docker` or `podman` |
| PostgreSQL | Optional graph-backed MAGMA runtime | `libpq-dev` |

In the normal SQLite-first build, SQLite base and `sqlite-vec` are embedded in
the Donkey binary. You do not need `libsqlite3-dev` or a separate vector
extension for the happy path.

## Installation Methods

### Method 1: Build from Source

```bash
git clone https://github.com/manelsen/donkey.git
cd donkey

# Standard build (SQLite-first)
nimble build

# Optional PostgreSQL-capable build
nimble build -d:withPostgres

# Production build
nim c -d:release --mm:orc --warningAsError:on src/donkey.nim
```

### Method 2: Nimble

```bash
nimble install donkey
```

### Method 3: Pre-built Binary

Download a release artifact from GitHub and place the binary somewhere in your
`PATH`.

## Directory Layout

```text
~/.config/donkey/
├── donkey.toml
└── donkey.env

~/.donkey/
├── paddocks/
├── state/
└── donkey.log
```

## Configuration

The most ergonomic path is:

```bash
./donkey setup
```

That command now:

- writes `~/.config/donkey/donkey.toml`
- writes `~/.config/donkey/donkey.env`
- creates local state directories under `~/.donkey/`
- auto-selects a usable OCI runtime when available
- keeps the hardened sandbox defaults

If you prefer a manual setup, copy the example files:

```bash
mkdir -p ~/.config/donkey
mkdir -p ~/.donkey/paddocks
cp deploy/donkey.toml.example ~/.config/donkey/donkey.toml
cp deploy/donkey.env.example ~/.config/donkey/donkey.env
chmod 600 ~/.config/donkey/donkey.env
```

`deploy/donkey.toml.example`:

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

`deploy/donkey.env.example` starts like this:

```bash
TELEGRAM_BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN
OPENROUTER_API_KEY=YOUR_PROVIDER_KEY
BRAVE_API_KEY=YOUR_BRAVE_SEARCH_KEY   # optional, enables web_search
```

Fill in only the tokens and keys you actually use.

## Important Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DONKEY_HOME` | Override home directory | `~/.donkey` |
| `DONKEY_CONFIG` | Override config path | `~/.config/donkey/donkey.toml` |
| `DONKEY_LOG_LEVEL` | Override log level | from config |
| `DONKEY_MAGMA_SQLITE_PATH` | Override SQLite MAGMA path | `~/.donkey/state/magma.sqlite` in SQLite builds |
| `DONKEY_PG_DSN` | Enable PostgreSQL-backed MAGMA runtime | unset |
| `DONKEY_HTTP_PORT` | HTTP gateway port. `0` disables it | `8080` |

## Verification

```bash
./donkey --version
./donkey doctor
```

`doctor` verifies config parsing, storage wiring, sandbox policy, runtime
availability, and optional credentials such as `BRAVE_API_KEY` when you want
the `web_search` tool to work.

## Running

### Daemon

```bash
./donkey start
```

Disable the HTTP gateway if you do not need it:

```bash
DONKEY_HTTP_PORT=0 ./donkey start
```

### Systemd User Service

```bash
./donkey service install
./donkey service start
```

## OCI Container

```bash
docker build -t donkey .

docker run -d \
  --name donkey \
  -v ~/.donkey:/home/donkey/.donkey \
  -v ~/.config/donkey:/home/donkey/.config/donkey \
  donkey
```

Use a non-root runtime setup so host-mounted state does not become `root`-owned.

## Troubleshooting

### `nim` not found

Install Nim from https://nim-lang.org/install.html

### Sandbox runtime missing

Install `docker` or `podman`, then align `[sandbox].runtime` with what is
actually available.

### Config not found

Check `~/.config/donkey/donkey.toml` or pass `--config`.

### Permission denied

Fix permissions on config and env:

```bash
chmod 600 ~/.config/donkey/donkey.toml ~/.config/donkey/donkey.env
```

## Next Steps

- [Quickstart](../quickstart.md)
- [Configuration Reference](../reference/configuration.md)
- [Architecture](../ARCHITECTURE.md)
