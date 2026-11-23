# Configuration Reference
Current `donkey.toml` reference for the SQLite-first runtime.

## Overview

Donkey reads a single TOML file, usually at `~/.config/donkey/donkey.toml`.
Secrets and tokens should live in `~/.config/donkey/donkey.env`.

Minimal recommended config:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/donkey.log"
default_provider = "zai-coding"
default_model = "glm-4.7"

[sandbox]
mode = "oci"
runtime = "docker"
image = "alpine"
allow_host_fallback = false
allow_network = false
read_only_rootfs = true
```

## `[donkey]` - Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `home` | string | `~/.donkey` | Base directory for Donkey state |
| `paddocks` | string | `~/.donkey/paddocks` | Per-user workspace directory |
| `log_level` | string | `info` | Logging level: `debug`, `info`, `warn`, `error` |
| `log_file` | string | empty | Log file path. Empty means stderr only |
| `default_provider` | string | empty | Instance-wide default provider before per-user preferences exist |
| `default_model` | string | empty | Instance-wide default model before per-user preferences exist |

Example:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/donkey.log"
default_provider = "zai-coding"
default_model = "glm-4.7"
```

## `[sandbox]` - Shell Sandbox

Shell execution now uses a top-level `[sandbox]` section.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mode` | string | `oci` | Shell mode: `oci`, `none`, or `wasm` |
| `runtime` | string | `docker` | OCI runtime command, typically `docker` or `podman` |
| `image` | string | `alpine` | OCI image for shell execution |
| `allow_host_fallback` | bool | `false` | Allow fallback to host shell if the configured sandbox fails |
| `allow_network` | bool | `false` | Allow outbound network access inside the OCI sandbox |
| `read_only_rootfs` | bool | `true` | Run the OCI sandbox with a read-only root filesystem |

Recommended production config:

```toml
[sandbox]
mode = "oci"
runtime = "docker"
image = "alpine"
allow_host_fallback = false
allow_network = false
read_only_rootfs = true
```

Security notes:

- `mode = "none"` is rejected in production
- `allow_host_fallback = true` is dev-only
- `allow_network = true` is dev-only
- `read_only_rootfs = false` is dev-only
- startup validates the policy and aborts on invalid production settings

## Storage Model

### SQLite-first default

The normal build is SQLite-first. In that mode:

- MAGMA uses SQLite by default
- SQLite base and `sqlite-vec` are embedded in the binary
- the default database path is `~/.donkey/state/magma.sqlite`

You can override the path with `DONKEY_MAGMA_SQLITE_PATH`.

### PostgreSQL-backed MAGMA

If `DONKEY_PG_DSN` is set, Donkey can use PostgreSQL-backed MAGMA instead.
Keep this disabled unless you explicitly want the PostgreSQL runtime.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DONKEY_CONFIG` | Override config file path |
| `DONKEY_HOME` | Override `donkey.home` |
| `DONKEY_LOG_LEVEL` | Override `donkey.log_level` |
| `DONKEY_MAGMA_SQLITE_PATH` | Override SQLite MAGMA path |
| `DONKEY_PG_DSN` | Enable PostgreSQL-backed MAGMA runtime |
| `DONKEY_HTTP_PORT` | HTTP gateway port. Set to `0` to disable it |
| `DONKEY_DM_POLICY` | DM authorization: `open`, `pairing` or `allowlist` (default `open`) |
| `DONKEY_TELEGRAM_ALLOWED_GROUPS` | Comma-separated Telegram chat ids allowed to use the bot; empty allows every group |
| `DONKEY_STT_API_KEY` | Speech-to-text key; falls back to `OPENAI_API_KEY` |
| `DONKEY_STT_URL` | Transcription endpoint (default: OpenAI `/v1/audio/transcriptions`) |
| `DONKEY_STT_MODEL` | Transcription model (default: `whisper-1`) |
| `DONKEY_TTS_API_KEY` | Text-to-speech key; falls back to `OPENAI_API_KEY` |
| `DONKEY_TTS_URL` | Speech endpoint (default: OpenAI `/v1/audio/speech`) |
| `DONKEY_TTS_MODEL` | Speech model (default: `tts-1`) |
| `DONKEY_TTS_VOICE` | Default voice (default: `alloy`) |
| `DONKEY_ATTACHMENT_RETENTION_DAYS` | Remove files in each paddock's `attachments/` older than this many days, checked hourly. Unset or `0` keeps everything |
| `TELEGRAM_BOT_TOKEN` | Telegram channel token |
| `DISCORD_BOT_TOKEN` | Discord channel token |
| `DONKEY_DISCORD_ALLOWED_CHANNELS` | Comma-separated Discord server or channel ids the bot serves (`*` = all). Other servers are ignored before any identity is created. DMs follow the DM policy. Empty serves every server |
| `DONKEY_DISCORD_REQUIRE_MENTION` | `1`/`true`/`yes`/`on`: in a server, answer only messages that mention the bot or reply to it. DMs are unaffected. Off by default |
| `ZAI_API_KEY` | ZAI generic provider key |
| `ZAI_CODING_API_KEY` | ZAI Coding provider key |
| `ZAI_ANTHROPIC_API_KEY` | ZAI Anthropic provider key |
| `OPENROUTER_API_KEY` | OpenRouter provider key |
| `OPENAI_API_KEY` | OpenAI provider key |
| `DEEPSEEK_API_KEY` | DeepSeek provider key |
| `ANTHROPIC_API_KEY` | Anthropic provider key |
| `GEMINI_API_KEY` | Gemini provider key |
| `MINIMAX_API_KEY` | MiniMax provider key |
| `MISTRAL_API_KEY` | Mistral AI provider key |
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock API key (sent as a bearer) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | AWS Bedrock IAM credentials, signed with SigV4 (used when no Bedrock API key is set) |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | Bedrock region (default `us-east-1`) |
| `BEDROCK_BASE_URL` | Override the Bedrock runtime endpoint |
| `MISTRAL_BASE_URL` | Override the Mistral endpoint (base URL; `/chat/completions` is appended) |
| `BRAVE_API_KEY` | Enables `web_search` via Brave Search |

