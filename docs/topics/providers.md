# Providers
Current provider model for the SQLite-first runtime.

## Overview

Donkey talks to LLMs through a unified provider layer. Credentials come from
environment variables in `~/.config/donkey/donkey.env`, while
`default_provider` and `default_model` live in `~/.config/donkey/donkey.toml`.

Typical flow:

1. Instance defaults come from `donkey.toml`.
2. Per-user overrides live in `PREFERENCES.md`.
3. Smart routing and failover pick the first healthy compatible provider when a
   session has no explicit preference.

The normal happy path is:

```bash
nimble build
./donkey setup
./donkey doctor
./donkey start
```

## Supported Providers

| Provider | Env var | Typical models | Streaming | Tool calling |
|----------|---------|----------------|-----------|--------------|
| ZAI Coding | `ZAI_CODING_API_KEY` | `glm-4.7` | Yes | Yes |
| ZAI Anthropic | `ZAI_ANTHROPIC_API_KEY` | Anthropic-compatible Claude models | Yes | Yes |
| ZAI generic | `ZAI_API_KEY` | `glm-*` | Yes | Yes |
| Anthropic | `ANTHROPIC_API_KEY` | `claude-*` | Yes | Yes |
| OpenAI | `OPENAI_API_KEY` | `gpt-*` | Yes | Yes |
| OpenRouter | `OPENROUTER_API_KEY` | provider/model strings | Provider-dependent | Provider-dependent |
| Gemini | `GEMINI_API_KEY` | `gemini-*` | Yes | Yes |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-chat` | Yes | Yes |
| MiniMax | `MINIMAX_API_KEY` | `MiniMax-M2.7` | Yes | Yes |
| Ollama | no API key | local models | Yes | Limited by server/model |

## Instance Defaults

Use `donkey.toml` to set the initial provider/model for new sessions before a
user has its own preferences:

```toml
[donkey]
default_provider = "zai-coding"
default_model = "glm-4.7"
```

This is what `donkey setup` writes by default today.

## Credentials

Credentials live in `~/.config/donkey/donkey.env`:

```bash
ZAI_CODING_API_KEY=...
OPENROUTER_API_KEY=...
MINIMAX_API_KEY=...
BRAVE_API_KEY=...   # optional, enables web_search
```

`donkey doctor` reports which providers are currently enabled by env.

## Per-user Overrides

Each user/session can override provider and model in `PREFERENCES.md`:

```toml
provider = "minimax"
model = "MiniMax-M2.7"
```

That affects normal conversation turns, heartbeat turns, and follow-up tool
turns for that user.

## Smart Routing and Fallbacks

When a session has no explicit provider preference:

- Donkey starts from the instance default provider/model.
- Tool-heavy sessions prefer tool-capable providers.
- Provider failover can move to the next healthy compatible provider if the
  current one errors.

This means you can keep one preferred provider and still configure secondary
keys such as OpenRouter or Gemini for resilience.

## Provider Notes

### ZAI Coding

The default tool-heavy path in the current runtime.

```bash
export ZAI_CODING_API_KEY=...
```

Recommended when you want:

- strong tool use
- coding-oriented behavior
- the default SQLite-first setup path

### Anthropic

Claude via Anthropic's API.

```bash
export ANTHROPIC_API_KEY=...
```

Typical models:

- `claude-sonnet-*`
- `claude-opus-*`

### OpenAI

GPT models via OpenAI.

```bash
export OPENAI_API_KEY=...
```

Typical models:

- `gpt-4o`
- `gpt-4o-mini`

### OpenRouter

Aggregator path for many upstream providers.

```bash
export OPENROUTER_API_KEY=...
```

Model names usually include the upstream provider:

```text
anthropic/claude-sonnet-4
openai/gpt-4o-mini
google/gemini-2.5-flash
```

### Gemini

Google Gemini models.

```bash
export GEMINI_API_KEY=...
```

Gemini remains important for:

- large context windows
- native Google-side capabilities

### DeepSeek

```bash
export DEEPSEEK_API_KEY=...
```

Useful as another compatible fallback path for general chat/coding turns.

### MiniMax

```bash
export MINIMAX_API_KEY=...
```

Typical current model naming in the runtime/docs:

- `MiniMax-M2.7`

### Ollama

Local server path, no hosted API key required:

```bash
export OLLAMA_BASE_URL=http://127.0.0.1:11434
```

Then choose a local model in session preferences or instance defaults.

## Choosing a Default

Practical recommendations:

| Goal | Recommended default |
|------|---------------------|
| Tool-heavy daily use | `zai-coding / glm-4.7` |
| Broad hosted fallback coverage | `openrouter / <provider/model>` |
| Google ecosystem and large context | `gemini / gemini-2.5-flash` |
| Local-only setup | `ollama / <local-model>` |

## Changing Models

Use the interactive model menu in chat:

```text
/models
```

Or set a concrete preference directly in memory:

```toml
provider = "zai-coding"
model = "glm-4.7"
```

## Related

- [Configuration Reference](../reference/configuration.md)
- [Provider Port API](../reference/provider_port.md)
- [Quickstart](../quickstart.md)
