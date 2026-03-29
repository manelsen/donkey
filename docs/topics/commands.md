# Commands System
Slash commands and message routing

## Overview

Donkey supports slash commands with semantic routing. Commands start with `/` and are parsed by the command routing system.

## Command Structure

```
/command [args]              → Route decision
     │
     ├─► crLocal           → Handled locally (no LLM)
     ├─► crSessionTask      → Session task (reset, compact, etc)
     ├─► crUi               → Interactive UI (model selection)
     ├─► crStatus           → Status queries
     └─► crPing             → Ping/pong
```

## Available Commands

### Navigation Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/start` | Start conversation | `crLocal` |
| `/menu` | Show command menu | `crLocal` |
| `/new` | Clear history, start fresh | `crSessionTask` |
| `/whoami` | Show current session id | `crLocal` |

### Configuration Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/config` | Manage runtime configuration | `crUi` |
| `/model` | Switch model | `crUi` |
| `/think` | Set thinking level | `crUi` |
| `/budget` | Set budget policy | `crUi` |
| `/verbose` | Set verbose level | `crSessionTask` |
| `/reasoning` | Set reasoning output | `crSessionTask` |
| `/exec` | Set exec policy | `crSessionTask` |
| `/allowlist` | Show allowlist | `crStatus` |
| `/queue` | Set queue policy | `crSessionTask` |
| `/usage` | Set usage footer mode | `crSessionTask` |

### Status Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/status` | Show model and stats | `crStatus` |
| `/tasks` | List background tasks | `crUi` |
| `/agents` | Show active agents | `crUi` |
| `/poll` | Show pending approvals | `crUi` |

### Memory Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/forget` | Clear memory | `crLocal` |
| `/memory` | Memory tools | `crLocal` |
| `/doctor` | Memory diagnostics | `crLocal` |

### Session Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/reset` | Reset session | `crSessionTask` |
| `/compact` | Compact context now | `crSessionTask` |
| `/restart` | Restart session | `crSessionTask` |
| `/stop` | Stop active task | `crSessionTask` |
| `/bind` | Bind chat to agent | `crSessionTask` |

### Utility Commands

| Command | Description | Route |
|---------|-------------|-------|
| `/help` | Show help | `crLocal` |
| `/debug` | Toggle debug mode | `crSessionTask` |
| `/mycode` | Generate link code | `crLocal` |
| `/continue` | Continue link | `crLocal` |
| `/ping` | Ping | `crPing` |

## Command Routing

Commands are parsed in `core/commands/command_routing.nim`:

```nim
func parseCommandText*(text: string): CommandDecision =
  let cmd = stripBotMention(text.strip)
  case cmd
  of "/start": newCommandDecision(cmdStart)
  of "/menu": newCommandDecision(cmdMenu)
  of "/reset": newCommandDecision(cmdReset)
  # ... more commands
```

### Route Types

```nim
type
  CommandRoute* = enum
    crNone          # Not a command
    crLocal         # Handled locally (no LLM)
    crSessionTask   # Session operation
    crUi            # Interactive UI
    crPing          # Ping/pong
    crStatus        # Status query
    crCallback      # Callback data
```

## Command Catalog

The unified command catalog provides metadata for all commands:

```nim
import donkey/core/commands/command_catalog

let catalog = newCommandCatalog()
echo catalog.getMenuText()
```

### Categories

```nim
type
  CommandCategory* = enum
    ccNavigation     # /start, /menu, /new, /whoami
    ccConfiguration  # /config, /model, /think...
    ccStatus        # /status, /tasks, /agents...
    ccMemory        # /forget, /memory, /doctor
    ccSession       # /reset, /compact, /restart...
    ccTools         # /help, /debug, /mycode...
```

## Creating Custom Commands

### 1. Add to CommandKind enum

```nim
# In command_routing.nim
type
  CommandKind* = enum
    # ... existing
    cmdMyCustom
```

### 2. Add parsing

```nim
func parseCommandText*(text: string): CommandDecision =
  let cmd = stripBotMention(text.strip)
  case cmd
  # ... existing
  of "/mycustom": newCommandDecision(cmdMyCustom)
```

### 3. Add route decision

```nim
func decideCommandRoute*(kind: CommandKind): CommandRoute =
  case kind
  # ... existing
  of cmdMyCustom: crSessionTask
```

### 4. Add to catalog

```nim
# In command_catalog.nim
const CommandCatalogItems*: seq[CommandMetadata] = @[
  # ... existing
  CommandMetadata(
    name: "/mycustom",
    description: "My custom command",
    category: ccTools,
    requiresArgs: false,
    route: crSessionTask
  ),
]
```

## Local Command Actions

Local commands are handled directly without LLM:

```nim
type
  LocalCommandAction* = enum
    lcaNone
    lcaStartIntro
    lcaShowMenu
    lcaShowWhoami
    lcaGenerateLinkCode
    lcaClearMemory
    lcaDoctorReport
    lcaHelpText
    lcaShowMemory
    lcaContinueLink
```

## Related

- [Hooks System](hooks.md)
- [Sessions](sessions.md)
- [Configuration](reference/configuration.md)
