# Channel Port API Reference
Complete reference for the channel abstraction

## Overview

The ChannelPort provides a unified interface for all messaging channels. This abstraction allows Donkey to work with any messaging platform without knowing platform-specific details.

**Architecture:** Channels are Adapters that implement the ChannelPort concept.

---

## ChannelPort Concept

```nim
type
  ChannelPort* = concept c, var vc
    c.send(OutboundMessage) is Result[void, string]
    vc.receive() is Result[seq[InboundMessage], string]
    c.ack(string)
```

| Method | Description |
|--------|-------------|
| `c.send(OutboundMessage)` | Send a message (immutable) |
| `vc.receive()` | Receive messages (mutable, may advance state) |
| `c.ack(string)` | Acknowledge a message |

---

## OutboundChannelPort

Object-based outbound channel interface.

```nim
type
  OutboundChannelPort* = object
    send*:         proc(msg: OutboundMessage): Result[void, string] {.gcsafe.}
    sendReturnId*: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.}
    editMessage*:  proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.}
    sendKeyboard*: proc(userId: UserId; text: string;
                         buttons: seq[seq[(string, string)]];
                         replyTo = ""): Result[void, string] {.gcsafe.}
    editKeyboard*: proc(userId: UserId; msgId, text: string;
                         buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.}
    setMessageReaction*: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.}
```

### Methods

#### `send`

Send a simple text message.

```nim
proc(msg: OutboundMessage): Result[void, string] {.gcsafe.}
```

#### `sendReturnId`

Send a message and return the message ID.

```nim
proc(msg: OutboundMessage): Result[string, string] {.gcsafe.}
```

#### `editMessage`

Edit an existing message.

```nim
proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.}
```

#### `sendKeyboard`

Send a message with inline keyboard buttons.

```nim
proc(userId: UserId; text: string;
     buttons: seq[seq[(string, string)]];
     replyTo = ""): Result[void, string] {.gcsafe.}
```

**Button format:** `seq[seq[(label, callback_data)]]`

```nim
# Two rows of buttons
let buttons = @[
  @[("Yes", "yes"), ("No", "no")],
  @[("Cancel", "cancel")]
]
```

#### `editKeyboard`

Edit a message's inline keyboard.

```nim
proc(userId: UserId; msgId, text: string;
     buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.}
```

#### `setMessageReaction`

Add a reaction to a message.

```nim
proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.}
```

---

## OutboundChannelPorts

Container for all channel ports.

```nim
type
  OutboundChannelPorts* = object
    telegram*: OutboundChannelPort
    discord*:  OutboundChannelPort
    wecom*:   OutboundChannelPort
    wechat*:  OutboundChannelPort
    qq*:      OutboundChannelPort
    feishu*:  OutboundChannelPort
    slack*:   OutboundChannelPort
    whatsapp*: OutboundChannelPort
    signal*:  OutboundChannelPort
    dingtalk*: OutboundChannelPort
    matrix*:  OutboundChannelPort
    email*:   OutboundChannelPort
    cli*:     OutboundChannelPort
```

---

## Pure Helpers

### `filterInbound`

Filter messages for a specific user.

```nim
func filterInbound*(userId: UserId; msgs: seq[InboundMessage]): seq[InboundMessage]
```

**Usage:**

```nim
# All messages
let all = channel.receive().get()

# Filter for specific user
let userMsgs = all |>-> filterInbound(userId)
```

**Pipeline operator:** Designed for `|>->` pipeops.

---

### `countInbound`

Count inbound messages.

```nim
func countInbound*(msgs: seq[InboundMessage]): int
```

**Usage:**

```nim
let msgs = channel.receive().get()
let count = msgs |> countInbound
```

---

### `validateOutbound`

Validate an outbound message before sending.

```nim
func validateOutbound*(msg: OutboundMessage): Result[OutboundMessage, string]
```

**Validation:** Checks that `text` is non-empty.

**Usage:**

