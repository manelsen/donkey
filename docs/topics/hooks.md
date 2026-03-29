# Hooks System
Message flow interception and augmentation

## Overview

Hooks provide middleware-style interception of the message flow. They allow you to validate, modify, and enrich messages at various phases of processing.

## Hook Phases

```
Message → hpPreLlm → LLM → hpPostLlm → Tool → hpPostTool → Response → hpPostResponse
```

| Phase | Description | Common Use Cases |
|-------|-------------|------------------|
| `hpPreLlm` | Before LLM call | Validation, context injection, spam filter |
| `hpPostLlm` | After LLM response | Response modification, logging |
| `hpPreTool` | Before tool execution | Permission checks, rate limiting |
| `hpPostTool` | After tool result | Result caching, transformation |
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
    hrkContinue   # Continue to next hook
    hrkModified   # Modified context, continue
    hrkRejected   # Reject the message
  
  HookResult* = object
    case kind*: HookResultKind
    of hrkContinue:
      discard
    of hrkModified:
      context*: HookContext
    of hrkRejected:
      errorMessage*: string
```

## Hook Definition

```nim
type
  HookDefinition* = object
    name*: string
    phase*: HookPhase
    handler*: HookFn
    enabled*: bool
    config*: StringTableRef
```

## Creating a Hook

### Simple Spam Filter

```nim
proc spamFilter*(ctx: HookContext): HookResult =
  let spamWords = ["buy now", "click here", "free money"]
  for word in spamWords:
    if word in ctx.message.toLower():
      return newHookResultRejected(ctx, "Spam detected")
  return newHookResultContinue(ctx)
```

### Context Injection

```nim
proc contextInjector*(ctx: HookContext): HookResult =
  # Get context from memory
  let hits = searchMemory(ctx.userId, ctx.message, k = 5)
  
  # Inject context into metadata
  var modified = ctx
  modified.metadata[ContextHintKey] = hits.mapIt(it.content).join("\n\n")
  
  return newHookResultModified(modified, ctx.message)
```

## Hook Executor

The executor manages hook lifecycle:

```nim
import donkey/core/hooks/hook_executor

var executor = newHookExecutor()
executor.registerHook(HookDefinition(
  name: "spam_filter",
  phase: hpPreLlm,
  handler: spamFilter
))

# Execute hooks for a phase
let result = executor.executePhase(hpPreLlm, ctx)

case result.kind
of hrkContinue:
  # Proceed
of hrkModified:
  ctx = result.context
of hrkRejected:
  # Handle rejection
  echo result.errorMessage
```

### Short-circuiting

Hooks execute in order and short-circuit on rejection:

```nim
# Hooks: spam_filter → context_inject → llm_call
# If spam_filter rejects, context_inject and llm_call are skipped
```

## Built-in Hooks

### RAG Context Hook

Injects relevant context from semantic memory:

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "rag_context"
enabled = true
phase = "pre_llm"
params.max_hits = 5
params.similarity_threshold = 0.7
```

### Memory Capture Hook

Captures conversation to memory:

```toml
[[hooks.definition]]
name = "memory_capture"
enabled = true
phase = "post_response"
params.capture_user = true
params.capture_assistant = true
```

### Context Injection Hook

Abstract hook factory for custom context injection:

```nim
import donkey/core/hooks/context_injection_hook

# Create with search function
let hookFn = makeContextInjectionHookFn(
  name = "custom_rag",
  searchFn = mySemanticSearch
)

# Register
executor.registerHook(HookDefinition(
  name: "custom_rag",
  phase: hpPreLlm,
  handler: hookFn
))
```

## Configuration

### TOML Configuration

```toml
[hooks]
enabled = true

[[hooks.definition]]
name = "spam_filter"
enabled = true
phase = "pre_llm"
params.block_threshold = 0.8

[[hooks.definition]]
name = "rag_context"
enabled = true
phase = "pre_llm"
params.max_hits = 5
params.min_score = 0.7
```

### Programmatic Configuration

```nim
import donkey/core/hooks/hook_config

var loader = newHookConfigLoader()
loader.addHookConfig(HookConfig(
  name: "my_hook",
  enabled: true,
  phase: hpPreLlm
))

# Get enabled hooks for a phase
let configs = loader.getHooksForPhase(hpPreLlm, onlyEnabled = true)
```

## Hook Registry

The executor maintains a registry of all hooks:

```nim
# Register multiple hooks
executor.registerHook(HookDefinition(...))
executor.registerHook(HookDefinition(...))

# Unregister
executor.unregisterHook("spam_filter")

# List hooks by phase
let preLlmHooks = executor.getHooksForPhase(hpPreLlm)

# Enable/disable
executor.setEnabled("spam_filter", false)
```

## Best Practices

### 1. Keep Hooks Fast

Hooks run synchronously. Avoid slow operations:

```nim
# Bad: Slow operation in hook
proc slowHook*(ctx: HookContext): HookResult =
  let result = httpClient.get("https://slow-api.com/")  # Avoid!
  return newHookResultContinue(ctx)

# Good: Async or cached
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
  modified.metadata["timestamp"] = $now()
  return newHookResultModified(modified, ctx.message)
```

### 3. Clear Error Messages

Provide helpful rejection messages:

```nim
proc validatedHook*(ctx: HookContext): HookResult =
  if ctx.message.len > 10000:
    return newHookResultRejected(ctx, "Message too long (max 10000 chars)")
  return newHookResultContinue(ctx)
```

## Related

- [Commands System](commands.md)
- [Memory System](memory.md)
- [API Reference](../reference/README.md)
