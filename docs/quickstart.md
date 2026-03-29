# Quickstart
Get Donkey running in 5 minutes

## Prerequisites

- Nim 2.0 or higher
- A Telegram bot token (or Discord bot token)
- An LLM API key (Anthropic, OpenAI, etc.)

## 1. Install Donkey

Clone and build:

```bash
git clone https://github.com/manelsen/donkey.git
cd donkey
nim c src/donkey
```

Or use nimble:

```bash
nimble install donkey
```

## 2. Create Configuration

Create the config directory:

```bash
mkdir -p ~/.config/donkey
```

Copy the example config:

```bash
cp deploy/donkey.toml.example ~/.config/donkey/donkey.toml
```

Edit `~/.config/donkey/donkey.toml`:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"

[telegram]
enabled = true
bot_token = "YOUR_BOT_TOKEN_HERE"

[providers.anthropic]
enabled = true
api_key = "YOUR_API_KEY_HERE"
model = "claude-sonnet-4-20250514"
```

## 3. Run

Start the daemon:

```bash
./donkey --config ~/.config/donkey/donkey.toml
```

You should see:

```
INFO  Donkey v1.0.0 starting...
INFO  Loading configuration...
INFO  Connecting to Telegram...
INFO  Ready!
```

## 4. Test

Send `/start` to your Telegram bot!

You should receive a greeting. Try:

- `/help` - Show available commands
- `/models` - Switch AI model
- `/reset` - Reset conversation

## What's Next?

- [Basic Concepts](getting_started/basic_concepts.md) - Understand the architecture
- [Configuration Reference](reference/configuration.md) - Full configuration options
- [Commands](topics/commands.md) - Slash command system
- [Hooks](topics/hooks.md) - Message flow interception

## Troubleshooting

### "Connection refused" error

Make sure your Telegram bot token is correct and you have internet access.

### "API key invalid" error

Check that your Anthropic/OpenAI API key is correct and has available credits.

### "Permission denied" error

Check file permissions on your config and data directories.

## Common Patterns

### Enable Discord

```toml
[discord]
enabled = true
bot_token = "YOUR_DISCORD_TOKEN"
```

### Use OpenAI

```toml
[providers.openai]
enabled = true
api_key = "YOUR_OPENAI_KEY"
model = "gpt-4o"
```

### Enable Hooks

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "rag_context"
enabled = true
phase = "pre_llm"
```
