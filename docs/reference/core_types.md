# Core Types API Reference
Complete reference for core domain types

## Overview

Core types are the foundational data structures used throughout Donkey. They have no external dependencies and are used across all layers of the architecture.

---

## `core/types.nim`

### Distinct Type Aliases

#### `UserId`

A unique identifier for a user.

```nim
type
  UserId* = distinct string
```

**Usage:**

```nim
let userId = UserId("user_123")
echo $userId  # "user_123"
```

**String operations are inherited from `string`:**

```nim
let id: UserId = "abc".UserId
let str: string = $id  # "abc"
```

#### `SessionId`

A unique identifier for a session.

```nim
type
  SessionId* = distinct string
```

**Usage:**

```nim
let sessionId = SessionId("session_456")
echo $sessionId  # "session_456"
```

---

### `ChannelKind`

Enumeration of supported messaging channels.

```nim
type
  ChannelKind* = enum
    ckTelegram   ## Telegram Bot API
    ckDiscord    ## Discord WebSocket
    ckWeCom      ## WeChat Work
    ckWeChat     ## WeChat
    ckQQ         ## QQ
    ckFeishu     ## Feishu/Lark
    ckSlack      ## Slack API
    ckWhatsApp   ## WhatsApp
    ckSignal     ## Signal
    ckDingTalk    ## DingTalk
    ckMatrix     ## Matrix
    ckEmail      ## Email
    ckCli        ## Command-line interface
```

**String representation:**

```nim
func `$`*(k: ChannelKind): string
```

| Variant | String |
|---------|--------|
| `ckTelegram` | `"telegram"` |
| `ckDiscord` | `"discord"` |
| `ckWeCom` | `"wecom"` |
| `ckWeChat` | `"wechat"` |
| `ckQQ` | `"qq"` |
| `ckFeishu` | `"feishu"` |
| `ckSlack` | `"slack"` |
| `ckWhatsApp` | `"whatsapp"` |
| `ckSignal` | `"signal"` |
| `ckDingTalk` | `"dingtalk"` |
| `ckMatrix` | `"matrix"` |
| `ckEmail` | `"email"` |
| `ckCli` | `"cli"` |

**Example:**

```nim
let channel: ChannelKind = ckTelegram
echo $channel  # "telegram"
```

---

### `LogLevel`

Logging verbosity levels.

```nim
type
  LogLevel* = enum
    lvlDebug  ## Detailed debug information
    lvlInfo   ## General information
    lvlWarn   ## Warning messages
    lvlError  ## Error messages
    lvlFatal  ## Fatal errors
```

**String representation:**

```nim
func `$`*(l: LogLevel): string
```

| Variant | String |
|---------|--------|
| `lvlDebug` | `"debug"` |
| `lvlInfo` | `"info"` |
| `lvlWarn` | `"warn"` |
| `lvlError` | `"error"` |
| `lvlFatal` | `"fatal"` |

**Parsing from string:**

```nim
func parseLogLevel*(s: string): LogLevel
```

Unknown strings default to `lvlInfo` (never crashes on bad config).

```nim
let level = parseLogLevel("debug")  # lvlDebug
let default = parseLogLevel("invalid")  # lvlInfo
```

---

## `domain/message.nim`

### Conversation Roles

Constants for message roles:

```nim
const
  roleUser*      = "user"       ## User message
  roleAssistant* = "assistant"   ## AI response
  roleSystem*    = "system"     ## System prompt
```

---

### `ToolResultKind`

Result type for tool execution.

```nim
type
  ToolResultKind* = enum
    trkOutput             ## Successful output
    trkOperationalError   ## Execution error
```

---

### `ChatMessage`

A single message in a conversation.

```nim
type
  ChatMessage* = object
    role*:       string                    ## user, assistant, or system
    text*:       string                    ## Message content
    imageUrl*:   string                   ## non-empty when message carries an image
    toolCalls*:  seq[ToolCallRequest]     ## non-empty: assistant issued pending calls
    toolCallId*: string                   ## non-empty: this message is a tool result
```

**Field details:**

| Field | Type | Description |
|-------|------|-------------|
| `role` | `string` | One of: `roleUser`, `roleAssistant`, `roleSystem` |
| `text` | `string` | Message text content |
| `imageUrl` | `string` | Image URL when message has an attachment |
| `toolCalls` | `seq[ToolCallRequest]` | Tool calls issued by assistant |
| `toolCallId` | `string` | Set when this message is a tool result |

**Creating messages:**

```nim
let msg = ChatMessage(
  role: roleUser,
  text: "Hello, world!"
)
```

---

### `ConversationHistory`

A sequence of chat messages.

```nim
type
  ConversationHistory* = seq[ChatMessage]
```

**Helpers:**

```nim
func newHistory*(): ConversationHistory = @[]

func addUser*(h: var ConversationHistory; text: string)
func addUserWithImage*(h: var ConversationHistory; text, imageUrl: string)
func addAssistant*(h: var ConversationHistory; text: string)
func addSystem*(h: var ConversationHistory; text: string)
func addToolResult*(h: var ConversationHistory; callId, output: string)
```

**Example:**

```nim
var history = newHistory()
history.addUser("Hello!")
history.addAssistant("Hi there!")
history.addToolResult("call_1", "Result: 42")
```

