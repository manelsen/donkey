# Memory Port API Reference
Complete reference for the memory system

## Overview

The memory system provides persistent storage for user data using a two-tier architecture:

1. **F1: Workspace Memory (Markdown)** - Simple file-based storage
2. **F2+: Semantic Memory (PostgreSQL)** - Vector-based retrieval

**Architecture:** Memory adapters implement the MemoryPort or SemanticMemoryPort concepts.

---

## Paddock Layout

Each user has a paddock directory:

```
~/.donkey/paddocks/{user_id}/
├── USER.md          # User identity
├── PREFERENCES.md   # User preferences
├── MEMORY.md       # Episodic/semantic notes
├── CONTACTS.md      # Known people
├── SOLUTIONS.md     # Reusable solutions
└── sessions/
    └── {session_id}.md  # Session conversation logs
```

---

## MemoryPort Concept

Basic workspace memory interface.

```nim
type
  MemoryPort* = concept m
    m.hasProfile(UserId) is bool
    m.loadContext(UserId) is UserContext
    m.saveUserMd(UserId, string)
    m.appendMemory(UserId, string)
    m.savePreferences(UserId, string)
```

### Methods

| Method | Description |
|--------|-------------|
| `hasProfile(UserId)` | Check if user exists |
| `loadContext(UserId)` | Load all user documents |
| `saveUserMd(UserId, string)` | Save USER.md |
| `appendMemory(UserId, string)` | Append to MEMORY.md |
| `savePreferences(UserId, string)` | Save PREFERENCES.md |

---

## SemanticMemoryPort Concept

Extended memory with vector search.

```nim
type
  SemanticMemoryPort* = concept m
    m.hasProfile(UserId) is bool
    m.loadContext(UserId) is UserContext
    m.saveUserMd(UserId, string)
    m.appendMemory(UserId, string)
    m.savePreferences(UserId, string)
    m.search(UserId, string, int) is seq[MemoryHit]
```

### Additional Methods

| Method | Description |
|--------|-------------|
| `search(UserId, query, k)` | Semantic search, returns top k hits |

---

## UserContext

Aggregated context loaded from a paddock.

```nim
type
  UserContext* = object
    userId*:        UserId   ## User identifier
    userMd*:        string   ## USER.md contents
    memoryMd*:      string   ## MEMORY.md contents
    preferencesMd*: string   ## PREFERENCES.md contents
```

---

## MemoryHit

Single result from semantic search.

```nim
type
  MemoryHit* = object
    content*: string   ## Memory text
    score*:   float32 ## Cosine similarity [0, 1]
    kind*:    string  ## Node kind: "memory", "fact", "user_profile"
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `content` | `string` | Memory text |
| `score` | `float32` | Cosine similarity (higher = more similar) |
| `kind` | `string` | Node kind |

---

## MemoryRuntimePort

Runtime interface for memory operations.

```nim
type
  MemoryRuntimePort* = object
    hasProfile*:      proc(userId: UserId): bool
    loadContext*:     proc(userId: UserId): UserContext
    saveUserMd*:      proc(userId: UserId; content: string)
    appendMemory*:    proc(userId: UserId; text: string)
    savePreferences*: proc(userId: UserId; content: string)
    clearMemory*:     proc(userId: UserId)
    saveSession*:     proc(userId: UserId; sessionId: string; history: ConversationHistory)
    saveIdentity*:    proc(userId: UserId; traits: PersonalityTraits; name: string)
    loadIdentity*:    proc(userId: UserId): (string, PersonalityTraits)
    paddockDir*:      proc(userId: UserId): string
    scheduleReminder*:  proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string
    loadDueReminders*: proc(): seq[JsonNode]
    deleteReminder*:  proc(userId: UserId; reminderId: string)
```

---

## MdFileAdapter

Markdown file-based workspace memory.

**Location:** `src/donkey/adapters/memory/md_file.nim`

### Creating an Adapter

```nim
import donkey/adapters/memory/md_file

let memory = newMdFileAdapter(paddocksDir = "~/.donkey/paddocks")
```

### Methods

```nim
# Check if user exists
if memory.hasProfile(userId):
  echo "User exists"

# Load all context
let ctx = memory.loadContext(userId)
echo ctx.userMd
echo ctx.memoryMd

# Save user document
memory.saveUserMd(userId, "# User Info\n- Name: John")

# Append to memory
memory.appendMemory(userId, "## New Fact\n- User prefers dark mode")

# Save preferences
memory.savePreferences(userId, "# Preferences\n- Theme: dark")
```

---

## PostgresMemoryAdapter

PostgreSQL-based semantic memory.

**Location:** `src/donkey/adapters/memory/postgres.nim`

### Configuration

```toml
[memory.postgres]
enabled = true
host = "localhost"
port = 5432
database = "donkey"
user = "postgres"
password = ""
```

### Schema

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE memories (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX ON memories USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

### Creating an Adapter

```nim
import donkey/adapters/memory/postgres

