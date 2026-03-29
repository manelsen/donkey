# Configuration Reference
Complete donkey.toml reference

## Overview

Donkey is configured via a single TOML file. The default location is `~/.config/donkey/donkey.toml`.

## Configuration File

```toml
[donkey]
# Core settings

[telegram]
# Telegram channel settings

[discord]
# Discord channel settings

[providers]
# LLM provider settings

[hooks]
# Hook system settings

[donkey.security]
# Security settings
```

---

## `[donkey]` - Core Settings

### Basic Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `home` | string | `~/.donkey` | Base directory for Donkey data |
| `paddocks` | string | `~/.donkey/paddocks` | User workspace directory |
| `log_level` | string | `info` | Logging level: `debug`, `info`, `warn`, `error` |
| `log_file` | string | - | Log file path (empty = stderr only) |

### Example

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/logs/donkey.log"
```

---

## Channel Configuration

### `[telegram]`

Telegram Bot API integration.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable Telegram channel |
| `bot_token` | string | - | Telegram bot token from @BotFather |
| `allowlist` | array | `[]` | Allowed URL domains for web requests |

### Example

```toml
[telegram]
enabled = true
bot_token = "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
allowlist = ["telegram.org", "example.com"]
```

### Getting a Bot Token

1. Open Telegram and chat with [@BotFather](https://t.me/botfather)
2. Send `/newbot`
3. Follow prompts to name your bot
4. Copy the token provided

---

### `[discord]`

Discord Bot integration.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable Discord channel |
| `bot_token` | string | - | Discord bot token |
| `application_id` | string | - | Discord application ID |
| `guild_id` | string | - | Guild ID for guild commands |

### Example

```toml
[discord]
enabled = false
bot_token = ""
application_id = ""
guild_id = ""
```

### Getting a Discord Bot Token

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application
3. Go to "Bot" section
4. Click "Reset Token" and copy the token
5. Enable necessary intents (Message Content Intent required)

---

### `[slack]`

Slack workspace integration.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable Slack channel |
| `bot_token` | string | - | Slack bot token (`xoxb-...`) |
| `signing_secret` | string | - | Slack signing secret |
| `app_token` | string | - | Slack app-level token (`xapp-...`) |

### Example

```toml
[slack]
enabled = false
bot_token = ""
signing_secret = ""
app_token = ""
```

---

### `[wechat]`

WeChat Work integration.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable WeChat channel |
| `corp_id` | string | - | WeChat Corp ID |
| `agent_id` | string | - | WeChat Agent ID |
| `corp_secret` | string | - | WeChat Corp Secret |

### Example

```toml
[wechat]
enabled = false
corp_id = ""
agent_id = ""
corp_secret = ""
```

---

## `[providers]` - LLM Providers

### Provider Configuration Structure

```toml
[providers.<name>]
enabled = true
api_key = ""
model = "default-model"
max_tokens = 8192
temperature = 0.7
```

### Common Provider Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable this provider |
| `api_key` | string | - | API key for the provider |
| `model` | string | - | Default model to use |
| `max_tokens` | int | `8192` | Maximum tokens in response |
| `temperature` | float | `0.7` | Response randomness (0-1) |

---

### `[providers.anthropic]`

Anthropic Claude API.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | `claude-sonnet-4-20250514` | Claude model |
| `max_tokens` | int | `8192` | Max response tokens |
| `temperature` | float | `0.7` | Response creativity |

### Available Models

| Model | Description |
|-------|-------------|
| `claude-opus-4-5` | Most capable, slower |
| `claude-sonnet-4-20250514` | Balanced performance |
| `claude-haiku-4-5` | Fast, lower capability |

### Example

```toml
[providers.anthropic]
enabled = true
api_key = "sk-ant-api03-..."
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7
```

---

### `[providers.openai]`

OpenAI GPT API.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | `gpt-4o` | GPT model |
| `max_tokens` | int | `4096` | Max response tokens |
| `temperature` | float | `0.7` | Response creativity |

### Available Models

| Model | Description |
|-------|-------------|
| `gpt-4o` | Latest GPT-4, balanced |
| `gpt-4o-mini` | Faster, lower cost |
| `gpt-4-turbo` | Previous GPT-4 |
| `gpt-3.5-turbo` | Fastest, basic |

### Example

```toml
[providers.openai]
enabled = false
api_key = "sk-..."
model = "gpt-4o"
max_tokens = 4096
temperature = 0.7
```

---

### `[providers.openrouter]`

OpenRouter multi-provider aggregation.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | - | Model identifier |
| `site_url` | string | - | Your site URL |
| `site_name` | string | - | Your site name |

### Example

```toml
[providers.openrouter]
enabled = false
api_key = ""
model = "anthropic/claude-3-opus"
site_url = "https://your-app.com"
site_name = "Your App"
```

---

### `[providers.gemini]`

Google Gemini API.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | `gemini-2.0-flash` | Gemini model |
| `max_tokens` | int | `8192` | Max response tokens |

### Available Models

| Model | Description |
|-------|-------------|
| `gemini-2.0-flash` | Fast, latest |
| `gemini-1.5-pro` | Higher capability |
| `gemini-1.5-flash` | Balanced |

### Example

```toml
[providers.gemini]
enabled = false
api_key = ""
model = "gemini-2.0-flash"
max_tokens = 8192
```

---

### `[providers.deepseek]`

DeepSeek API.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | `deepseek-chat` | DeepSeek model |
| `base_url` | string | `https://api.deepseek.com` | API base URL |