Example:

```bash
export DONKEY_CONFIG="$HOME/.config/donkey/donkey.toml"
export DONKEY_HTTP_PORT=0
export TELEGRAM_BOT_TOKEN=...
export ZAI_CODING_API_KEY=...
```

## OpenAI-Compatible API

When the HTTP gateway is enabled, it exposes two OpenAI-shaped endpoints on the
same port and Bearer auth:

| Endpoint | Method | Behavior |
|---|---|---|
| `/v1/models` | GET | Lists the configured model as `owned_by: donkey` |
| `/v1/chat/completions` | POST | Runs a real agent turn (tools, memory, session) and returns a `chat.completion`; `stream: true` returns SSE chunks |
| `/api/sessions`, `/api/providers` | GET | Dashboard read endpoints (Bearer): session detail and provider health |
| `/api/sessions/{userId}/task` | POST | Dashboard action: `{"action":"new"}` starts a fresh task for an existing session |
| `/dashboard` | GET | Public HTML shell for the status/logs page; the page asks for the Bearer token and keeps it in `sessionStorage` |

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer $DONKEY_HTTP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"donkey/default","messages":[{"role":"user","content":"oi"}]}'
```

This is the agent loop, not a provider proxy: the same tools, memory and
session a channel turn uses. `user` is the identity and must be present; the
`api:` namespace is applied automatically, and programmatic users never enter
channel onboarding. `model` is advisory and the instance routing decides the
provider. `stream: false` returns one `chat.completion`; `stream: true` returns
`text/event-stream` with `chat.completion.chunk` frames and `data: [DONE]`.

Errors follow the OpenAI shape: `400` parse/unsupported, `401` missing token,
`403` revoked or not allowed (before dispatch), `413` body over the cap, `429`
one turn per user or capacity, `502` redacted provider error, `503` wiring
missing, `504` turn deadline (`DONKEY_HTTP_AGENT_TIMEOUT_SEC`, default 120 s,
cap 600 s).

`GET /api/sessions` takes `limit` (default 50, max 200) and `offset`; invalid
values are clamped, never a 500. Without `DONKEY_HTTP_TOKEN`, every `/api/*`
route answers `401` (even on loopback); only `/`, `/health` and the
`/dashboard` shell stay open, and the `/v1/*` routes keep their local-only
behavior.

## Happy Path

`~/.config/donkey/donkey.toml`:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/donkey.log"
default_provider = "zai-coding"
default_model = "glm-4.7"

[sandbox]
mode = "oci"
runtime = "docker"
image = "alpine"
allow_host_fallback = false
allow_network = false
read_only_rootfs = true
```

`~/.config/donkey/donkey.env`:

```bash
TELEGRAM_BOT_TOKEN=...
ZAI_CODING_API_KEY=...
BRAVE_API_KEY=...   # optional
```

Validation and startup:

```bash
./donkey doctor --config ~/.config/donkey/donkey.toml
./donkey start --config ~/.config/donkey/donkey.toml
```

## Related Docs

- [Quickstart](../quickstart.md)
- [Installation](../getting_started/installation.md)
- [Architecture](../ARCHITECTURE.md)