let semantic = newPostgresMemoryAdapter(
  connectionString = "postgres://user:pass@localhost/donkey"
)
```

### Semantic Search

```nim
# Search memories
let hits = semantic.search(
  userId = userId,
  query = "What does the user prefer?",
  k = 5
)

for hit in hits:
  echo hit.content
  echo "Score: ", hit.score
  echo "Kind: ", hit.kind
```

---

## Bootstrap Helpers

### `bootstrapUserMd`

Generate initial USER.md content.

```nim
proc bootstrapUserMd*(
  name: string;
  callMe: string;
  timezone: string;
  language: string
): string
```

**Example:**

```nim
let userContent = bootstrapUserMd(
  name = "John Doe",
  callMe = "John",
  timezone = "UTC",
  language = "en"
)

memory.saveUserMd(userId, userContent)
```

**Output:**

```markdown
---
summary: John Doe — onboarded via Donkey bootstrapping.
read_when: every conversation
---

# John Doe

**Preferred name:** John
**Timezone:** UTC
**Language:** en
```

---

## Usage Examples

### Load User Context

```nim
import donkey/adapters/memory/md_file

let memory = newMdFileAdapter("~/.donkey/paddocks")

# Load all user data
let ctx = memory.loadContext(userId)

# Check what's available
if ctx.userMd.len > 0:
  echo "User profile exists"
if ctx.memoryMd.len > 0:
  echo "User has memories"
if ctx.preferencesMd.len > 0:
  echo "User has preferences"
```

### Append Memories

```nim
# Append new information to memory
memory.appendMemory(userId, """
## New Fact
- User mentioned they prefer concise responses
- Works at Acme Corp
""")
```

### Semantic Retrieval

```nim
import donkey/adapters/memory/postgres

let semantic = newPostgresMemoryAdapter("postgres://...")

# Find relevant memories
let hits = semantic.search(
  userId = UserId("user_123"),
  query = "programming languages",
  k = 3
)

# Combine with context
let context = memory.loadContext(userId)
let contextText = """
User Profile:
{context.userMd}

Memories:
{context.memoryMd}

Relevant Facts:
{hits.mapIt(it.content).join("\n\n")}
"""
```

### Save Session History

```nim
# Save conversation history
memory.saveSession(
  userId = userId,
  sessionId = sessionId,
  history = @[
    ChatMessage(role: roleUser, text: "Hello"),
    ChatMessage(role: roleAssistant, text: "Hi!")
  ]
)
```

### Reminders

```nim
# Schedule a reminder
let reminderId = memory.scheduleReminder(
  userId = userId,
  channel = "telegram",
  scheduledAt = 1704067200,  # Unix timestamp
  message = "Check in with user"
)

# Load due reminders
let reminders = memory.loadDueReminders()
for reminder in reminders:
  echo reminder["message"]

# Delete a reminder
memory.deleteReminder(userId, reminderId)
```

---

## Context Injection

Combine workspace and semantic memory for LLM context:

```nim
proc buildContext*(
  memory: MdFileAdapter;
  semantic: SemanticMemoryPort;
  userId: UserId;
  query: string
): string =
  # Load workspace memory
  let ctx = memory.loadContext(userId)
  
  # Semantic search
  let hits = semantic.search(userId, query, k = 5)
  
  # Build context string
  result = "User Information:\n"
  if ctx.preferencesMd.len > 0:
    result &= ctx.preferencesMd & "\n\n"
  if ctx.memoryMd.len > 0:
    result &= "Memories:\n" & ctx.memoryMd & "\n\n"
  if hits.len > 0:
    result &= "Relevant Facts:\n"
    for hit in hits:
      result &= "- " & hit.content & "\n"
```

---

## Best Practices

### 1. Load Context Once Per Session

```nim
# Good: Load once
let ctx = memory.loadContext(userId)
useContext(ctx.userMd)
useContext(ctx.memoryMd)

# Bad: Multiple loads
useContext(memory.loadContext(userId).userMd)
useContext(memory.loadContext(userId).memoryMd)
```

### 2. Batch Semantic Updates

```nim
# Good: Batch appends
memory.appendMemory(userId, "## Session Notes\n- Topic A\n- Topic B")

# Bad: Individual appends
memory.appendMemory(userId, "## Session Notes\n- Topic A")
memory.appendMemory(userId, "- Topic B")
```

### 3. Use Appropriate Search

```nim
# Good: Specific queries
let hits = semantic.search(userId, "user's Python projects", k = 5)

# Bad: Too broad
let hits = semantic.search(userId, "everything", k = 50)
```

---

## Related

- [Memory System](../topics/memory.md)
- [Configuration Reference](configuration.md)
