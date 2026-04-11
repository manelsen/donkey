# Contributing to Donkey

This guide covers the two main extension points: adding new **channels** (messaging platforms) and adding new **providers** (LLM APIs).

## Table of Contents

- [Adding a New Channel](#adding-a-new-channel)
- [Adding a New Provider](#adding-a-new-provider)
- [Adding a New Tool via MCP](#adding-a-new-tool-via-mcp)
- [Running Tests](#running-tests)

---

## Adding a New Channel

A channel is a messaging platform adapter (Telegram, Discord, Slack, etc.). Channels are implemented using hexagonal architecture: the **port** defines the contract, the **adapter** implements it.

### Step 1: Add the channel kind

Add your channel to the `ChannelKind` enum in `src/donkey/core/types.nim`:

```nim
ChannelKind* = enum
  ckTelegram
  ckDiscord
  # ... existing channels ...
  ckMyChannel   ## My new channel
```

### Step 2: Declare channel capabilities

Register your channel's capabilities in `src/donkey/ports/channel_capability.nim`. Add an entry to the registry:

```nim
proc channelCapabilityRegistry*(): ChannelCapabilityRegistry =
  # ... existing entries ...
  result[ckMyChannel] = NoReactionCapability  # or custom flags
```

The `ChannelCapabilityDescriptor` controls which outbound operations your channel supports:

| Flag | Description |
|------|-------------|
| `send` | Basic message send |
| `sendReturnId` | Send returns the created message ID |
| `editMessage` | Edit an existing message by ID |
| `sendKeyboard` | Send with inline keyboard |
| `editKeyboard` | Edit keyboard of an existing message |
| `setMessageReaction` | React to a message |

### Step 3: Implement the adapter

Create `src/donkey/adapters/channel/mychannel_runtime.nim`:

```nim
## MyChannel channel adapter.
## Implements ChannelPort for the MyChannel platform.

import std/[asyncdispatch, strutils, json, httpclient]
import ../../ports/channel
import ../../domain/message
import ../../core/types

type
  MyChannelAdapter* = object
    botToken*: string
    # ... adapter state ...

proc newMyChannelAdapter*(botToken: string): MyChannelAdapter =
  MyChannelAdapter(botToken: botToken)

# Implement required port methods
proc caps*(self: MyChannelAdapter): ChannelCapabilityDescriptor =
  capability(ckMyChannel)

proc sendMessage*(self: var MyChannelAdapter; msg: OutboundMessage): Result[string, string] =
  ## Send a message via MyChannel API.
  # ... HTTP call to MyChannel API ...
  ok("")

# Implement other ChannelPort methods as needed:
# editMessage, sendWithKeyboard, setMessageReaction, etc.
```

### Step 4: Register the channel

In `src/donkey.nim` (or the appropriate startup module), add your channel to the channel runtime builder:

```nim
of ckMyChannel:
  let token = getEnv("MYCHANNEL_BOT_TOKEN")
  # ... build and register adapter ...
```

### Step 5: Add environment variable

Document your channel's token in `README.md` under the environment variables table:

| Variable | Required | Description |
|----------|----------|-------------|
| `MYCHANNEL_BOT_TOKEN` | For MyChannel | MyChannel bot token |

### Step 6: Write tests

Create `tests/adapters/channel/t_mychannel.nim` and `tests/channel/t_mychannel.nim` for pure domain logic and adapter tests.

---

## Adding a New Provider

Providers are LLM API backends (OpenAI, Anthropic, Gemini, etc.). Donkey uses a **declarative ProviderCatalog** for routing, so adding a provider means registering models in the catalog and implementing the adapter.

### Step 1: Register models in the ProviderCatalog

Add your provider's models to `src/donkey/core/providers/provider_catalog.nim` in the `buildDefaultCatalog()` proc:

```nim
proc buildDefaultCatalog*(): ProviderCatalog =
  # ... existing registrations ...

  # ── MyProvider ──
  result.register(makeEntry(
    "my-model-v1", "myprovider",          # canonical name, provider name
    aliases = @["my-model", "model-v1"],  # alternative names
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctModerate,                # ctFree, ctVeryCheap, ctCheap, ctModerate, ctExpensive
    budgetPriority = bpDefault,           # bpDefault, bpHigh, bpLow
    contextWindow = 128_000,
  ))
```

The capabilities determine how smart routing uses your model:

| Capability | Description |
|------------|-------------|
| `mcTools` | Supports tool calling / function calling |
| `mcImage` | Supports image input |
| `mcThinking` | Supports extended thinking / chain-of-thought |
| `mcStreaming` | Supports token streaming |

### Step 2: Implement the provider adapter

Create `src/donkey/adapters/provider/myprovider.nim`:

```nim
## MyProvider adapter.
## Implements ProviderPort for the MyProvider API.

import std/[json, httpclient, strutils]
import ../../ports/provider
import ../../domain/message
import ../../core/pipeops

type
  MyProviderAdapter* = ref object of RootObj
    apiKey*: string
    model*: string
    client*: HttpClient

proc newMyProviderAdapter*(apiKey: string; model: string): MyProviderAdapter =
  MyProviderAdapter(
    apiKey: apiKey,
    model: model,
    client: newHttpClient(),
  )

proc complete*(self: MyProviderAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  ## Send a completion request to MyProvider API.
  try:
    # ... build HTTP request ...
    # ... parse response ...
    ok(CompletionResponse(text: "response text"))
  except Exception as e:
    err(e.msg)

proc caps*(self: MyProviderAdapter): ProviderCaps =
  ProviderCaps(
    name: "myprovider",
    streaming: true,
    toolCalling: true,
    nativeTools: @[],
    maxContextTokens: 128_000,
    requiresUserFirst: false,
  )

proc makeStreamFn*(self: MyProviderAdapter): StreamFn =
  ## Optional: return a streaming closure, or nil if not supported.
  nil  # or implement SSE streaming
```

### Step 3: Register the provider in the runtime builder

Add your provider to `src/donkey/adapters/provider/runtime_builder.nim`:

```nim
import myprovider

proc buildProviderBundle*(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
  case spec.providerName
  # ... existing providers ...
  of "myprovider":
    let adapter = newMyProviderAdapter(spec.apiKey, model = spec.modelName)
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
```

### Step 4: Add environment variable

Add your provider's API key to `~/.config/donkey/donkey.env` and document it in `README.md`:

| Variable | Required | Description |
|----------|----------|-------------|
| `MYPROVIDER_API_KEY` | For MyProvider | MyProvider API key |

### Step 5: (Optional) Add a model catalog loader

If your provider has a live REST API listing models, add a loader in `src/donkey/adapters/provider/model_catalog.nim`:

```nim
proc parseMyProviderCatalog(body: string): Result[seq[ModelCatalogEntry], string] =
  # Parse the JSON response and return ModelCatalogEntry entries
  ...

proc loadMyProviderCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("myprovider"))
  # Fetch from live API
  ...
```

### Step 6: Write tests

Create `tests/provider/t_myprovider.nim` for adapter tests and `tests/core/t_provider_catalog.nim` already covers catalog queries.

---

## Adding a New Tool via MCP

For adding external tools via the Model Context Protocol:

```bash
./donkey ctl tool install <mcp-server-command> [args...]
```

The tool will be available to all sessions automatically.

---

## Running Tests

```bash
# Run all tests
nimble test

# Run a single test file
nim c --mm:orc -u:withPostgres -r tests/core/t_smart_routing.nim

# Run tests with the full suite (recommended for PRs)
bash scripts/run_tests.sh
```

The quality gate for any change is:
- `nim c src/donkey.nim` must compile successfully
- All tests must pass (pre-existing failures in `tests/architecture/t_boundaries.nim`, `tests/core/t_telegram_format.nim`, etc. are tracked separately)

---

## Architecture Notes

- **Hexagonal architecture**: ports define contracts (Nim `concept` types), adapters implement them
- **Structural typing**: ports use Nim `concept` for duck typing
- **Pure core, impure shell**: domain logic and routing are pure; I/O lives in adapters
- **SQLite-first**: default memory backend is embedded SQLite + sqlite-vec

See [CLAUDE.md](CLAUDE.md) for AI-assistant development guidance.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full technical overview.
