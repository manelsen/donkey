# Donkey Documentation Plan
## Comprehensive Didactic Documentation Inspired by Discord.PY

**Version:** 1.0  
**Created:** 2026-03-28  
**Inspired by:** Discord.PY Documentation

---

## 1. Vision & Philosophy

### 1.1 Documentation Goals

Our documentation follows Discord.PY's proven formula:
- **Beginner-friendly**: Zero-to-production in under 10 minutes
- **Complete reference**: Every API, type, and function documented
- **Practical examples**: Working code for every feature
- **Deep dives**: Architectural explanations for advanced users

### 1.2 Target Audience

| Audience | Primary Needs | Documentation Focus |
|----------|---------------|---------------------|
| New Users | Quick start, basic concepts | Quickstart, Installation |
| Developers | API reference, patterns | API Reference, Examples |
| Contributors | Architecture, internals | Architecture, Contributing |
| DevOps | Deployment, configuration | Deployment, Security |

---

## 2. Documentation Structure

### 2.1 Top-Level Organization

```
docs/
├── index.md                    # Landing page
├── quickstart.md               # 5-minute quick start
├── getting_started/            # Beginner tutorials
├── guides/                    # Task-oriented guides
├── reference/                 # API documentation
├── topics/                   # Deep-dive articles
├── howto/                    # Common patterns
└── contribute/               # Contributor guide
```

### 2.2 Discord.PY-Inspired Structure

Following the Discord.PY model:

| Discord.PY Section | Donkey Equivalent |
|-------------------|-------------------|
| Introduction | Getting Started |
| Quickstart | Quickstart |
| FAQ | FAQ |
| API Reference | API Reference |
| ext/commands | Commands |
| ext/tasks | Background Tasks |
| Logging | Logging |
| Intents | Permissions & Access Control |
| Migrating | Changelog |

---

## 3. Document Specifications

### 3.1 Core Documents

#### 3.1.1 Landing Page (`index.md`)

```markdown
# Donkey
An AI agent daemon for multi-channel messaging

## Features
- 12+ channel integrations (Telegram, Discord, Slack...)
- Multi-provider LLM support (Anthropic, OpenAI, Gemini...)
- Hooks system for message flow interception
- Memory persistence with RAG support
- Hexagonal architecture

## Installation
```bash
nim install donkey
```

## Quick Start
```bash
donkey --config ~/.config/donkey/donkey.toml
```

[Get Started](getting_started/installation.md) · [Quickstart](quickstart.md) · [API Reference](reference/README.md)
```

**Priority:** P0  
**Estimated Size:** ~50 lines

#### 3.1.2 Quickstart (`quickstart.md`)

**Goal:** User sends first message in 5 minutes

```markdown
# Quickstart
Get Donkey running in 5 minutes

## Prerequisites
- Nim 2.0+
- Telegram bot token (or Discord/other channel)
- LLM API key (OpenAI/Anthropic/etc)

## 1. Installation

```bash
# Clone the repository
git clone https://github.com/manelsen/donkey.git
cd donkey

# Build
nim c src/donkey

# Install
mkdir -p ~/.config/donkey
cp deploy/donkey.toml.example ~/.config/donkey/donkey.toml
```

## 2. Configuration

Edit `~/.config/donkey/donkey.toml`:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"

[telegram]
enabled = true
bot_token = "YOUR_BOT_TOKEN"

[providers.anthropic]
enabled = true
api_key = "YOUR_API_KEY"
```

## 3. Run

```bash
./donkey --config ~/.config/donkey/donkey.toml
```

Send `/start` to your Telegram bot!

## What's Next?

- [Basic Concepts](getting_started/basic_concepts.md)
- [Your First Command](guides/first_command.md)
- [Configuration Reference](reference/configuration.md)
```

**Priority:** P0  
**Estimated Size:** ~100 lines

#### 3.1.3 Basic Concepts (`getting_started/basic_concepts.md`)

**Goal:** Explain architecture without overwhelming

```markdown
# Basic Concepts
Understanding Donkey's architecture

## The Hexagonal Architecture

Donkey uses hexagonal (ports & adapters) architecture:

```
┌─────────────────────────────────────────┐
│              Channels                    │
│  (Telegram, Discord, Slack...)         │
└──────────────────┬──────────────────────┘
                   │ InboundMessage
                   ▼
┌─────────────────────────────────────────┐
│              Ports                       │
│  ChannelPort, ProviderPort, HookPort... │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Core                        │
│  Session, Orchestrator, Tool Loop       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│              Adapters                    │
│  LLM Providers, Memory, Tools           │
└─────────────────────────────────────────┘
```