### Example

```toml
[providers.deepseek]
enabled = false
api_key = ""
model = "deepseek-chat"
base_url = "https://api.deepseek.com"
```

---

### `[providers.ollama]`

Local Ollama server.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | `llama3` | Ollama model |
| `base_url` | string | `http://localhost:11434` | Ollama server URL |

### Example

```toml
[providers.ollama]
enabled = false
model = "llama3"
base_url = "http://localhost:11434"
```

---

## `[hooks]` - Hook System

### Hook Configuration Structure

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "hook_name"
enabled = true
phase = "pre_llm"
```

### Hook Phases

| Phase | Description |
|-------|-------------|
| `pre_llm` | Before LLM call |
| `post_llm` | After LLM response |
| `pre_tool` | Before tool execution |
| `post_tool` | After tool result |
| `post_response` | Before sending response |

### Built-in Hooks

#### RAG Context Hook

```toml
[[hooks.definition]]
name = "rag_context"
enabled = false
phase = "pre_llm"
[hooks.definition.params]
max_hits = 5
similarity_threshold = 0.7
```

#### Memory Capture Hook

```toml
[[hooks.definition]]
name = "memory_capture"
enabled = false
phase = "post_response"
[hooks.definition.params]
capture_user = true
capture_assistant = true
```

#### Spam Filter Hook

```toml
[[hooks.definition]]
name = "spam_filter"
enabled = false
phase = "pre_llm"
[hooks.definition.params]
block_threshold = 0.8
```

---

## `[donkey.security]` - Security Settings

### DM Policy

Controls who can send direct messages to the bot.

| Value | Description |
|-------|-------------|
| `allow` | Allow all DMs |
| `block` | Block all DMs |
| `whitelist` | Only whitelisted users |

```toml
[donkey.security]
dm_policy = "allow"
```

### Sandbox Mode

Shell command execution isolation.

| Value | Description |
|-------|-------------|
| `none` | No isolation (not recommended) |
| `docker` | Ephemeral Docker container |

```toml
[donkey.security]
sandbox_mode = "docker"
sandbox_image = "alpine"
```

### Execution

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `exec_timeout_seconds` | int | `30` | Max shell command duration |

### Web Access

URL allowlist for web fetching.

```toml
[donkey.security]
web_allowlist = [
  "api.github.com",
  "example.com",
]
```

---

## `[donkey.sandbox]` - Sandbox Settings

### Docker Sandbox

```toml
[donkey.sandbox]
enabled = true
mode = "docker"
image = "alpine"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable sandbox |
| `mode` | string | `docker` | Sandbox mode |
| `image` | string | `alpine` | Docker image |

---

## `[memory]` - Memory Settings

### Workspace Memory

Markdown file-based memory (always enabled).

```toml
[memory]
paddocks_dir = "~/.donkey/paddocks"
```

### Semantic Memory (PostgreSQL)

```toml
[memory.postgres]
enabled = false
host = "localhost"
port = 5432
database = "donkey"
user = "postgres"
password = ""
```

### Embedding Configuration

```toml
[memory.embedding]
provider = "openai"
model = "text-embedding-3-small"
dimension = 1536
```

---

## `[donkey.web]` - Web Access

### Allowlist

Domains allowed for web requests.

```toml
[donkey.web]
allowlist = [
  "https://api.github.com",
  "https://example.com",
]
```

---

## Environment Variables

Override configuration via environment variables.

| Variable | Description | Overrides |
|----------|-------------|-----------|
| `DONKEY_HOME` | Home directory | `donkey.home` |
| `DONKEY_CONFIG` | Config file path | - |
| `DONKEY_LOG_LEVEL` | Log level | `donkey.log_level` |
| `DONKEY_SECRETS_KEY` | Secrets encryption key | - |

### Example

```bash
export DONKEY_HOME="/opt/donkey"
export DONKEY_LOG_LEVEL="debug"
export DONKEY_SECRETS_KEY="your-32-byte-hex-key"
```

---

## Full Example Configuration

```toml
# ~/.config/donkey/donkey.toml

[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"

[telegram]
enabled = true
bot_token = "YOUR_BOT_TOKEN"

[discord]
enabled = false
bot_token = ""

[providers.anthropic]
enabled = true
api_key = "YOUR_ANTHROPIC_KEY"
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7

[providers.openai]
enabled = false
api_key = "YOUR_OPENAI_KEY"
model = "gpt-4o"

[hooks]
enabled = false

[donkey.security]
dm_policy = "allow"
sandbox_mode = "docker"
sandbox_image = "alpine"
exec_timeout_seconds = 30

[donkey.web]
allowlist = []
```

---

## Related

- [Quickstart](../quickstart.md)
- [Installation](../getting_started/installation.md)
- [Hooks System](../topics/hooks.md)
