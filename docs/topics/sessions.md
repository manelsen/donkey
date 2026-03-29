# Sessions
Session management and lifecycle

## Overview

A session represents a conversation thread between a user and the AI agent. Sessions persist conversation history and enable context-aware responses.

---

## Session Structure

```nim
type
  Session* = object
    id*:        SessionId     ## Unique session identifier
    userId*:    UserId       ## Owner user
    channel*:   ChannelKind  ## Source channel
    messages*:   ConversationHistory  ## Message history
    createdAt*:  DateTime    ## Creation timestamp
    model*:      string      ## Current model
    contextTokens*: int      ## Current context size
```

---

## Session Lifecycle

```
┌─────────────┐
│  New User   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Create      │
│ Session     │────── On /reset ─────► Reset History
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Active    │────── On /compact ───► Compact Context
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Idle      │────── On /new ───────► New Session
│  (timeout)  │
└─────────────┘
```

---

## Session Commands

| Command | Action |
|---------|--------|
| `/reset` | Clear message history |
| `/compact` | Compact context window |
| `/new` | Start fresh session |
| `/restart` | Restart session |

---

## Session Management

### Create Session

```nim
let session = Session(
  id: SessionId("sess_123"),
  userId: UserId("user_456"),
  channel: ckTelegram,
  messages: @[],
  createdAt: now()
)
```

### Add Message

```nim
session.messages.addUser("Hello!")
session.messages.addAssistant("Hi there!")
```

### Compact Context

```nim
import donkey/domain/compaction_pure

let compacted = compactHistory(session.messages, maxTokens = 8000)
session.messages = compacted
```

---

## Session Storage

Sessions are stored in paddocks:

```
~/.donkey/paddocks/{user_id}/sessions/{session_id}.md
```

### Session File Format

```markdown
# Session {session_id}

## Meta
- Created: 2024-03-28
- Channel: telegram
- Model: claude-sonnet-4

## History

### User
Hello!

### Assistant
Hi there! How can I help you?

### User
I need help with Nim.
```

---

## Related

- [Commands](commands.md)
- [Memory](memory.md)
