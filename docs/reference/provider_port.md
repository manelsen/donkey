# Provider Port API Reference
Current reference for Donkey's LLM provider abstraction.

## Overview

Providers are adapters behind a common interface. Runtime credentials come from
environment variables such as `ZAI_CODING_API_KEY`, `OPENROUTER_API_KEY`, or
`MINIMAX_API_KEY`. Instance defaults live in `donkey.toml` via
`default_provider` and `default_model`.

The provider layer is responsible for:

- request/response translation
- streaming support
- tool-call parsing
- capability reporting
- model catalog integration

## ProviderPort Concept

```nim
type
  ProviderPort* = concept p
    p.complete(CompletionRequest) is CompletionResponse
    p.caps() is ProviderCaps
```

| Method | Description |
|--------|-------------|
| `p.complete(CompletionRequest)` | Blocking full completion |
| `p.caps()` | Pure capability metadata |

## ProviderCaps

```nim
type
  ProviderCaps* = object
    name*:              string
    streaming*:         bool
    toolCalling*:       bool
    nativeTools*:       seq[string]
    maxContextTokens*:  int
    requiresUserFirst*: bool
```

| Field | Description |
|-------|-------------|
| `name` | Provider identifier such as `anthropic` or `minimax` |
| `streaming` | Whether token streaming is supported |
| `toolCalling` | Whether structured tool calling is supported |
| `nativeTools` | Provider-managed tools, if any |
| `maxContextTokens` | Maximum context window, `0` when unknown |
| `requiresUserFirst` | Provider ordering quirk, notably Gemini |

## CompletionRequest

```nim
type
  CompletionRequest* = object
    system*:    string
    messages*:  seq[ChatMessage]
    maxTokens*: int
    tools*:     seq[ToolDescription]
```

| Field | Description |
|-------|-------------|
| `system` | System prompt |
| `messages` | Conversation history |
| `maxTokens` | Response token budget, `0` = provider default |
| `tools` | Advertised callable tools |

## CompletionResponse

```nim
type
  CompletionResponse* = object
    text*:         string
    inputTokens*:  int
    outputTokens*: int
    toolCalls*:    seq[ToolCallRequest]
```

| Field | Description |
|-------|-------------|
| `text` | Final generated text |
| `inputTokens` | Prompt token usage |
| `outputTokens` | Completion token usage |
| `toolCalls` | Parsed tool calls to execute |

## Runtime Function Types

### CompleteFn

```nim
type
  CompleteFn* = proc(req: CompletionRequest): Result[CompletionResponse, string]
                    {.gcsafe.}
```

### StreamFn

```nim
type
  StreamFn* = proc(req: CompletionRequest;
                   onToken: proc(tok: string) {.gcsafe.}
                  ): Result[CompletionResponse, string]
                  {.gcsafe.}
```

### ProviderBundle

```nim
type
  ProviderBundle* = object
    completeFn*: CompleteFn
    streamFn*:   StreamFn
```

## Configuration Model

### Instance Defaults

The current runtime uses:

```toml
[donkey]
default_provider = "zai-coding"
default_model = "glm-4.7"
```

### Credentials

Credentials come from env:

```bash
export ZAI_CODING_API_KEY=...
export OPENROUTER_API_KEY=...
export GEMINI_API_KEY=...
export MINIMAX_API_KEY=...
```

### Per-user Preferences

Per-user overrides live in `PREFERENCES.md`:

```toml
provider = "minimax"
model = "MiniMax-M2.7"
```

## ProviderSpec and ProviderPrefs

```nim
type
  ProviderSpec* = object
    providerName*: string
    modelName*:    string
    apiKey*:       string

  ProviderPrefs* = object
    providerName*: string
    modelName*:    string
```

`ProviderSpec` is used when building a concrete runtime client. `ProviderPrefs`
represent a user's selected provider/model pair.

## Model Catalog

### ModelCatalogEntry

```nim
type
  ModelCatalogEntry* = object
    providerName*: string
    modelName*:    string
    label*:        string
    isFree*:       bool
    available*:    bool
    hasPricing*:   bool
    inputCostMicrosPer1k*:  int
    outputCostMicrosPer1k*: int
```

### ModelCatalogSource

```nim
type
  ModelCatalogSource* = enum
    mcsLive
    mcsCache
    mcsFallback
```

### ModelCatalogResult

```nim
type
  ModelCatalogResult* = object
    entries*:       seq[ModelCatalogEntry]
    source*:        ModelCatalogSource
    fetchedAtUnix*: int64
```

## Built-in Provider Adapters

### Anthropic

- Location: `src/donkey/adapters/provider/anthropic.nim`
- Env: `ANTHROPIC_API_KEY`
- Typical models: `claude-sonnet-*`, `claude-opus-*`
- Streaming: yes
- Tool calling: yes

### OpenAI

- Location: `src/donkey/adapters/provider/openai.nim`
- Env: `OPENAI_API_KEY`
- Typical models: `gpt-4o`, `gpt-4o-mini`
- Streaming: yes
- Tool calling: yes

### OpenRouter

- Location: `src/donkey/adapters/provider/openrouter.nim`
- Env: `OPENROUTER_API_KEY`
- Typical models: `provider/model`
- Streaming: provider-dependent
- Tool calling: provider-dependent

### Gemini

- Location: `src/donkey/adapters/provider/gemini.nim`
- Env: `GEMINI_API_KEY`
- Typical models: `gemini-*`
- Streaming: yes
- Tool calling: yes
- Note: `requiresUserFirst = true`

### DeepSeek

- Location: `src/donkey/adapters/provider/deepseek.nim`
- Env: `DEEPSEEK_API_KEY`
- Typical models: `deepseek-chat`

### MiniMax

- Location: `src/donkey/adapters/provider/minimax.nim`
- Env: `MINIMAX_API_KEY`
- Typical models: `MiniMax-M2.7`

### ZAI Coding / Zhipu-compatible

- Location: `src/donkey/adapters/provider/zhipu.nim`
- Env: `ZAI_CODING_API_KEY`
- Compatibility fallback envs: `ZAI_API_KEY`, `ZHIPU_API_KEY`
- Typical models: `glm-4.7`

### ZAI Anthropic

- Built through the Anthropic-compatible runtime layer
- Env: `ZAI_ANTHROPIC_API_KEY`

### Ollama

- Location: `src/donkey/adapters/provider/ollama.nim`
- Env: `OLLAMA_BASE_URL` (optional)
- Typical models: local tags exposed by the Ollama server

## Usage Examples

### Basic Completion

```nim
import donkey/ports/provider
import donkey/domain/message

let req = CompletionRequest(
  system: "You are a helpful assistant.",
  messages: @[ChatMessage(role: roleUser, text: "Hello!")],
  maxTokens: 100,
  tools: @[]
)

let resp = provider.complete(req)
if resp.isOk:
  echo resp.value.text
```

### Streaming Completion

```nim
var fullText = ""

proc onToken(tok: string) =
  fullText &= tok
  echo tok

let req = CompletionRequest(
  system: "You are a helpful assistant.",
  messages: @[ChatMessage(role: roleUser, text: "Tell me a story.")],
  maxTokens: 500,
  tools: @[]
)

if provider.streamFn.isNil.not:
  discard provider.streamFn(req, onToken)
```

### Tool Calling

```nim
let tool = ToolDescription(
  name: "get_weather",
  description: "Get current weather",
  schema: %*{
    "type": "object",
    "properties": {
      "location": {"type": "string"}
    }
  }
)
```

## Related

- [Providers Overview](../topics/providers.md)
- [Configuration Reference](configuration.md)
