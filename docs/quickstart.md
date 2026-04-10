# Quickstart
Get Donkey running in a few minutes with the current SQLite-first setup.

## Prerequisites

- Nim 2.2 or higher
- One channel token, such as `TELEGRAM_BOT_TOKEN` or `DISCORD_BOT_TOKEN`
- One provider API key, such as `ZAI_CODING_API_KEY`, `OPENROUTER_API_KEY`, or `MINIMAX_API_KEY`
- `docker` or `podman` if you want the recommended hardened shell sandbox

## 1. Build

```bash
git clone https://github.com/manelsen/donkey.git
cd donkey
nimble build
```

The normal build is already SQLite-first and embeds SQLite plus `sqlite-vec`.

## 2. Run Setup

```bash
./donkey setup
```

This writes:

- `~/.config/donkey/donkey.toml`
- `~/.config/donkey/donkey.env`
- local state directories under `~/.donkey/`

It also:

- detects a usable OCI runtime and writes it into `[sandbox].runtime`
- keeps the hardened sandbox defaults
- offers optional Brave Search setup for the `web_search` tool
- asks for the instance-wide default provider/model used before a user picks one
- prints the exact `doctor` and `start` commands at the end

If you want to override the generated config, the resulting `donkey.toml` looks like this:

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

Your generated `donkey.env` will contain only the tokens and keys you supplied. A minimal example looks like this:

```bash
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
ZAI_CODING_API_KEY=YOUR_PROVIDER_KEY_HERE
BRAVE_API_KEY=YOUR_BRAVE_SEARCH_KEY   # optional, enables web_search
```

The example files are:

- [deploy/donkey.toml.example](/home/micelio/git/donkey/deploy/donkey.toml.example)
- [deploy/donkey.env.example](/home/micelio/git/donkey/deploy/donkey.env.example)

If you prefer Podman, update `runtime` in `donkey.toml`:

```toml
[sandbox]
mode = "oci"
runtime = "podman"
image = "alpine"
allow_host_fallback = false
allow_network = false
read_only_rootfs = true
```

## 3. Validate

```bash
./donkey doctor
```

This checks:

- config parsing
- SQLite-first runtime wiring
- the active storage path and default provider/model
- sandbox policy
- availability of the configured OCI runtime
- provider, channel, and optional Brave Search credentials

## 4. Start

```bash
./donkey start
```

To disable the HTTP gateway completely:

```bash
DONKEY_HTTP_PORT=0 ./donkey start
```

## 5. Use It

Talk to your configured channel bot.

Useful first commands:

- `/help`
- `/models`
- `/reset`

## Service Mode

To run Donkey as a user service:

```bash
./donkey service install
./donkey service start
```

## Troubleshooting

### `doctor` fails on sandbox/runtime

Install `docker` or `podman`, then make sure `[sandbox].runtime` matches what is available.

### Channel or provider auth fails

Check the relevant secrets in `~/.config/donkey/donkey.env`.

### Permission errors

Check ownership and permissions on:

- `~/.config/donkey`
- `~/.donkey`
- `~/.donkey/paddocks`

## What's Next?

- [Installation](getting_started/installation.md)
- [Configuration Reference](reference/configuration.md)
- [Commands](topics/commands.md)
- [Architecture](ARCHITECTURE.md)