## Key Concepts

### Session
A session represents a conversation with a user. Each user has one or more sessions, one per channel.

### Orchestrator
The orchestrator manages the message flow: receives messages, calls the LLM, executes tools, sends responses.

### Hooks
Hooks intercept the message flow at various phases:
- `hpPreLlm` - Before LLM call
- `hpPostLlm` - After LLM response
- `hpPreTool` - Before tool execution
- `hpPostTool` - After tool result
- `hpPostResponse` - Before sending response

### Memory
Memory persistence uses a paddock system:
- `~/.donkey/paddocks/<user_id>/USER.md` - User identity
- `~/.donkey/paddocks/<user_id>/MEMORY.md` - Persistent memories
- `~/.donkey/paddocks/<user_id>/PREFERENCES.md` - User preferences

## Next Steps

- [Commands System](topics/commands.md)
- [Hooks System](topics/hooks.md)
- [Memory System](topics/memory.md)
```

**Priority:** P0  
**Estimated Size:** ~150 lines

### 3.1.4 Installation Guide (`getting_started/installation.md`)

```markdown
# Installation
How to install and configure Donkey

## Requirements

### System Requirements
- Nim 2.0 or higher
- 512MB RAM minimum
- 1GB disk space

### Optional Dependencies
- **PostgreSQL** (for semantic memory): `libpq-dev`
- **SQLite** (for local storage): `libsqlite3-dev`
- **Docker** (for sandboxed shell execution)

## Installation Methods

### Method 1: Build from Source

```bash
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

### Method 2: Using Nimble

```bash
nimble install donkey
```

### Method 3: Pre-built Binary

Download from releases page.

## Configuration File

Create `~/.config/donkey/donkey.toml`:

```toml
[donkey]
home = "~/.donkey"
paddocks = "~/.donkey/paddocks"
log_level = "info"

[telegram]
enabled = true
bot_token = "YOUR_TOKEN"

[discord]
enabled = false

[providers.anthropic]
enabled = true
api_key = "YOUR_KEY"
model = "claude-sonnet-4-20250514"

[providers.openai]
enabled = false
api_key = "YOUR_KEY"
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DONKEY_HOME` | Override home directory |
| `DONKEY_SECRETS_KEY` | Encryption key for secrets |

## Verifying Installation

```bash
./donkey --version
# Output: donkey 1.0.0

./donkey --help
# Shows available commands
```

## Next Steps

- [Quickstart](quickstart.md)
- [Configuration Reference](reference/configuration.md)
```

**Priority:** P0  
**Estimated Size:** ~150 lines

---

### 3.2 Topic Deep-Dives

#### 3.2.1 Commands System (`topics/commands.md`)

```markdown
# Commands System
Slash commands and message routing

## Command Structure

Donkey supports slash commands with semantic routing:

```
/command                    → Route decision
     │
     ├─► crLocal           → Handled locally (no LLM)
     ├─► crSessionTask      → Session task (reset, compact, etc)
     ├─► crUi               → Interactive UI (model selection)
     ├─► crStatus           → Status queries
     └─► crPing             → Ping/pong
```

## Available Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/start` | Start conversation | local |
| `/menu` | Show command menu | local |
| `/help` | Show help | local |
| `/reset` | Reset session | session |
| `/compact` | Compact context | session |
| `/models` | Switch model | ui |
| `/think` | Set thinking level | ui |
| `/memory` | Memory tools | local |

## Command Parsing

Commands are parsed in `core/commands/command_routing.nim`:

```nim
func parseCommandText*(text: string): CommandDecision =
  let cmd = stripBotMention(text.strip)
  case cmd
  of "/start": newCommandDecision(cmdStart)
  of "/reset": newCommandDecision(cmdReset)
  # ...
```

## Creating Custom Commands

Custom commands can be added by creating a new `CommandKind`:

```nim
# 1. Add to enum
CommandKind* = enum
  # ... existing
  cmdMyCustom

# 2. Add parsing
of "/mycustom": newCommandDecision(cmdMyCustom)

# 3. Add route
of cmdMyCustom: crSessionTask

# 4. Implement handler
```

## Command Catalog

The unified command catalog (`core/commands/command_catalog.nim`) provides:

```nim
const CommandCatalogItems*: seq[CommandMetadata] = @[
  CommandMetadata(
    name: "/mycommand",
    description: "Does something",
    category: ccTools,
    requiresArgs: false,
    route: crLocal
  ),
  # ...
]
```

## Related

- [Hooks System](hooks.md)
- [Session Management](sessions.md)
```

**Priority:** P1  
**Estimated Size:** ~200 lines

#### 3.2.2 Hooks System (`topics/hooks.md`)

```markdown
# Hooks System
Message flow interception and augmentation

## Overview

Hooks provide middleware-style interception of the message flow:

```
Message → hpPreLlm → LLM → hpPostLlm → Tool → hpPostTool → Response → hpPostResponse
```

## Hook Phases

| Phase | Description | Use Case |
|-------|-------------|----------|
| `hpPreLlm` | Before LLM call | Validation, context injection |
| `hpPostLlm` | After LLM response | Response modification |
| `hpPreTool` | Before tool execution | Permission checks |
| `hpPostTool` | After tool result | Result caching |
| `hpPostResponse` | Before sending | Final modifications |

## Hook Interface

```nim
type
  HookFn* = proc(ctx: HookContext): HookResult {.gcsafe.}
  
  HookContext* = object
    userId*: UserId
    sessionId*: SessionId
    message*: string
    history*: seq[ChatMessage]
    metadata*: StringTableRef
  
  HookResultKind* = enum
    hrkContinue    # Continue to next hook
    hrkModified    # Modified context
    hrkRejected    # Reject the message
  
  HookResult* = object
    case kind*: HookResultKind
    of hrkContinue, hrkModified:
      context*: HookContext
    of hrkRejected:
      errorMessage*: string
```

## Creating a Hook

### 1. Define the hook function

```nim
proc mySpamFilter*(ctx: HookContext): HookResult =
  if "spam" in ctx.message.toLower():
    return newHookResultRejected(ctx, "Spam detected")
  return newHookResultContinue(ctx)
```

### 2. Register with executor

```nim
var executor = newHookExecutor()
executor.registerHook(HookDefinition(
  name: "spam_filter",
  phase: hpPreLlm,
  handler: mySpamFilter
))
```

## Built-in Hooks

### RAG Context Hook
Injects relevant context from semantic memory:

```toml
[hooks.rag_context]
enabled = true
phase = "pre_llm"
max_hits = 5
similarity_threshold = 0.7
```

### Memory Capture Hook
Captures conversation to memory:

```toml
[hooks.memory_capture]
enabled = true
phase = "post_response"
```

### Context Injection Hook
Abstract hook for custom context injection:

```nim
let hookFn = makeContextInjectionHookFn(
  name = "custom_context",
  searchFn = mySearchFn
)
```

## Hook Configuration

Hooks are configured in `donkey.toml`:

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "spam_filter"
enabled = true
phase = "pre_llm"

[[hooks.definition]]
name = "rag_context"
enabled = true
phase = "pre_llm"
params.max_hits = 5
```

## Related

- [Commands System](commands.md)
- [Memory System](memory.md)
```

**Priority:** P1  
**Estimated Size:** ~250 lines

#### 3.2.3 Memory System (`topics/memory.md`)

```markdown
# Memory System
Persistent storage and semantic retrieval

## Architecture

Donkey's memory system has two tiers:

```
┌─────────────────────────────────────────┐
│           F1: Workspace Memory           │
│  (Markdown paddocks per user)           │
├─────────────────────────────────────────┤
│           F2+: Semantic Memory           │
│  (PostgreSQL + pgvector)                │
└─────────────────────────────────────────┘
```

## F1: Workspace Memory (Markdown Paddocks)

Each user has a paddock directory:

```
~/.donkey/paddocks/<user_id>/
├── USER.md          # User identity
├── MEMORY.md        # Persistent memories
├── PREFERENCES.md   # User settings
└── NOTES.md        # Additional notes
```

### File Structure

**USER.md:**
```markdown
# User Identity

- name: John Doe
- language: en
- timezone: UTC
- created: 2024-01-15
```

**MEMORY.md:**
```markdown
# Memories

## Important Facts
- User prefers dark mode
- Works at Acme Corp
- Interested in Nim programming

## Preferences
- Prefers concise responses
- Morning person
```

## F2: Semantic Memory (PostgreSQL)

For vector-based retrieval:

```toml
[memory.postgres]
enabled = true
host = "localhost"
port = 5432
database = "donkey"
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
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX ON memories USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