```nim
let msg = OutboundMessage(...)
msg.validateOutbound >>= channel.send
```

**Pipeline operator:** Designed for `>>=` pipeops.

---

## InboundMessage

Message received from a user.

```nim
type
  InboundMessage* = object
    userId*:    UserId       ## User who sent the message
    channelId*: string      ## Channel message ID
    text*:      string      ## Message content
    mediaUrl*:  string      ## non-empty when attachment exists
    channel*:   ChannelKind ## Source channel
```

---

## OutboundMessage

Message to send to a user.

```nim
type
  OutboundMessage* = object
    userId*:    UserId       ## Target user
    text*:      string        ## Message text
    replyTo*:   string        ## Message to reply to
    channel*:   ChannelKind   ## Target channel
    streamId*:  string        ## Streaming turn ID
    isPartial*: bool          ## Partial streaming edit
    mediaUrl*:  string        ## Media URL
    keyboard*:  seq[seq[(string, string)]]  ## Inline buttons
```

---

## Channel Adapters

### Telegram

Located in `src/donkey/adapters/channel/telegram.nim`

**Features:**
- Send/receive messages
- Inline keyboards
- Message editing
- Reactions

**Configuration:**

```toml
[telegram]
enabled = true
bot_token = "YOUR_TOKEN"
```

---

### Discord

Located in `src/donkey/adapters/channel/discord.nim`

**Features:**
- Send/receive messages
- Embeds
- Components
- Slash commands

**Configuration:**

```toml
[discord]
enabled = true
bot_token = "YOUR_TOKEN"
```

---

### Slack

Located in `src/donkey/adapters/channel/slack.nim`

**Features:**
- Send/receive messages
- Interactive components
- Block Kit

**Configuration:**

```toml
[slack]
enabled = true
bot_token = "xoxb-..."
signing_secret = "..."
```

---

### All Supported Channels

The runtime projects outbound behavior through a shared capability matrix owned by
`core/outbound/outbound.nim`.

| Channel | Implemented | Editable UI | Stream updates | Components | Reactions |
|---------|-------------|-------------|----------------|------------|-----------|
| Telegram | yes | yes | yes | yes | yes |
| Discord | yes | yes | yes | yes | yes |
| Slack | yes | no | no | no | no |
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

## Usage Examples

### Send a Message

```nim
import donkey/domain/message
import donkey/adapters/channel/telegram

let adapter = newTelegramAdapter(config)
let msg = OutboundMessage(
  userId: UserId("user_123"),
  text: "Hello!",
  channel: ckTelegram
)

let result = adapter.send(msg)
if result.isErr:
  echo "Failed: ", result.error
```

### Send with Keyboard

```nim
let buttons = @[
  @[("Option A", "choice_a"), ("Option B", "choice_b")],
  @[("Cancel", "cancel")]
]

let result = adapter.sendKeyboard(
  userId = UserId("user_123"),
  text = "Choose:",
  buttons = buttons
)
```

### Receive Messages

```nim
var adapter = newTelegramAdapter(config)
let messages = adapter.receive()

for msg in messages:
  echo "From: ", msg.userId
  echo "Text: ", msg.text
```

### Filter and Send

```nim
import donkey/core/pipeops

# Receive and filter
let msgs = adapter.receive() |>> filterInbound(UserId("user_123"))

# Validate and send
for msg in msgs:
  OutboundMessage(text: "Echo: " & msg.text, channel: msg.channel)
    .validateOutbound
    >>= adapter.send
```

---

## Error Handling

All channel operations return `Result`:

```nim
proc send*(port: ChannelPort; msg: OutboundMessage): Result[void, string]
```

**Success:**

```nim
let result = channel.send(msg)
if result.isOk:
  echo "Sent successfully"
```

**Failure:**

```nim
let result = channel.send(msg)
if result.isErr:
  echo "Failed: ", result.error
```

---

## Related

- [Configuration Reference](configuration.md)
- [Core Types Reference](core_types.md)
