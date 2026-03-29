# Provider Port API Reference
Complete reference for the LLM provider abstraction

## Overview

The ProviderPort provides a unified interface for all LLM providers. This abstraction allows Donkey to work with any language model without knowing provider-specific details.

**Architecture:** Providers are Adapters that implement the ProviderPort concept.

---

## ProviderPort Concept

```nim
type
  ProviderPort* = concept p
    p.complete(CompletionRequest) is CompletionResponse  ## Blocking completion
    p.caps() is ProviderCaps                        ## Provider capabilities
```

| Method | Description |
|--------|-------------|
| `p.complete(CompletionRequest)` | Blocking LLM call, returns full response |
| `p.caps()` | Provider capabilities (pure metadata) |

---

## Provider Capabilities

```nim
type
  ProviderCaps* = object
    name*:               string    ## Provider name
    streaming*:          bool     ## Supports streaming
    toolCalling*:        bool     ## Supports function calling
    nativeTools*:        seq[string]  ## Provider-managed tools
    maxContextTokens*:   int     ## 0 = unknown/unlimited
    requiresUserFirst*:  bool    ## Gemini: function response follows model turn
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Provider identifier (e.g., "anthropic") |
| `streaming` | `bool` | Whether streaming is supported |
| `toolCalling` | `bool` | Whether function calling is supported |
| `nativeTools` | `seq[string]` | Provider-managed tools (e.g., `["web_search"]`) |
| `maxContextTokens` | `int` | Maximum context window (0 = unknown) |
| `requiresUserFirst` | `bool` | Gemini quirk: function response follows model turn |

---

## CompletionRequest

Request to the LLM.

```nim
type
  CompletionRequest* = object
    system*:    string                    ## System prompt
    messages*:  seq[ChatMessage]        ## Conversation history
    maxTokens*: int                       ## 0 = provider default
    tools*:     seq[ToolDescription]      ## Available tools
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `system` | `string` | System prompt |
| `messages` | `seq[ChatMessage]` | Conversation history |
| `maxTokens` | `int` | Max response tokens (0 = default) |
| `tools` | `seq[ToolDescription]` | Available tools |

---

## CompletionResponse

Response from the LLM.

```nim
type
  CompletionResponse* = object
    text*:         string                   ## Generated text
    inputTokens*:  int                    ## Input tokens used
    outputTokens*: int                    ## Output tokens generated
    toolCalls*:    seq[ToolCallRequest] ## Tool calls to execute
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `text` | `string` | Generated text |
| `inputTokens` | `int` | Input tokens consumed |
| `outputTokens` | `int` | Output tokens generated |
| `toolCalls` | `seq[ToolCallRequest]` | Tool calls to execute |

---

## Provider Function Types

### `CompleteFn`

Blocking completion function.

```nim
type
  CompleteFn* = proc(req: CompletionRequest): Result[CompletionResponse, string]
                    {.gcsafe.}
```

### `StreamFn`

Streaming completion function.

```nim
type
  StreamFn* = proc(req: CompletionRequest;
                    onToken: proc(tok: string) {.gcsafe.}
                   ): Result[CompletionResponse, string]
                   {.gcsafe.}
```

### `ProviderBundle`

Container for provider functions.

```nim
type
  ProviderBundle* = object
    completeFn*: CompleteFn
    streamFn*:   StreamFn
```

---

## Provider Configuration

### `ProviderSpec`

Configuration for a provider.

```nim
type
  ProviderSpec* = object
    providerName*: string  ## Provider identifier
    modelName*:    string  ## Model to use
    apiKey*:       string  ## API key
```

### `ProviderPrefs`

User preferences for a provider.

```nim
type
  ProviderPrefs* = object
    providerName*: string  ## Provider identifier
    modelName*:    string  ## Model name
```

---

## Model Catalog

### `ModelCatalogEntry`

Entry in the model catalog.

```nim
type
  ModelCatalogEntry* = object
    providerName*: string
    modelName*:    string
    label*:        string      ## Display name
    isFree*:       bool       ## Free tier available
    available*:    bool       ## Currently available
    hasPricing*:   bool       ## Pricing info available
    inputCostMicrosPer1k*: int   ## Input cost per 1k tokens (microdollars)
    outputCostMicrosPer1k*: int   ## Output cost per 1k tokens (microdollars)
```

### `ModelCatalogSource`

Source of catalog data.

```nim
type
  ModelCatalogSource* = enum
    mcsLive     ## Live from API
    mcsCache   ## From local cache
    mcsFallback ## Fallback data
```

### `ModelCatalogResult`

Result from catalog query.

```nim
type
  ModelCatalogResult* = object
    entries*:      seq[ModelCatalogEntry]
    source*:       ModelCatalogSource
    fetchedAtUnix*: int64   ## When catalog was fetched
