# Memory System
Persistent storage and semantic retrieval

## Overview

Donkey's memory system uses a two-tier architecture:

```
┌─────────────────────────────────────────┐
│        F1: Workspace Memory              │
│      (Markdown paddocks per user)       │
├─────────────────────────────────────────┤
│        F2+: Semantic Memory              │
│      (PostgreSQL + pgvector)            │
└─────────────────────────────────────────┘
```

## F1: Workspace Memory

Workspace memory uses markdown files stored in paddocks.

### Directory Structure

```
~/.donkey/paddocks/<user_id>/
├── USER.md          # User identity
├── MEMORY.md        # Persistent memories
├── PREFERENCES.md   # User preferences
└── NOTES.md        # Additional notes
```

### USER.md

```markdown
# User Identity

- name: John Doe
- language: en
- timezone: UTC
- created: 2024-01-15
- last_seen: 2024-03-28
```

### MEMORY.md

```markdown
# Memories

## Important Facts
- User prefers dark mode
- Works at Acme Corp
- Interested in Nim programming
- Dog owner

## Preferences
- Prefers concise responses
- Morning person
- Drinks coffee

## Projects
- Working on a Discord bot in Nim
- Learning Rust
```

### PREFERENCES.md

```markdown
# Preferences

## Model Preferences
- default_model: claude-sonnet-4
- temperature: 0.7

## Interface Preferences
- theme: dark
- verbose: false
- thinking_level: medium

## Tool Preferences
- allow_shell: true
- allow_git: true
- allow_fetch: false
```

## F2: Semantic Memory

For vector-based retrieval, Donkey supports PostgreSQL with pgvector.

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

CREATE INDEX idx_memories_user_id ON memories(user_id);
```

### Configuration

```toml
[memory.postgres]
enabled = false
host = "localhost"
port = 5432
database = "donkey"
user = "postgres"
password = ""

# Embedding configuration
[memory.embedding]
provider = "openai"
model = "text-embedding-3-small"
dimension = 1536
```

## Memory Port Interface

```nim
type
  MemoryPort* = concept c
    c.readUserDoc(userId, docName) is string
    c.writeUserDoc(userId, docName, content) is bool
    c.listDocs(userId) is seq[string]
    c.userExists(userId) is bool
    c.createUser(userId) is bool
  
  SemanticMemoryPort* = concept c
    c.search(userId, query, k) is seq[MemoryHit]
    c.add(userId, document, metadata) is bool
    c.delete(id) is bool
    c.getByUserId(userId) is seq[MemoryHit]
```

## Adapters

### MdFileAdapter

Workspace memory adapter using markdown files:

```nim
import donkey/adapters/memory/md_file

let memory = newMdFileAdapter("~/.donkey/paddocks")

# Read user document
let userDoc = memory.readUserDoc(userId, "MEMORY.md")

# Write user document
discard memory.writeUserDoc(userId, "MEMORY.md", updatedContent)

# List user's documents
let docs = memory.listDocs(userId)
# @["USER.md", "MEMORY.md", "PREFERENCES.md", "NOTES.md"]
```

### PostgresMemoryAdapter

Semantic memory adapter using PostgreSQL:

```nim
import donkey/adapters/memory/postgres

let semantic = newPostgresMemoryAdapter(
  connectionString: "postgres://user:pass@localhost/donkey"
)

# Search memories
let hits = semantic.search(
  userId = userId,
  query = "What does the user prefer?",
  k = 5
)

for hit in hits:
  echo hit.content
  echo "Score: ", hit.score

# Add memory
discard semantic.add(
  userId = userId,
  document = "User prefers dark mode",
  metadata = %*{"category": "preferences"}
)
```

## Usage Patterns

### User Identification

```nim
proc getOrCreateUser*(memory: MdFileAdapter; userId: UserId): UserDoc =
  if memory.userExists(userId):
    return memory.readUserDoc(userId, "USER.md")
  
  # Create new user
  let doc = UserDoc(id: userId, name: "", language: "en")
  memory.writeUserDoc(userId, "USER.md", doc.toMarkdown())
  return doc
```

### Context Retrieval

```nim
proc retrieveContext*(memory: MdFileAdapter; semantic: SemanticMemoryPort; userId: UserId; query: string): string =
  # Get preferences
  let prefs = memory.readUserDoc(userId, "PREFERENCES.md")
  
  # Get semantic memories
  let hits = semantic.search(userId, query, k = 3)
  let semanticContext = hits.mapIt(it.content).join("\n\n")
  
  # Combine
  result = "User Preferences:\n" & prefs & "\n\nRelevant Memories:\n" & semanticContext
```

## Memory Hooks

Donkey includes hooks for automatic memory management:

### Memory Capture Hook

Captures conversation to memory:

```toml
[hooks.memory_capture]
enabled = true
phase = "post_response"
params.capture_user = true
params.capture_assistant = true
params.auto_summarize = true
params.summarize_after = 50
```

### RAG Context Hook

Retrieves relevant context before LLM call:

```toml
[hooks.rag_context]
enabled = true
phase = "pre_llm"
params.max_hits = 5
params.min_score = 0.7
params.include_metadata = true
```

## Best Practices

### 1. Keep Documents Focused

Each document should have a clear purpose:

```
GOOD:
├── USER.md       # Identity only
├── MEMORY.md     # Memories only
└── NOTES.md      # Notes only

BAD:
└── EVERYTHING.md # Mixed content
```

### 2. Update Memories Regularly

```nim
proc updateMemory*(memory: MdFileAdapter; userId: UserId; fact: string) =
  let current = memory.readUserDoc(userId, "MEMORY.md")
  let updated = current & "\n- " & fact & " (" & $now() & ")"
  memory.writeUserDoc(userId, "MEMORY.md", updated)
```

### 3. Use Semantic Search Wisely

```nim
# Good: Specific queries
let hits = semantic.search(userId, "user's programming languages", k = 5)

# Bad: Too broad
let hits = semantic.search(userId, "everything about user", k = 50)
```

## Related

- [Hooks System](hooks.md)
- [Configuration Reference](../reference/configuration.md)
