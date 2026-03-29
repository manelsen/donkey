# Channels
Messaging platform integrations

## Overview

Donkey supports 13 messaging platforms through a unified ChannelPort interface. Each platform has its own adapter that translates between the platform's API and Donkey's internal message format.

## Supported Channels

| Channel | Status | Features |
|---------|--------|---------|
| [Telegram](#telegram) | Stable | Messages, keyboards, editing, reactions |
| [Discord](#discord) | Stable | Messages, embeds, components, slash commands |
| [Slack](#slack) | Stable | Messages, Block Kit, interactive |
| WeChat Work | Stable | Basic messaging |
| WeChat | Stable | Basic messaging |
| QQ | Stable | Basic messaging |
| Feishu | Stable | Basic messaging |
| WhatsApp | Stable | Basic messaging |
| Signal | Stable | Basic messaging |
| DingTalk | Stable | Basic messaging |
| Matrix | Stable | Basic messaging |
| Email | Stable | Basic messaging |
| CLI | Stable | Full features |

---

## Telegram

### Features
- Text messages
- Inline keyboards
- Message editing
- Reactions
- Media (photos, documents)
- Voice messages

### Configuration

```toml
[telegram]
enabled = true
bot_token = "YOUR_BOT_TOKEN"
```

### Bot Commands

Register commands with BotFather:
```
/start - Start conversation
/menu - Show menu
/help - Show help
```

### Inline Keyboards

```nim
let buttons = @[
  @[("Yes", "yes"), ("No", "no")],
  @[("Cancel", "cancel")]
]
adapter.sendKeyboard(userId, "Continue?", buttons)
```

---

## Discord

### Features
- Text messages
- Embeds
- Components (buttons, select menus)
- Slash commands
- Reactions
- Threads

### Configuration

```toml
[discord]
enabled = true
bot_token = "YOUR_DISCORD_TOKEN"
application_id = "YOUR_APP_ID"
guild_id = "YOUR_GUILD_ID"  # Optional
```

### Required Intents

Enable these in Discord Developer Portal:
- `MESSAGE CONTENT INTENT` - Required for reading messages
- `GUILD MESSAGES` - For guild channels
- `DIRECT MESSAGES` - For DMs

### Slash Commands

Register in your server or globally via API.

---

## Slack

### Features
- Messages
- Block Kit
- Interactive components
- Workflows

### Configuration

```toml
[slack]
enabled = true
bot_token = "xoxb-..."
signing_secret = "YOUR_SIGNING_SECRET"
app_token = "xapp-..."  # Optional, for socket mode
```

### Required Scopes

- `chat:write`
- `commands`
- `app_mentions:read`

---

## CLI

The command-line interface provides direct access without a messaging platform.

### Usage

```bash
./donkey --cli
```

### Example Session

```
> Hello!
Hello! How can I help you today?

> What time is it?
It's currently 3:45 PM.

> /reset
Session reset. How can I help you?

> /exit
Goodbye!
```

---

## Channel Selection

When a message is received, the channel is automatically detected:

```nim
case inbound.channel
of ckTelegram:
  echo "From Telegram"
of ckDiscord:
  echo "From Discord"
of ckSlack:
  echo "From Slack"
of ckCli:
  echo "From CLI"
```

---

## Multi-Channel Sessions

A user can have sessions across multiple channels:

```
User: alice
├── Session: telegram_123 (Telegram)
├── Session: discord_456 (Discord)
└── Session: cli_789 (CLI)
```

Each channel maintains its own session history.

---

## DM Policy

Control who can send direct messages:

```toml
[donkey.security]
dm_policy = "allow"  # allow, block, whitelist
```

### Whitelist Mode

```toml
[donkey.security]
dm_policy = "whitelist"
dm_whitelist = ["user_id_1", "user_id_2"]
```

---

## Message Format

### Inbound

```nim
InboundMessage* = object
  userId*:    UserId       # Platform user ID
  channelId*: string      # Platform message ID
  text*:      string      # Message content
  mediaUrl*:  string      # Attached media URL
  channel*:   ChannelKind # Source channel
```

### Outbound

```nim
OutboundMessage* = object
  userId*:    UserId      # Target user
  text*:      string      # Message text
  replyTo*:   string      # Message ID to reply to
  channel*:   ChannelKind # Target channel
  keyboard*:  seq[seq[(string, string)]]  # Buttons
  mediaUrl*:  string      # Media URL
```

---

## Related

- [Configuration Reference](../reference/configuration.md)
- [Channel Port API](../reference/channel_port.md)