```

---

## Provider Adapters

### Anthropic

Claude via Anthropic API.

**Location:** `src/donkey/adapters/provider/anthropic.nim`

**Capabilities:**
- Streaming: Yes
- Tool Calling: Yes
- Native Tools: None

**Configuration:**

```toml
[providers.anthropic]
enabled = true
api_key = "sk-ant-api03-..."
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7
```

---

### OpenAI

GPT via OpenAI API.

**Location:** `src/donkey/adapters/provider/openai.nim`

**Capabilities:**
- Streaming: Yes
- Tool Calling: Yes
- Native Tools: None

**Configuration:**

```toml
[providers.openai]
enabled = true
api_key = "sk-..."
model = "gpt-4o"
max_tokens = 4096
temperature = 0.7
```

---

### OpenRouter

Multi-provider aggregation via OpenRouter.

**Location:** `src/donkey/adapters/provider/openrouter.nim`

**Capabilities:**
- Streaming: Yes (provider-dependent)
- Tool Calling: Provider-dependent
- Native Tools: None

**Configuration:**

```toml
[providers.openrouter]
enabled = true
api_key = "sk-or-..."
model = "anthropic/claude-3-opus"
site_url = "https://your-app.com"
site_name = "Your App"
```

---

### Gemini

Google Gemini AI.

**Location:** `src/donkey/adapters/provider/gemini.nim`

**Capabilities:**
- Streaming: Yes
- Tool Calling: Yes
- Native Tools: `["google_search"]`

**Note:** `requiresUserFirst = true` - function response must follow model turn.

**Configuration:**

```toml
[providers.gemini]
enabled = true
api_key = ""
model = "gemini-2.0-flash"
max_tokens = 8192
```

---

### DeepSeek

DeepSeek API.

**Location:** `src/donkey/adapters/provider/deepseek.nim`

**Configuration:**

```toml
[providers.deepseek]
enabled = false
api_key = ""
model = "deepseek-chat"
base_url = "https://api.deepseek.com"
```

---

### Ollama

Local Ollama server.

**Location:** `src/donkey/adapters/provider/ollama.nim`

**Configuration:**

```toml
[providers.ollama]
enabled = false
model = "llama3"
base_url = "http://localhost:11434"
```

---

### MiniMax

MiniMax API.

**Configuration:**

```toml
[providers.minimax]
enabled = false
api_key = ""
model = "abab6-chat"
```

---

### Zhipu

Zhipu AI API.

**Configuration:**

```toml
[providers.zhipu]
enabled = false
api_key = ""
model = "glm-4"
```

---

## Usage Examples

### Basic Completion

```nim
import donkey/ports/provider
import donkey/domain/message

let req = CompletionRequest(
  system: "You are a helpful assistant.",
  messages: @[
    ChatMessage(role: roleUser, text: "Hello!")
  ],
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
  name: "bash",
  description: "Execute a bash command",
  schemaJson: """{"type": "object", "properties": {"command": {"type": "string"}}}"""
)

let req = CompletionRequest(
  system: "You have access to tools.",
  messages: history,
  maxTokens: 1000,
  tools: @[tool]
)

let resp = provider.complete(req)
if resp.isOk and resp.value.toolCalls.len > 0:
  for call in resp.value.toolCalls:
    echo "Tool: ", call.name
    echo "Args: ", call.inputJson
```

### Checking Capabilities

```nim
let caps = provider.caps()

if caps.toolCalling:
  echo "Provider supports function calling"

if caps.streaming:
  echo "Provider supports streaming"

echo "Max context: ", caps.maxContextTokens, " tokens"
```

---

## Provider Comparison

| Provider | Streaming | Tool Calling | Native Tools | Max Context |
|---------|----------|--------------|--------------|--------------|
| Anthropic | Yes | Yes | None | 200k |
| OpenAI | Yes | Yes | None | 128k |
| OpenRouter | Varies | Varies | Varies | Varies |
| Gemini | Yes | Yes | google_search | 1M |
| DeepSeek | Yes | Yes | None | 128k |
| Ollama | Yes | No | None | Varies |

---

## Error Handling

All provider operations return `Result`:

```nim
proc complete*(p: ProviderPort; req: CompletionRequest): Result[CompletionResponse, string]
```

**Success:**

```nim
let resp = provider.complete(req)
if resp.isOk:
  echo resp.value.text
```

**Failure:**

```nim
let resp = provider.complete(req)
if resp.isErr:
  echo "Error: ", resp.error
```

---

## Related

- [Configuration Reference](configuration.md)
- [Core Types Reference](core_types.md)
