# Hooks API Reference
Complete reference for the hook system

## Overview

The hook system provides middleware-style interception of the message flow. Hooks can validate, modify, and enrich messages at various phases of processing.

**Architecture:** Hooks are a Port (interface), not an Adapter. Implementations are in `src/donkey/adapters/hooks/`.

---

## Hook Phases

```nim
type
  HookPhase* = enum
    hpPreLlm       ## Before LLM call
    hpPostLlm      ## After LLM response
    hpPreTool      ## Before tool execution
    hpPostTool     ## After tool result
    hpPostResponse  ## Before sending response
```

### Phase Flow

```
Message → hpPreLlm → LLM → hpPostLlm → Tool → hpPostTool → Response → hpPostResponse
```

| Phase | Description | Common Use Cases |
|-------|-------------|-----------------|
| `hpPreLlm` | Before LLM call | Validation, context injection, spam filter |
| `hpPostLlm` | After LLM response | Response modification, logging |
| `hpPreTool` | Before tool execution | Permission checks, rate limiting |
| `hpPostTool` | After tool result | Result caching, transformation |
| `hpPostResponse` | Before sending | Final modifications |

---

## `HookContext`

Context passed to each hook containing the current message state.

```nim
type
  HookContext* = object
    userId*:     UserId                ## User identifier
    sessionId*:  string               ## Session identifier
    message*:    string               ## Current message text
    history*:    Option[ConversationHistory]  ## Conversation history
    metadata*:   StringTableRef       ## Hook-specific metadata
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `userId` | `UserId` | User who sent the message |
| `sessionId` | `string` | Current session identifier |
| `message` | `string` | Message text |
| `history` | `Option[ConversationHistory]` | Conversation history |
| `metadata` | `StringTableRef` | Hook-specific key-value storage |

### Creating a Context

```nim
import donkey/ports/hook
import donkey/core/types

let ctx = newHookContext(
  userId = UserId("user_123"),
  sessionId = "session_456",
  message = "Hello, world!",
  history = some(history),
  metadata = newStringTable(modeCaseInsensitive)
)
```

---

## `HookResult`

Result returned by a hook function.

```nim
type
  HookResultKind* = enum
    hrkContinue   ## Continue to next hook, no modification
    hrkModified  ## Continue with modified context
    hrkRejected  ## Stop processing, reject message

  HookResult* = object
    case kind*: HookResultKind
    of hrkContinue, hrkModified:
      context*: HookContext
    of hrkRejected:
      errorMessage*: string
```

### Result Variants

| Variant | Description |
|--------|-------------|
| `hrkContinue` | Continue to next hook, no changes |
| `hrkModified` | Continue with modified context |
| `hrkRejected` | Stop processing, reject message |

### Creating Results

```nim
import donkey/ports/hook

func newHookResultContinue*(ctx: HookContext): HookResult

func newHookResultModified*(ctx: HookContext; modifiedContent: string): HookResult

func newHookResultRejected*(ctx: HookContext; error: string): HookResult
```

**Continue example:**

```nim
proc myHook*(ctx: HookContext): HookResult =
  # No changes, just continue
  return newHookResultContinue(ctx)
```

**Modified example:**

```nim
proc myModifier*(ctx: HookContext): HookResult =
  var modified = ctx
  modified.message = "Modified: " & ctx.message
  modified.metadata["modified"] = "true"
  return newHookResultModified(modified, modified.message)
```

**Rejected example:**

```nim
proc spamFilter*(ctx: HookContext): HookResult =
  if "spam" in ctx.message.toLower():
    return newHookResultRejected(ctx, "Spam detected")
  return newHookResultContinue(ctx)
```

---

## `HookFn`

The hook function signature.

```nim
type
  HookFn* = proc(ctx: HookContext): HookResult {.gcsafe, raises: [].}
```

**Requirements:**
- Must be `gcsafe` (GC-safe, no closure over GC-managed memory)
- Must not raise exceptions (`raises: []`)

---

## `HookDefinition`

Definition of a hook for registration.

```nim
type
  HookDefinition* = object
    name*:    string              ## Hook name
    phase*:   HookPhase          ## Execution phase
    handler*: HookFn             ## Hook function
    config*:  Option[StringTableRef]  ## Optional configuration
```

### Creating a Definition

```nim
import donkey/ports/hook

proc myHook*(ctx: HookContext): HookResult =
  return newHookResultContinue(ctx)

let definition = HookDefinition(
  name: "my_hook",
  phase: hpPreLlm,
  handler: myHook,
  config: some(configTable)
)
```

---

## `HookRegistry`

Registry for managing hooks.

```nim
type
  HookRegistry* = object
    hooks*: seq[HookDefinition]
```

### Creating a Registry

```nim
func newHookRegistry*(): HookRegistry
```

### Registration

```nim
func registerHook*(reg: var HookRegistry; hook: HookDefinition)
```

### Querying

```nim
func getHooksForPhase*(reg: HookRegistry; phase: HookPhase): seq[HookDefinition]
```

**Example:**

```nim
var registry = newHookRegistry()
registry.registerHook(hook1)
registry.registerHook(hook2)

