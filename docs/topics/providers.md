# Providers
LLM provider integrations

## Overview

Donkey connects to various LLM providers through a unified ProviderPort interface. Each provider adapter handles authentication, request formatting, and response parsing.

## Supported Providers

| Provider | Model | Streaming | Tool Calling | Max Context |
|---------|-------|----------|--------------|--------------|
| [Anthropic](#anthropic) | Claude | Yes | Yes | 200k |
| [OpenAI](#openai) | GPT-4 | Yes | Yes | 128k |
| [OpenRouter](#openrouter) | Multiple | Varies | Varies | Varies |
| [Gemini](#gemini) | Gemini | Yes | Yes | 1M |
| [DeepSeek](#deepseek) | DeepSeek | Yes | Yes | 128k |
| [Ollama](#ollama) | Local | Yes | No | Varies |

---

## Anthropic

Claude via Anthropic API.

### Capabilities
- **Streaming:** Yes
- **Tool Calling:** Yes
- **Native Tools:** None
- **Max Context:** 200k tokens

### Configuration

```toml
[providers.anthropic]
enabled = true
api_key = "sk-ant-api03-..."
model = "claude-sonnet-4-20250514"
max_tokens = 8192
temperature = 0.7
```

### Models

| Model | Description | Best For |
|-------|-------------|----------|
| `claude-opus-4-5` | Most capable | Complex reasoning |
| `claude-sonnet-4-20250514` | Balanced | General use |
| `claude-haiku-4-5` | Fast, efficient | Quick tasks |

### System Prompt Tips

Claude responds well to:
- Clear role definitions
- Step-by-step thinking
- Output format specifications

```nim
let system = """
You are a helpful coding assistant.
Think step by step.
Format code with proper syntax highlighting.
"""
```

---

## OpenAI

GPT via OpenAI API.

### Capabilities
- **Streaming:** Yes
- **Tool Calling:** Yes
- **Native Tools:** None
- **Max Context:** 128k tokens

### Configuration

```toml
[providers.openai]
enabled = false
api_key = "sk-..."
model = "gpt-4o"
max_tokens = 4096
temperature = 0.7
```

### Models

| Model | Description | Best For |
|-------|-------------|----------|
| `gpt-4o` | Latest, balanced | General use |
| `gpt-4o-mini` | Fast, low cost | Quick tasks |
| `gpt-4-turbo` | Previous generation | Budget-conscious |
| `gpt-3.5-turbo` | Basic | Simple tasks |

### JSON Mode

```nim
# Add to request
let req = CompletionRequest(
  # ...
)
# Provider handles JSON mode formatting
```

---

## OpenRouter

Multi-provider aggregation with unified pricing.

### Capabilities
- **Streaming:** Provider-dependent
- **Tool Calling:** Provider-dependent
- **Max Context:** Varies by provider

### Configuration

```toml
[providers.openrouter]
enabled = false
api_key = "sk-or-..."
model = "anthropic/claude-3-opus"
site_url = "https://your-app.com"
site_name = "Your App"
```

### Model Selection

OpenRouter supports models from multiple providers:

```toml
# Anthropic models
model = "anthropic/claude-3-opus"
model = "anthropic/claude-3-sonnet"

# OpenAI models
model = "openai/gpt-4-turbo"

# Google models
model = "google/gemini-pro"

# Meta models
model = "meta-llama/llama-3-70b-instruct"
```

### Cost Management

OpenRouter provides unified pricing across providers.

---

## Gemini

Google Gemini AI.

### Capabilities
- **Streaming:** Yes
- **Tool Calling:** Yes
- **Native Tools:** `google_search`
- **Max Context:** 1M tokens

### Configuration

```toml
[providers.gemini]
enabled = false
api_key = ""
model = "gemini-2.0-flash"
max_tokens = 8192
```

### Models

| Model | Description | Max Context |
|-------|-------------|-------------|
| `gemini-2.0-flash` | Latest, fast | 1M |
| `gemini-1.5-pro` | High capability | 1M |
| `gemini-1.5-flash` | Balanced | 1M |

### Google Search Tool

Gemini can use `google_search` natively:

```nim
let caps = ProviderCaps(
  name: "gemini",
  nativeTools: @["google_search"]
)
```

### Turn Ordering

Gemini requires user message after function results:

```nim
# Gemini quirk: requiresUserFirst = true
# Function response must follow model turn
```

---

## DeepSeek

DeepSeek API (Chinese LLM).

### Configuration

```toml
[providers.deepseek]
enabled = false
api_key = ""
model = "deepseek-chat"
base_url = "https://api.deepseek.com"
```

### Models

| Model | Description |
|-------|-------------|
| `deepseek-chat` | General chat |
| `deepseek-coder` | Code-specialized |

---

## Ollama

Local LLM server.

### Configuration

```toml
[providers.ollama]
enabled = false
model = "llama3"
base_url = "http://localhost:11434"
```

### Setup

1. Install Ollama: https://ollama.ai
2. Pull a model:
   ```bash
   ollama pull llama3
   ```
3. Start server (runs automatically):
   ```bash
   ollama serve
   ```

### Available Models

```bash
# List available models
ollama list

# Pull a model
ollama pull codellama
ollama pull mistral
ollama pull mixtral
```

### Limitations

- No tool calling support
- No streaming (depends on model)
- Context varies by model

---

## Provider Selection

### By Task

| Task | Recommended Provider |
|------|---------------------|
| Coding | Claude, GPT-4 |
| Creative | GPT-4, Claude |
| Fast/cheap | GPT-3.5, Gemini Flash |
| Local | Ollama |

### By Budget

| Budget | Provider |
|--------|----------|
| Unlimited | Claude Opus |
| Moderate | Claude Sonnet, GPT-4 |
| Low | GPT-3.5, Gemini Flash, Ollama |

---

## Switching Models

Use `/model` command:

```
/model anthropic claude-sonnet-4-20250514
```

Or via configuration:

```toml
[providers.anthropic]
model = "claude-sonnet-4-20250514"
```

---

## Temperature

Controls response randomness:

| Temperature | Use Case |
|------------|----------|
| 0.0-0.3 | Precise, factual |
| 0.4-0.6 | Balanced |
| 0.7-0.9 | Creative |
| 1.0+ | Random |

```toml
[providers.anthropic]
temperature = 0.7  # Balanced
```

---

## Token Limits

### Input Tokens

Cost based on input message length.

### Output Tokens

`max_tokens` limits response length:

```toml
[providers.anthropic]
max_tokens = 8192  # Limit response to 8k tokens
```

### Context Window

Total capacity for input + output:

| Provider | Max Context |
|----------|-------------|
| Claude | 200k |
| GPT-4 | 128k |
| Gemini | 1M |

---

## Related

- [Configuration Reference](../reference/configuration.md)
- [Provider Port API](../reference/provider_port.md)
