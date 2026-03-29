# Installation
How to install and configure Donkey

## Requirements

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Nim | 2.0 | 2.2+ |
| RAM | 512 MB | 1 GB |
| Disk | 1 GB | 5 GB |
| OS | Linux/macOS/Windows | Linux |

### Optional Dependencies

| Dependency | Purpose | Install |
|------------|---------|---------|
| PostgreSQL | Semantic memory | `libpq-dev` |
| SQLite | Local storage | `libsqlite3-dev` |
| Docker | Shell sandbox | Docker daemon |

## Installation Methods

### Method 1: Build from Source

```bash
# Clone repository
git clone https://github.com/manelsen/donkey.git
cd donkey

# Standard build
nim c src/donkey

# With database support
nim c -d:withSqlite src/donkey
nim c -d:withPostgres src/donkey

# Production build
nim c -d:release --mm:orc --warningAsError:on src/donkey
```

### Method 2: Nimble

```bash
nimble install donkey
```

### Method 3: Pre-built Binary

Download from the releases page on GitHub.

## Configuration

### Directory Structure

```bash
~/.donkey/                 # Home directory
├── paddocks/              # User workspaces
│   └── <user_id>/
│       ├── USER.md
│       └── MEMORY.md
└── logs/                  # Log files

~/.config/donkey/          # Configuration
└── donkey.toml
```

### Create Configuration

```bash
mkdir -p ~/.config/donkey
mkdir -p ~/.donkey/paddocks
```

### Example Configuration

Copy from deploy:

```bash
cp deploy/donkey.toml.example ~/.config/donkey/donkey.toml
```

Or create manually:

```toml
# ~/.config/donkey/donkey.toml

[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"
log_file = "~/.donkey/logs/donkey.log"

# Channel: Telegram
[telegram]
enabled = true
bot_token = "YOUR_TELEGRAM_BOT_TOKEN"

# Channel: Discord
[discord]
enabled = false
bot_token = ""

# LLM Providers
[providers.anthropic]
enabled = true
api_key = "YOUR_ANTHROPIC_API_KEY"
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7

[providers.openai]
enabled = false
api_key = "YOUR_OPENAI_API_KEY"
model = "gpt-4o"

# Hooks (optional)
[hooks]
enabled = false

# Security
[donkey.security]
dm_policy = "allow"
sandbox_mode = "docker"
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DONKEY_HOME` | Override home directory | `~/.donkey` |
| `DONKEY_SECRETS_KEY` | Encryption key for secrets | - |
| `DONKEY_LOG_LEVEL` | Override log level | from config |
| `DONKEY_CONFIG` | Override config path | `~/.config/donkey/donkey.toml` |

### Secrets Encryption

API keys are encrypted at rest. Set a secrets key:

```bash
export DONKEY_SECRETS_KEY="your-32-byte-hex-key"
```

Generate a key:

```bash
openssl rand -hex 32
```

## Verification

Check installation:

```bash
./donkey --version
# Output: donkey 1.0.0

./donkey --help
# Shows available commands
```

## Running

### Daemon Mode

```bash
./donkey --config ~/.config/donkey/donkey.toml
```

### CLI Mode

```bash
./donkey --cli
```

### Systemd Service

Install as user service:

```bash
bash deploy/install.sh
```

Start:

```bash
systemctl --user start donkey
```

## Docker

### Build Image

```bash
docker build -t donkey .
```

### Run Container

```bash
docker run -d \
  --name donkey \
  -v ~/.donkey:/root/.donkey \
  -v ~/.config/donkey:/root/.config/donkey \
  donkey
```

## Troubleshooting

### Build Errors

**"nim not found"**
Install Nim: https://nim-lang.org/install.html

**"missing dependency"**
Install required system packages.

### Runtime Errors

**"config not found"**
Check config path exists.

**"permission denied"**
Fix file permissions:
```bash
chmod 600 ~/.config/donkey/donkey.toml
```

## Next Steps

- [Quickstart](quickstart.md)
- [Basic Concepts](basic_concepts.md)
- [Configuration Reference](../reference/configuration.md)