## Memory Port Interface

```nim
type
  MemoryPort* = concept c
    c.readUserDoc(string) is string
    c.writeUserDoc(string, string) is bool
    c.listDocs(string) is seq[string]
  
  SemanticMemoryPort* = concept c
    c.search(query: string, k: int) is seq[MemoryHit]
    c.add(document: string, metadata: Metadata) is bool
```

## Adapters

### MdFileAdapter (Workspace Memory)

```nim
let memory = MdFileAdapter(
  paddocksDir: "~/.donkey/paddocks"
)
let userDoc = memory.readUserDoc(userId, "MEMORY.md")
```

### PostgresMemoryAdapter (Semantic Memory)

```nim
let semantic = PostgresMemoryAdapter(
  connectionString: "postgres://..."
)
let hits = semantic.search(
  query = "What does the user prefer?",
  k = 5
)
```

## Related

- [Hooks System](hooks.md)
- [Configuration Reference](reference/configuration.md)
```

**Priority:** P1  
**Estimated Size:** ~250 lines

---

### 3.3 API Reference Structure

#### 3.3.1 API Reference Index (`reference/README.md`)

```markdown
# API Reference
Complete documentation for all public APIs

## Core Modules

### Ports
| Module | Description |
|--------|-------------|
| [hook](hook.md) | Hook system interface |
| [channel](channel.md) | Channel abstraction |
| [provider](provider.md) | LLM provider interface |
| [memory](memory.md) | Memory system interface |
| [tool](tool.md) | Tool abstraction |

### Core
| Module | Description |
|--------|-------------|
| [types](types.md) | Core types (UserId, SessionId...) |
| [session](session.md) | Session management |
| [orchestrator](orchestrator.md) | Message orchestration |

### Domain
| Module | Description |
|--------|-------------|
| [message](message.md) | Message types |
| [agent_message](agent_message.md) | Internal agent messages |

## Adapters

### Channels
- [Telegram](channels/telegram.md)
- [Discord](channels/discord.md)
- [Slack](channels/slack.md)

### Providers
- [Anthropic](providers/anthropic.md)
- [OpenAI](providers/openai.md)
- [OpenRouter](providers/openrouter.md)
- [Gemini](providers/gemini.md)

### Memory
- [MdFileAdapter](memory/mdfile.md)
- [PostgresMemoryAdapter](memory/postgres.md)
```

**Priority:** P0  
**Estimated Size:** ~100 lines

#### 3.3.2 Configuration Reference (`reference/configuration.md`)

```markdown
# Configuration Reference
Complete donkey.toml reference

## Top-Level `[donkey]`

```toml
[donkey]
home = "~/.donkey"           # Base directory
paddocks = "~/.donkey/paddocks"  # User workspaces
log_level = "info"           # debug|info|warn|error
log_file = ""                # Empty = stderr only
```

## Channel Configuration

### `[telegram]`

```toml
[telegram]
enabled = true
bot_token = "123456:ABC-DEF..."  # Required
allowlist = ["example.com"]       # Optional URL allowlist
```

### `[discord]`

```toml
[discord]
enabled = false
bot_token = ""
application_id = ""
guild_id = ""
```

## Provider Configuration

### `[providers.anthropic]`

```toml
[providers.anthropic]
enabled = true
api_key = "sk-ant-..."
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7
```

### `[providers.openai]`

```toml
[providers.openai]
enabled = false
api_key = "sk-..."
model = "gpt-4o"
max_tokens = 4096
temperature = 0.7
```

## Hooks Configuration

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "rag_context"
enabled = true
phase = "pre_llm"
params.max_hits = 5

[[hooks.definition]]
name = "memory_capture"
enabled = true
phase = "post_response"
```

## Security

### `[donkey.security]`

```toml
[donkey.security]
dm_policy = "allow"           # allow|block|whitelist
sandbox_mode = "docker"      # none|docker
sandbox_image = "alpine"
exec_timeout_seconds = 30
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DONKEY_HOME` | Override home | ~/.donkey |
| `DONKEY_SECRETS_KEY` | Encryption key | - |
| `DONKEY_LOG_LEVEL` | Override log level | from config |
```

**Priority:** P0  
**Estimated Size:** ~300 lines

---

## 4. Implementation Plan

### Phase 1: Core Documentation (P0)