let preLlmHooks = registry.getHooksForPhase(hpPreLlm)
```

---

## `HookExecutor`

Execution engine for hooks with enable/disable support.

```nim
type
  HookExecutor* = object
    registry*: HookRegistry
    enabled*: bool
```

### Creating an Executor

```nim
func newHookExecutor*(enabled: bool = true): HookExecutor
```

### Registration

```nim
func registerHook*(exec: var HookExecutor; hook: HookDefinition)
```

### Execution

```nim
proc executePhase*(
  exec: HookExecutor;
  phase: HookPhase;
  ctx: HookContext
): HookResult {.gcsafe.}
```

**Behavior:**
1. If `exec.enabled == false`, returns `hrkContinue` immediately
2. Gets hooks for the specified phase
3. Executes hooks in order
4. Short-circuits on `hrkRejected`
5. Passes modified context to next hook

### Complete Example

```nim
import donkey/ports/hook
import donkey/core/hooks/hook_executor

# Create spam filter hook
proc spamFilter*(ctx: HookContext): HookResult =
  let spamWords = ["buy now", "click here"]
  for word in spamWords:
    if word in ctx.message.toLower():
      return newHookResultRejected(ctx, "Spam detected")
  return newHookResultContinue(ctx)

# Create executor
var executor = newHookExecutor()

# Register hooks
executor.registerHook(HookDefinition(
  name: "spam_filter",
  phase: hpPreLlm,
  handler: spamFilter
))

# Execute hooks
let ctx = newHookContext(
  userId = UserId("user_123"),
  sessionId = "session_456",
  message = "Hello!"
)

let result = executor.executePhase(hpPreLlm, ctx)

case result.kind
of hrkContinue:
  echo "Proceeding to LLM..."
of hrkModified:
  echo "Message modified: ", result.context.message
of hrkRejected:
  echo "Rejected: ", result.errorMessage
```

---

## Hook Configuration

### TOML Configuration

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

### Phase String Mapping

| TOML String | Enum Value |
|-------------|------------|
| `"pre_llm"` | `hpPreLlm` |
| `"post_llm"` | `hpPostLlm` |
| `"pre_tool"` | `hpPreTool` |
| `"post_tool"` | `hpPostTool` |
| `"post_response"` | `hpPostResponse` |

---

## Built-in Hook Adapters

### RAG Context Hook

Located in `src/donkey/adapters/hooks/rag_context_hook.nim`

```nim
import donkey/adapters/hooks/rag_context_hook

proc ragHook*(ctx: HookContext): HookResult =
  let hookFn = makeRagContextHookFn(
    name = "rag_context",
    searchFn = mySearchFn,
    maxHits = 5
  )
  return hookFn(ctx)
```

### Memory Capture Hook

Located in `src/donkey/adapters/hooks/memory_capture_hook.nim`

```nim
import donkey/adapters/hooks/memory_capture_hook

proc memoryHook*(ctx: HookContext): HookResult =
  let hookFn = makeMemoryCaptureHookFn(
    name = "memory_capture",
    writeFn = myWriteFn
  )
  return hookFn(ctx)
```

### Context Injection Hook

Located in `src/donkey/core/hooks/context_injection_hook.nim`

```nim
import donkey/core/hooks/context_injection_hook

proc injectionHook*(ctx: HookContext): HookResult =
  let hookFn = makeContextInjectionHookFn(
    name = "context_injection",
    searchFn = mySearchFn
  )
  return hookFn(ctx)
```

---

## Metadata Usage

Hooks can communicate via the `metadata` StringTableRef:

```nim
proc loggingHook*(ctx: HookContext): HookResult =
  var modified = ctx
  modified.metadata["logged_at"] = $now()
  modified.metadata["original_message"] = ctx.message
  return newHookResultModified(modified, ctx.message)

proc laterHook*(ctx: HookContext): HookResult =
  if ctx.metadata.hasKey("logged_at"):
    echo "Message was logged at: ", ctx.metadata["logged_at"]
  return newHookResultContinue(ctx)
```

---

## Best Practices

### 1. Keep Hooks Fast

Hooks run synchronously. Avoid slow operations:

```nim
# Bad
proc slowHook*(ctx: HookContext): HookResult =
  let result = httpClient.get("https://slow-api.com/")  # Avoid!
  return newHookResultContinue(ctx)

# Good
proc fastHook*(ctx: HookContext): HookResult =
  if cache.has(ctx.message):
    ctx.metadata["cached"] = cache.get(ctx.message)
  return newHookResultContinue(ctx)
```

### 2. Preserve Context

When modifying, preserve important fields:

```nim
proc goodModifier*(ctx: HookContext): HookResult =
  var modified = ctx
  modified.metadata["processed_by"] = "my_hook"
  return newHookResultModified(modified, ctx.message)
```

### 3. Clear Error Messages

```nim
proc validatedHook*(ctx: HookContext): HookResult =
  if ctx.message.len > 10000:
    return newHookResultRejected(ctx, "Message too long (max 10000 chars)")
  return newHookResultContinue(ctx)
```

---

## Related

- [Hooks System](../topics/hooks.md)
- [Configuration Reference](configuration.md)
