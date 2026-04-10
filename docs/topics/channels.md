# Channels
Messaging platform integrations

## Overview

Donkey exposes a unified channel abstraction over the messaging adapters it ships.
The adapters translate between platform-specific APIs and Donkey's internal
message format, while outbound UI behavior is governed by the shared capability
model in `core/outbound`.

## Supported Channels

This matrix reflects the current `core/outbound` capability model used by the runtime.

| Channel | Implemented | Editable UI | Stream updates | Components | Reactions |
|---------|-------------|-------------|----------------|------------|-----------|
| [Telegram](#telegram) | yes | yes | yes | yes | yes |
| [Discord](#discord) | yes | yes | yes | yes | yes |
| [Slack](#slack) | yes | no | no | no | no |
| WeChat Work | yes | no | no | no | no |
| WeChat | yes | no | no | no | no |
| QQ | yes | no | no | no | no |
| Feishu | yes | no | no | no | no |
| WhatsApp | yes | no | no | no | no |
| Signal | yes | no | no | no | no |
| DingTalk | yes | no | no | no | no |
| Matrix | no | no | no | no | no |
| Email | no | no | no | no | no |
| CLI | no | no | no | no | no |

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

```bash
export TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
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
- DM-oriented editable UI surfaces

### Configuration

```bash
export DISCORD_BOT_TOKEN=YOUR_DISCORD_TOKEN
```

### Required Intents

Enable these in Discord Developer Portal:
- `MESSAGE CONTENT INTENT` - Required for reading messages
- direct messages / message create events for DM use

### Slash Commands

Register in your server or globally via API.

---

## Slack

### Features
- Messages
- Basic outbound send/edit support via adapter

### Configuration

```bash
# Slack support is adapter-level today and not part of the recommended
# quickstart path. Configure the corresponding adapter tokens in the env
# used to start Donkey.
```

### Required Scopes

- `chat:write`
- `commands`
- `app_mentions:read`

---

## CLI

The CLI is not part of the outbound capability matrix. It is an operational
surface for `setup`, `doctor`, `about`, `service`, and local daemon control.

### Usage

```bash
./donkey about
./donkey doctor
./donkey service start
```

### Example Session

```
Snapshot
--------
- storage: SQLite-first MAGMA (/home/user/.donkey/state/magma.sqlite)
- default model: smart routing
- web search: disabled (set BRAVE_API_KEY to enable web_search)
- sandbox: mode=oci, runtime=docker, network=off, rootfs=ro, host-fallback=off
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

A user can be reached across multiple channels:

```
User: alice
├── telegram
├── discord
└── qq
```

The runtime keeps channel identity mappings while the session/memory layer owns
the actual conversational state.

---

## DM Policy

Control who can send direct messages:

See `docs/reference/configuration.md` for the active DM policy fields and the
current config shape.

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