| Document | Owner | Status |
|---------|-------|--------|
| `index.md` | TBD | ⏳ |
| `quickstart.md` | TBD | ⏳ |
| `getting_started/installation.md` | TBD | ⏳ |
| `getting_started/basic_concepts.md` | TBD | ⏳ |
| `reference/README.md` | TBD | ⏳ |
| `reference/configuration.md` | TBD | ⏳ |

### Phase 2: Topics (P1)

| Document | Owner | Status |
|---------|-------|--------|
| `topics/commands.md` | TBD | ⏳ |
| `topics/hooks.md` | TBD | ⏳ |
| `topics/memory.md` | TBD | ⏳ |
| `topics/sessions.md` | TBD | ⏳ |
| `topics/channels.md` | TBD | ⏳ |
| `topics/providers.md` | TBD | ⏳ |

### Phase 3: API Reference (P1)

| Document | Owner | Status |
|---------|-------|--------|
| `reference/types.md` | TBD | ⏳ |
| `reference/hook.md` | TBD | ⏳ |
| `reference/channel.md` | TBD | ⏳ |
| `reference/provider.md` | TBD | ⏳ |
| `reference/memory.md` | TBD | ⏳ |
| `reference/orchestrator.md` | TBD | ⏳ |

### Phase 4: Guides (P2)

| Document | Owner | Status |
|---------|-------|--------|
| `guides/first_bot.md` | TBD | ⏳ |
| `guides/deploying.md` | TBD | ⏳ |
| `guides/custom_channel.md` | TBD | ⏳ |
| `guides/custom_provider.md` | TBD | ⏳ |
| `guides/testing.md` | TBD | ⏳ |

### Phase 5: Contribute (P2)

| Document | Owner | Status |
|---------|-------|--------|
| `contributing.md` | TBD | ⏳ |
| `contributing/code_style.md` | TBD | ⏳ |
| `contributing/tests.md` | TBD | ⏳ |
| `contributing/architecture.md` | TBD | ⏳ |

---

## 5. Writing Style Guide

### 5.1 Tone

- **Friendly but professional**
- **Second person** ("You can..." not "The user can...")
- **Active voice** ("The function returns..." not "It is returned...")
- **Concrete examples** over abstract explanations

### 5.2 Code Examples

All code examples must:
1. Be syntactically correct
2. Be runnable (where practical)
3. Include comments for non-obvious parts
4. Use `nim` syntax highlighting

```nim
# Good: Complete, runnable example
proc greet*(name: string): string =
  ## Returns a greeting for the given name.
  result = "Hello, " & name & "!"

# Bad: Incomplete or missing context
proc greet*(name: string): string =
  "Hello, " & name & "!"
```

### 5.3 Formatting

```markdown
## Headings
Use sentence case: "### Creating a hook"
Not: "### Creating A Hook"

## Code blocks
```nim
# Always specify language
proc example() = discard
```

## Tables
Use for configuration options and API parameters only.

## Notes and warnings
!!! note
    This is a helpful note.

!!! warning
    This is important.
```

---

## 6. Maintenance

### 6.1 Review Process

1. All documentation PRs require review
2. Code changes must update relevant docs
3. Changelog entries should reference affected docs

### 6.2 Staleness Policy

- Configuration docs: Update on config schema changes
- API docs: Update on API changes
- Guides: Review quarterly
- Examples: Test code snippets annually

---

## 7. Appendix

### 7.1 Discord.PY Documentation Structure (Reference)

```
discord.py/
├── index.rst
├── quickstart.rst
├── intro.rst
├── faq.rst
├── api/
│   ├── client.rst
│   ├── intents.rst
│   ├── guild.rst
│   ├── channel.rst
│   └── ...
├── ext/
│   ├── commands/
│   └── tasks/
└── ...
```

### 7.2 Existing Donkey Documentation

```
docs/
├── adr/                    # Architecture Decision Records
├── architecture.md         # System overview
├── blueprint/              # Feature blueprints
├── nim/                    # Nim-specific docs
│   ├── tutorials/
│   ├── manual/
│   ├── style_guide/
│   ├── stdlib/
│   ├── memory/
│   └── tools/
└── reference/
    └── qq-official/
```

### 7.3 Migration Notes

When restructuring existing docs:
1. Preserve all existing ADR content
2. Merge redundant guides
3. Update cross-references
4. Redirect old URLs (if hosted)