---

### `InboundMessage`

Message received from a user via a channel.

```nim
type
  InboundMessage* = object
    userId*:    UserId       ## User who sent the message
    channelId*: string        ## Channel-specific message ID
    text*:      string        ## Message content
    mediaUrl*:  string        ## non-empty when message has attachment
    channel*:   ChannelKind   ## Source channel
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `userId` | `UserId` | User identifier |
| `channelId` | `string` | Channel message ID (for ack/dedup) |
| `text` | `string` | Message text |
| `mediaUrl` | `string` | Attached media URL |
| `channel` | `ChannelKind` | Source channel |

**Example:**

```nim
let inbound = InboundMessage(
  userId: UserId("user_123"),
  channelId: "msg_456",
  text: "Hello!",
  channel: ckTelegram
)
```

---

### `OutboundMessage`

Message to send to a user via a channel.

```nim
type
  OutboundMessage* = object
    userId*:    UserId       ## Target user
    text*:      string        ## Message text
    replyTo*:   string        ## Channel message ID to reply to
    channel*:   ChannelKind   ## Target channel
    streamId*:  string        ## non-empty for streaming turns
    isPartial*: bool          ## true for streaming partial edits
    mediaUrl*:  string        ## non-empty → send as photo/document
    keyboard*:  seq[seq[(string, string)]]  ## Inline keyboard buttons
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `userId` | `UserId` | Target user |
| `text` | `string` | Message text |
| `replyTo` | `string` | Message ID to reply to |
| `channel` | `ChannelKind` | Target channel |
| `streamId` | `string` | Streaming turn identifier |
| `isPartial` | `bool` | True for partial streaming edits |
| `mediaUrl` | `string` | Media URL if sending photo/document |
| `keyboard` | `seq[seq[(string, string)]]` | Inline keyboard buttons |

**Inline keyboard example:**

```nim
let outbound = OutboundMessage(
  userId: UserId("user_123"),
  text: "Choose an option:",
  channel: ckTelegram,
  keyboard: @[
    @[("Option 1", "callback:1"), ("Option 2", "callback:2")],
    @[("Cancel", "callback:cancel")]
  ]
)
```

---

### `ToolDescription`

Description of an available tool.

```nim
type
  ToolDescription* = object
    name*:        string  ## Tool name
    description*: string  ## Human-readable description
    schemaJson*:  string  ## JSON schema for tool input
```

**Example:**

```nim
let tool = ToolDescription(
  name: "bash",
  description: "Execute a bash command",
  schemaJson: """{"type": "object", "properties": {"command": {"type": "string"}}}"""
)
```

---

### `ToolCallRequest`

A request to execute a tool.

```nim
type
  ToolCallRequest* = object
    id*:        string  ## Unique call identifier
    name*:      string  ## Tool name to execute
    inputJson*: string  ## JSON-encoded input arguments
```

**Example:**

```nim
let call = ToolCallRequest(
  id: "call_abc123",
  name: "bash",
  inputJson: """{"command": "ls -la"}"""
)
```

---

### `CompletionRequest`

Request to the LLM for completion.

```nim
type
  CompletionRequest* = object
    system*:    string                    ## System prompt
    messages*:  seq[ChatMessage]        ## Conversation history
    maxTokens*: int                       ## 0 = provider default
    tools*:     seq[ToolDescription]      ## Available tools
```

**Example:**

```nim
let req = CompletionRequest(
  system: "You are a helpful assistant.",
  messages: history,
  maxTokens: 8192,
  tools: @[bashTool, fetchTool]
)
```

---

### `CompletionResponse`

Response from the LLM.

```nim
type
  CompletionResponse* = object
    text*:         string                  ## Generated text
    inputTokens*:  int                    ## Tokens used for input
    outputTokens*: int                    ## Tokens generated
    toolCalls*:    seq[ToolCallRequest]  ## Tool calls to execute
```

**Example:**

```nim
let resp = CompletionResponse(
  text: "I'll help you with that.",
  inputTokens: 150,
  outputTokens: 25,
  toolCalls: @[]
)
```

---

## Usage Examples

### Basic Message Flow

```nim
import donkey/domain/message
import donkey/core/types

# Create inbound message
let inbound = InboundMessage(
  userId: UserId("user_123"),
  channelId: "msg_456",
  text: "What is 2 + 2?",
  channel: ckTelegram
)

# Build conversation history
var history = newHistory()
history.addSystem("You are a calculator assistant.")
history.addUser("What is 2 + 2?")

# Create completion request
let req = CompletionRequest(
  system: "You are a calculator.",
  messages: history,
  maxTokens: 100,
  tools: @[]
)

# Process response
let resp = CompletionResponse(
  text: "2 + 2 = 4",
  inputTokens: 20,
  outputTokens: 5,
  toolCalls: @[]
)

# Create outbound message
let outbound = OutboundMessage(
  userId: inbound.userId,
  text: resp.text,
  channel: inbound.channel,
  replyTo: inbound.channelId
)
```

---

## Related

- [Commands System](../topics/commands.md)
- [Hooks System](../topics/hooks.md)
- [Memory System](../topics/memory.md)
