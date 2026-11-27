# Providers
Current provider model for the SQLite-first runtime.

## Overview

Donkey talks to LLMs through a unified provider layer. Credentials come from
environment variables in `~/.config/donkey/donkey.env`, while
`default_provider` and `default_model` live in `~/.config/donkey/donkey.toml`.

Typical flow:

1. Instance defaults come from `donkey.toml`.
2. Per-user overrides live in `PREFERENCES.md`.
3. With no explicit preference, smart routing builds an ordered candidate list
   and failover walks it; feedback, circuit breakers and cooldowns can demote or
   skip a provider. The list itself is assembled from fixed provider groups,
   not from a generic "any compatible provider" scan (see Architecture).

The normal happy path is:

```bash
nimble build
./donkey setup
./donkey doctor
./donkey start
```

## Supported Providers

| Provider | Env var | Default model | Streaming | Tool calling |
|----------|---------|---------------|-----------|--------------|
| ZAI Coding | `ZAI_CODING_API_KEY` | `glm-4.7` | No (complete only) | Yes |
| ZAI Anthropic | `ZAI_ANTHROPIC_API_KEY` | Anthropic-compatible Claude models | Yes | Yes |
| ZAI generic | `ZAI_API_KEY` | `glm-4.7` | No (complete only) | Yes |
| Anthropic | `ANTHROPIC_API_KEY` | `claude-sonnet-5-5` | Yes | Yes |
| OpenAI | `OPENAI_API_KEY` | `gpt-6.2-sol` | Yes* | Yes |
| OpenRouter | `OPENROUTER_API_KEY` | `openai/gpt-6.1-sol` | Provider-dependent | Provider-dependent |

\* Tool calling means "over the Chat Completions wire". A model that only
exposes function calling through the Responses API is not covered by the compat
path; the table describes the transport, not every model's API surface.
| Gemini | `GEMINI_API_KEY` | `gemini-3.8-flash` | No (complete only) | Yes |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-flash` | Yes | Yes |
| MiniMax | `MINIMAX_API_KEY` | `MiniMax-M3` | No (complete only) | Yes |
| Groq | `GROQ_API_KEY` | `openai/gpt-oss-120b` | Yes | Yes |
| OpenCode Go | `OPENCODE_API_KEY` or `OPENCODE_GO_API_KEY` | `opencode/deepseek-4.1-flash` | Yes | Yes |
| OpenCode Zen | `OPENCODE_API_KEY` or `ZEN_API_KEY` | `zen/deepseek-4.1-flash` | Yes | Yes |
| NVIDIA NIM | `NVIDIA_API_KEY` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | Yes | Yes |
| Alibaba DashScope | `DASHSCOPE_API_KEY` | `qwen3.8-max` | Yes | Yes |
| Fireworks AI | `FIREWORKS_API_KEY` | `accounts/fireworks/models/kimi-k2p6` | Yes | Yes |
| Azure OpenAI | `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` | your deployment name (`gpt-4.1` if unset) | Yes | Yes |
| Ollama | no API key | local models | Yes | Limited by server/model |

The default strings live in `src/donkey/core/providers/provider_defaults.nim`;
the descriptor table references them instead of repeating literals.

The Streaming and Tool calling columns describe what `buildProviderBundle`
actually wires. Every `ptOpenAiChat` descriptor that goes through
`CompatAdapter` gets a `streamFn`, and its `caps` reports `streaming: true` and
`toolCalling: true` for the provider as a whole; that is not a per-model
verification. ZAI Coding, ZAI generic, Gemini and MiniMax currently return only
`completeFn` from the bundle (MiniMax's `caps` still says `streaming: true`,
which overstates the wiring). OpenRouter and Ollama depend on the upstream
server or model.

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
NVIDIA_API_KEY=...
DASHSCOPE_API_KEY=...
FIREWORKS_API_KEY=...
BRAVE_API_KEY=...   # optional, enables web_search
```

Endpoint overrides, when the provider documents one, are separate env vars read
at request time: `NVIDIA_BASE_URL` and `DASHSCOPE_BASE_URL` today. Fireworks has
no descriptor `baseUrlEnv`.

Azure OpenAI needs both its key and its resource URL; it is enabled only when
both are set. It uses Microsoft's v1 API (`{resource}/openai/v1/chat/completions`,
no `api-version`), sends the key in the `api-key` header, and takes the model as
the **deployment name** you created in Azure:

```bash
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_ENDPOINT=https://<resource>.openai.azure.com
```

and in the preferences, `provider = "azure"` with `model = "<deployment>"`.
`AZURE_OPENAI_ENDPOINT` may also be the `/openai/v1` base or the full chat
completions URL; it must be https.

`donkey doctor` reports which providers are currently enabled by env.

### Multiple Keys and Rotation

Any provider key can carry a pool by adding the plural env next to it:

```bash
OPENAI_API_KEY=key-a
OPENAI_API_KEYS=key-a,key-b,key-c
```

Selection is round-robin over healthy keys. A key that returns `401`, `403`,
`429`, an invalid-key or a quota error cools down (1 min for rate limits,
15 min for quota, 30 min otherwise) and the next request uses another one.
When the error is key-specific, the same request is retried once per untried
healthy key before the provider fallback moves on. Transport and payload
errors do not rotate: they are not the key's fault.

The plural env alone also marks the provider as available, so a pool does not
need a duplicate single key.

> **OAuth is not implemented.** It is a long-term TODO, deferred by the
> maintainer on 18/11/2026 (the providers PRD, §6.1; in git history since `tasks/` was removed). Every provider in the
> descriptor table is `atApiKey` or `atNone` (local endpoint); there is no
> device-code flow, token store, refresh path or OAuth adapter in the codebase.
> Do not plan around one being available.
>
> The PRD records Nous Portal device-code as the only provider in the surveyed
> upstream (`nous`, Hermes) with `auth_type="oauth_device_code"`. The flow shape
> is documented there, but the blocking issue is client identity: the public
> `hermes-cli` client belongs to Hermes, so reusing it would impersonate another
> client. Until Donkey has its own registered client (or written authorization),
> zero OAuth code. The key pool above is what actually applies today.

## Per-user Overrides

Each user/session can override provider and model in `PREFERENCES.md`:

```toml
provider = "minimax"
model = "MiniMax-M2.7"
```

That affects normal conversation turns, heartbeat turns, and follow-up tool
turns for that user.

## Smart Routing and Fallbacks

When a session has no explicit provider/model preference, `smartRouteSelections`
builds the candidate list from **fixed provider groups**, in order:

- signals: inline image, long input (`60_000` approximate chars), thinking
  level and tool use;
- each branch appends providers that the catalog accepts for that signal;
- a general fallback block closes the list, then duplicates are removed.

Each candidate's model comes from `defaultModelForProvider`: the first catalog
entry for the provider, or a per-id/alias fallback `case` in `smart_routing.nim`.
Failover walks the list; if a provider errors, the next candidate is tried, and
optional feedback, circuit-breaker and cooldown hooks can reorder or skip
entries.

Two consequences worth knowing:

- The instance default is applied to the session's preferences
  (`applyProviderDefaults`) and supplies empty models, but the auto path does
  **not** start from an "instance default provider".
- NVIDIA, Alibaba and Fireworks are not in any signal group, so auto routing
  will not pick them today. Select them explicitly in `PREFERENCES.md` or in
  `/models`.

This still means you can keep one preferred provider and configure secondary
keys such as OpenRouter or Gemini for resilience.

## Image Input

`inspect_image` reads a local file, base64-encodes it as a data URL and sends
it to the active provider. It applies the same policy as inbound inline
images (`domain/providers/media_pure.nim`):

- **Formats:** only the extensions `.jpg`/`.jpeg`, `.png`, `.gif` and `.webp`
  are accepted, mapping to `SupportedImageMimes`
  (`image/jpeg`, `image/png`, `image/gif`, `image/webp`). SVG is deliberately
  excluded: it is a script-carrying document, not an image the providers agree
  to inline.
- **Size:** `MaxInlineImageEncodedBytes` is 5 MiB of **encoded** data. The limit
  is checked from the file size before reading (`raw * 4 / 3`), because base64
  grows the payload by about a third, and again on the built data URL. This is
  a change in practice: a 4–5 MB JPEG that used to pass can now be refused with
  "image file too large to inline". Downscale the file before calling the tool;
  the raw file must stay under about 3.9 million bytes (3.75 MiB) to fit the
  encoded budget.

`HEIC`, `BMP` and `SVG` are not supported for vision. `inspect_image` rejects
them with "unsupported image type". An inbound image in one of those formats is
still saved, but its attachment marker says the format is unsupported for
vision and points at the bytes on disk (`fs_read`/`text_read`), **not** at
`inspect_image`. For supported formats the marker also points at the saved
file, because the bytes are on disk whether or not they were inlined; when the
image was inlined, the marker says so and suggests `inspect_image` only for
detail (crop/zoom). An oversize attachment is saved the same way, but
`inspect_image` enforces the same encoded limit and will refuse it too —
downscale first.

The same `imageUrl` path serves any turn whose message carries an inline image.

| Provider family | Envelope |
|---|---|
| Anthropic | `image` block with a `base64` source (data URL) or a `url` source (http/https) |
| Gemini | `inlineData` part with `mimeType` + base64 `data` |
| OpenRouter, OpenAI, DeepSeek, Zhipu, MiniMax, NVIDIA | OpenAI-compatible `image_url` part |

Only `image/jpeg`, `image/png`, `image/gif` and `image/webp` are accepted
inline. A URL the provider cannot fetch (Gemini does not fetch arbitrary
http URLs) or a malformed data URL is dropped so the turn keeps its text.

A compat profile with `supportsImages = false` removes every image before the
body is built; text is untouched. That is the current state for Alibaba and
Fireworks (vision unverified). NVIDIA keeps images (`supportsImages = true`),
including on messages that also carry tool calls. As a last resort, a turn
whose providers all reject the image is retried once as text
(`buildCompleteFn` / `buildAsyncCompleteFn`).

## Audio Tools

`transcribe_audio` and `text_to_speech` speak the OpenAI-compatible audio
wire format (`/v1/audio/transcriptions` and `/v1/audio/speech`). They reuse
`OPENAI_API_KEY` when no dedicated key is set:

```bash
DONKEY_STT_API_KEY=...        # optional, falls back to OPENAI_API_KEY
DONKEY_STT_URL=https://api.openai.com/v1/audio/transcriptions
DONKEY_STT_MODEL=whisper-1
DONKEY_TTS_API_KEY=...
DONKEY_TTS_URL=https://api.openai.com/v1/audio/speech
DONKEY_TTS_MODEL=tts-1
DONKEY_TTS_VOICE=alloy
```

Transcription uploads the file as multipart (25 MB limit) and returns the
text. Speech writes the returned bytes to `attachments/tts-*.mp3` and returns
the path, so a later tool or reply can reference the file.

## Provider Architecture

Providers are split into four layers, each with one owner:

| Layer | Where | Owns |
|---|---|---|
| Descriptor | `src/donkey/domain/providers/descriptors.nim` | id, transport, auth type, ordered env names, base URL and `baseUrlEnv`, default model, aliases, aggregator flag |
| Profile | `src/donkey/domain/providers/profile_<id>.nim` and `compat.nim` | the provider's deltas as data: endpoint, headers, payload/reasoning extras, vision flag, quirks |
| Transport | `src/donkey/domain/providers/openai_pure.nim` + `compat.nim`, `anthropic_pure.nim`, `gemini_pure.nim`, `ollama_pure.nim` | the wire shape and its quirks |
| Adapter | `src/donkey/adapters/provider/*.nim` | HTTP, headers, streaming, response parsing |

For an OpenAI-compatible provider the request flows: the descriptor resolves the
identity and default model (`buildProviderSpec`) → `buildProviderBundle` picks
the `CompatAdapter` → `profileFn()` builds a fresh `CompatProfile` →
`buildCompatRequestBody` renders the OpenAI shape (with `OpenAiWireQuirks`) →
the adapter posts it. The profile is rebuilt per request because it owns
`JsonNode`s that must not cross a thread.

The OpenAI-compatible transport is the default. A provider expresses only its
deltas, never a copied serializer:

- `payloadExtras` — always merged (MiniMax `reasoning_split`);
- `reasoningExtras` — merged only when the turn asks for reasoning (Zhipu
  `thinking`);
- `reasoningOffExtras` — merged only when the turn does not ask for reasoning
  (Fireworks `reasoning_effort: "none"`);
- `streamExtras` — merged only for a streaming request (OpenRouter
  `stream_options.include_usage`);
- `extraHeaders` — provider-mandated headers (OpenRouter, Fireworks, the hosted
  NVIDIA endpoint);
- `OpenAiWireQuirks` — tool-result `name`, empty content, image/text ordering,
  image vs tool-call precedence, `tool_choice: auto`, omitting `stream`,
  `include_reasoning`, and empty-content preservation.

What stays provider-specific, and why:

- **Response parsing** — error envelopes differ (Zhipu, MiniMax, OpenRouter);
  the parsers remain in their adapters and are tested there.
- **SSE** — OpenRouter's tool-call deltas and reasoning chunks are richer than
  the OpenAI stream; its parser stays module-level.
- **Anthropic, Gemini and Ollama** — separate transports; their pure modules
  own the wire format.

### What the descriptor actually drives

These surfaces read `providerDescriptors()` (or `descriptorOr(id)`) and need no
per-provider edit:

- `doctor` rows: ids, order and the first env name come from the table
  (`doctorProviderRows`); only the label is curated.
- `setup` provider ids: every descriptor appears in the menu, curated ids first,
  then the rest in descriptor order (`setupProviderIds`).
- the service env template and `serviceEnvKeys` (`app/service_handler.nim`);
- route-cost provider ids (`src/donkey.nim`, `routeCostProviderIds`);
- credential detection and pools (`app/credential_runtime.nim`:
  `providerConfigured`, `descriptorApiKey` — single env and the plural
  `*_KEYS` form);
- endpoint override (`adapters/provider/runtime_builder.nim`,
  `providerEndpointFor`: `baseUrlEnv` wins, `/chat/completions` is appended for
  `ptOpenAiChat`, a complete endpoint is left alone);
- identity, aliases and the default model in `buildProviderSpec`
  (`app/session_bootstrap.nim`).

That covers the *identity* of a provider. It does not cover the executable
parts below.

### Adding a provider: the real checklist

A provider is not added once. The descriptor is the source of truth for
identity, but a new provider still needs a factory branch, an availability
field, a catalog entry, labels and tests. Skipping a step fails in a different
place:

| # | What | File | Descriptor-driven? |
|---|------|------|--------------------|
| 1 | Default model constant | `src/donkey/core/providers/provider_defaults.nim` | No — a product choice |
| 2 | Descriptor row | `src/donkey/domain/providers/descriptors.nim` | This *is* the table |
| 3 | Compat profile (only when not plain OpenAI) | `src/donkey/domain/providers/profile_<id>.nim` | No — the deltas are hand-written data |
| 4 | Factory branch + env-aware profile | `src/donkey/adapters/provider/runtime_builder.nim` | No — `case` over adapter types |
| 5 | Availability | `smart_routing.nim`, `app/session_bootstrap.nim` | No — fixed object, one field per provider |
| 6 | Catalog entry | `src/donkey/core/providers/provider_catalog.nim` | No — curated cost/capabilities |
| 7 | Operator labels | `app/doctor.nim`, `app/setup_wizard.nim` | Partly — ids/env yes, text no |
| 8 | Tests | conformance, golden, bundle, surface | No |

1. **Default model.** Add `DefaultModel<Provider>*` to
   `core/providers/provider_defaults.nim`. Both the descriptor table and
   `smart_routing` read this file, so the string exists once.
2. **Descriptor row.** `ProviderDescriptor(id, transport, authType, envNames,
   baseUrl, baseUrlEnv, defaultModel, aliases, aggregator)`. `envNames` is an
   ordered fallback list; `baseUrlEnv` is empty when the provider has no
   documented endpoint override. Aliases must not collide with another id.
   Unknown ids resolve to `zai-coding` (`descriptorOr`), which is why a typo in
   a preference silently changes provider.
3. **Profile** (skip when `defaultOpenAiProfile()` is correct). Add
   `profile_<id>.nim` with a zero-argument constructor named after the provider
   (`nvidiaCompatProfile*()`, `alibabaCompatProfile*()`,
   `fireworksCompatProfile*()`) and, when tests or a proxy need an explicit
   endpoint, a `<id>CompatProfileAt*(endpoint)` twin. Names only the deltas: `supportsImages`,
   `extraHeaders`, `payloadExtras`, `reasoningExtras`, `reasoningOffExtras`,
   `streamExtras`, `quirks`. It must stay pure data: no I/O, no HTTP client, no
   serializer copy.
4. **Factory branch.** In `buildProviderBundle`
   (`adapters/provider/runtime_builder.nim`) add a `case` arm for the canonical
   id that calls `newCompatAdapter` with the profile. If `baseUrlEnv` is
   non-empty, also add a `<id>ProfileFromEnv()` proc that calls
   `providerEndpointFor(id)`: `CompatProfileFn` is a top-level `nimcall`, so the
   endpoint cannot be captured in a closure. A missing arm falls through to the
   Zhipu `else` — the provider is "available" but talks the wrong wire.
5. **Availability.** Five edits: `ProviderAvailability` field, `isAvailable`
   case and `availableProviders` in `core/providers/smart_routing.nim`;
   `detectProviderAvailability` and `availableProviderNames` in
   `app/session_bootstrap.nim`. `defaultModelForProvider` in the same
   `smart_routing.nim` also carries a per-id/alias fallback `case`;
   `detectProviderAvailability` lives in `app/credential_runtime.nim`, and the
   dashboard maps the field in `domain/gateway/dashboard_pure.nim`. Without
   the availability field the router never selects the provider.
6. **Catalog/status.** Register the default model in
   `provider_catalog.buildDefaultCatalog` so `/models` and catalog queries see
   it without a live `/models` fetch. The entry also carries what the
   descriptor does not: cost tier, budget priority and `mc*` capabilities. For
   a new provider leave `contextWindow` at 0 unless a source proves it; the
   existing non-zero entries predate `model_limits` (see Model Limits).
7. **Labels.** Add the provider to `ProviderKeyLabels` (`app/doctor.nim`) and
   `ProviderMenu` (`app/setup_wizard.nim`). Both fall back to the descriptor id
   when the label is missing; the text and menu order are curated on purpose.
8. **Tests.** One row in `tests/domain/providers/t_compat_conformance.nim`,
   one golden body test (`tests/domain/providers/t_compat_<id>.nim`), one
   bundle test (`tests/provider/t_<id>.nim`) and, for the surfaces, an assertion
   in `tests/app/t_provider_breadth_surface.nim`.

`buildBody` on the compat adapters remains a thin test seam over
`buildCompatRequestBody`; it is not a second serializer.

### Reasoning extras

`CompatProfile.reasoningOffExtras` mirrors `reasoningExtras`. In
`buildCompatRequestBody` the merge order is: base body → `payloadExtras`
(always) → `reasoningExtras` if `req.reasoning` is true, otherwise
`reasoningOffExtras` → `streamExtras` when streaming. The two reasoning nodes
are therefore mutually exclusive, and `reasoningOffExtras` is merged on every
non-reasoning turn.

`req.reasoning` is the `showReasoning` switch derived from channel preferences
(`prefs.reasoning == "on"`, on by default). It is not a provider effort level.
Fireworks is the only profile using the hook today: reasoning off sends
`reasoning_effort: "none"`; reasoning on sends no effort field at all.

Deliberately not supported:

- **Streamed reasoning deltas.** `parseOpenAISseLine` reads content and usage;
  `delta.reasoning` is ignored. Compat streaming returns text only. Non-streaming
  replies still have `reasoning_content` parsed by `openai_pure`.
- **Effort levels.** `CompletionRequest` has no effort field, so `low`,
  `medium` and `high` have no wire mapping. The `thinking` routing preference
  only orders candidates; it never becomes a payload field.
- **`include_reasoning` as provider behavior.** It is a Donkey extension
  (`OpenAiWireQuirks.includeReasoningField`). Setting it false only stops Donkey
  from sending the field; it says nothing about what the provider does.

## AWS Bedrock (Converse)

Bedrock has its own adapter (`adapters/provider/bedrock.nim`, transport
`ptBedrockConverse`); the request and response translation is pure
(`domain/providers/bedrock_pure.nim`).

```bash
# either a Bedrock API key …
export AWS_BEARER_TOKEN_BEDROCK=...
# … or IAM credentials, signed with SigV4
export AWS_ACCESS_KEY_ID=...  AWS_SECRET_ACCESS_KEY=...  # AWS_SESSION_TOKEN optional
export AWS_REGION=us-east-1   # then AWS_DEFAULT_REGION, then us-east-1
```

- The bearer wins when both are set. SigV4 is hand-written
  (`core/security/aws_sigv4.nim`, service `bedrock`) and checked against the
  example AWS publishes; the model id is a path segment, so its `:` is
  encoded once in the URL and once more in the canonical URI.
- `BEDROCK_BASE_URL` replaces the regional endpoint (a proxy, a VPC endpoint).
- Default model `amazon.nova-pro-v1:0`; any Converse model id works, including
  regional inference profiles (`us.anthropic.claude-…`).
- Converse is strict about shape: roles alternate and start with a user turn,
  tool results ride in a user turn, empty text blocks are dropped, tool ids are
  made valid (`[a-zA-Z0-9_-]{1,64}`, the same way on both sides of a pair), and
  without tools in the request the history's tool blocks become text (Converse
  rejects them without `toolConfig`). Images go as bytes; URL images are not
  sent.
- Vision: Claude and Nova Pro/Lite/Premier yes, Nova Micro no, others unknown.
- Not implemented: ConverseStream (AWS binary event-stream framing). The
  bundle has no `streamFn`, so turns run without streaming.

## Compat Breadth: NVIDIA, Alibaba, Fireworks, Mistral

Four OpenAI-compatible providers were added through the generic
`CompatAdapter`. None has its own adapter file; each contributes a descriptor
row and a pure profile.

| Provider | Endpoint (hosted) | Default model | Vision | Verified limits |
|---|---|---|---|---|
| `nvidia` (NIM) | `https://integrate.api.nvidia.com/v1/chat/completions` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | Yes | tools, vision, 16384 output; context unknown |
| `alibaba` (DashScope) | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions` | `qwen3.8-max` | No (unverified) | unknown |
| `fireworks` | `https://api.fireworks.ai/inference/v1/chat/completions` | `accounts/fireworks/models/kimi-k2p6` | Per model (unverified) | unknown |
| `mistral` | `https://api.mistral.ai/v1/chat/completions` | `mistral-large-latest` | Pixtral yes; others unverified | unknown |

Vision is decided per provider and model before each call
(`media_pure.visionSupport`; see `docs/topics/media.md`). The compat
transport sends the images it is given.

### Mistral AI

```bash
export MISTRAL_API_KEY=...
```

- `MISTRAL_BASE_URL` moves the endpoint (same rule as `NVIDIA_BASE_URL`).
- The API is strict: unknown fields are a 422, so the Donkey-only
  `include_reasoning` is never sent.
- A tool id must be exactly 9 alphanumerics. The `shortToolIds` quirk maps any
  other id (Donkey's own, or another provider's before a fallback) through a
  deterministic hash, on the wire copy only; both sides of a call/result pair
  get the same id and the stored history keeps the original.

### NVIDIA NIM

```bash
export NVIDIA_API_KEY=...
```

- Hosted endpoint above; `NVIDIA_BASE_URL` is consumed by
  `providerEndpointFor`. Set it to a base such as
  `http://localhost:8000/v1` and Donkey appends `/chat/completions`; a value
  that is already a complete endpoint is used unchanged.
- `X-BILLING-INVOKE-ORIGIN: Donkey` is attached **only** when the resolved
  endpoint equals the hosted descriptor URL. A local or proxied NIM endpoint
  never claims `build.nvidia.com` billing.
- Vision is on (`NvidiaSupportsImages = true`). The citation carried in
  `profile_nvidia.nim` and `model_limits.nim` is the upstream provider doc:
  Nemotron 3.5 Super VL "supports text and image inputs, reasoning, and tool
  calls" (`hermes:providers.md:517-518`). Images stay attached even on messages
  that also carry tool calls.
- NIM receives no `name`/`tool_name` on tool results (`toolResultName = false`)
  and no `include_reasoning` (Donkey extension switch). The profile expects
  reasoning text in `reasoning_content`, the field `openai_pure` already reads;
  the exact response envelope is not verified (PRD §11).
- Aliases: `nvidia-nim`, `nim`, `build-nvidia`. `nemotron` is deliberately not
  an alias.

### Alibaba DashScope (Qwen Cloud)

```bash
export DASHSCOPE_API_KEY=...
```

- International endpoint under `compatible-mode`
  (`https://dashscope-intl.aliyuncs.com/compatible-mode/v1/...`).
  `DASHSCOPE_BASE_URL` is consumed the same way as `NVIDIA_BASE_URL`.
- Default `qwen3.8-max` is the first of the curated upstream list
  (`hermes_cli/models_catalog_static.py:209-212`). The upstream docs example
  uses `qwen3.5-plus` (`hermes:providers.md:259-260`); the code follows the
  catalog's first entry, and the PRD records the divergence as an open question
  (§11).
- Vision is **off** because it is not verified, not because the model is known
  to reject images. `AlibabaSupportsImages = false` and the request builder
  suppresses every image (text is kept). Unverified is not a promise either
  way.
- `preserve_thinking` is **not** sent. The key exists to replay a previous
  turn's reasoning into the next request, and this transport never sends a
  `reasoning` field back in the message history. Sending it without replay
  would be inert; the debt is recorded in PRD §11.
- Aliases: `dashscope`, `alibaba-cloud`, `aliyun`. `qwen` is not an alias.

### Fireworks AI

```bash
export FIREWORKS_API_KEY=...
```

- Hosted endpoint above; the descriptor has `baseUrlEnv: ""`, so no
  `*_BASE_URL` override is read.
- Every request carries Donkey's attribution headers: `HTTP-Referer`,
  `X-Title: Donkey` and `User-Agent: Donkey`. The values are Donkey's, never
  Hermes'.
- Default `accounts/fireworks/models/kimi-k2p6` is a **Donkey choice**: it is
  the first entry of the upstream `fallback_models`, not Hermes'
  `default_aux_model` (`accounts/fireworks/models/glm-5p2`). The rationale is
  in `provider_defaults.nim`.
- Reasoning off sends top-level `reasoning_effort: "none"`, matching the
  upstream mapping of `enabled=false`; the nested `extra_body.reasoning`
  fallback is rejected by Fireworks. Reasoning on sends no effort field,
  because `CompletionRequest` has no effort level.
- Vision and limits are unverified: images are suppressed and `modelLimits`
  returns `mlsUnknown`.
- Aliases: `fireworks-ai`, `fw`.

## Model Limits

`src/donkey/domain/providers/model_limits.nim` is the designated single source
for context window, max output tokens, vision and tool support per exact
`(provider, model)` pair. It is a pure `func` over a `const` table sorted by
`(provider, model)`, searched with a binary search; provider ids are trimmed
and case-folded, model ids are exact.

- `ModelLimitSource` is `mlsVerified` (with a non-empty `sourceRef`),
  `mlsDescriptor` (defaults published by a descriptor) or `mlsUnknown`.
  `mlsUnknown` is the first enum value, so a default-initialized struct is
  conservative instead of accidentally "verified".
- A known provider with an unlisted model does **not** inherit a provider
  default. Only the exact pair matches.
- **0 / false is a recorded fact**, not a missing implementation and not
  "unlimited": it means no source proves the value. Absence never becomes a
  promise of context, output, vision or tools.
- Current table: one verified row, NVIDIA's default model — context `0` (no
  source states Nemotron's context window), output `16384`
  (`hermes:plugins/model-providers/nvidia/__init__.py:31`), vision and tools
  true, `sourceRef` citing the upstream paths. Alibaba, Fireworks and every
  other provider/model pair are `mlsUnknown`.

**Wiring status.** The table is authoritative as a declaration, but its
propagation is still pending in this tree: `CompatAdapter.caps` returns
`maxContextTokens: 0` and neither `provider_catalog` nor `smart_routing`
imports `model_limits` today (PRD US-005 intended that link). The catalog still
carries its own `contextWindow` values for the pre-existing providers, and
catalog queries read those; for NVIDIA, Alibaba and Fireworks the catalog
records 0, so both sources agree on "unknown". Do not expect context-aware
routing for these three yet.

Vision, by contrast, *is* enforced: a profile with `supportsImages = false`
drops images before the request is built. The image branch in
`smartRouteSelections` is still a fixed provider list and does not consult the
catalog's `mcImage`, so NVIDIA's `mcImage` entry does not put it in the image
group.

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

Models in the catalog:

- `claude-sonnet-5-5`
- `claude-opus-5-5`
- `claude-haiku-5-5`
- `claude-fable-5-2`

### OpenAI

GPT models via OpenAI.

```bash
export OPENAI_API_KEY=...
```

Models in the catalog:

- `gpt-6.2-sol` (default)
- `gpt-6.2-astra`
- `gpt-6.1-terra`
- `gpt-6-luna`

### OpenRouter

Aggregator path for many upstream providers.

```bash
export OPENROUTER_API_KEY=...
```

Model names usually include the upstream provider:

```text
anthropic/claude-sonnet-5-5
openai/gpt-6-luna
google/gemini-3.8-flash
```

### Gemini

Google Gemini models.

```bash
export GEMINI_API_KEY=...
```

Gemini remains important for:

- large context windows (the catalog records `1_048_576` for these models)
- native Google-side capabilities

Models in the catalog: `gemini-3.8-flash` (default), `gemini-4-hydrogen`,
`gemini-4-argon`, `gemini-3.5-flash-lite`. Google routes `gemini-2.5-pro` and
`gemini-2.5-flash` to newer models from 1 December 2026.

### DeepSeek

```bash
export DEEPSEEK_API_KEY=...
```

Useful as another compatible fallback path for general chat/coding turns.
Models in the catalog: `deepseek-flash` (default, V4.1 Flash), `deepseek-v4-pro`.
DeepSeek announced the end of `deepseek-chat` and `deepseek-reasoner` for 24 July 2026.

### MiniMax

```bash
export MINIMAX_API_KEY=...
```

Models in the catalog: `MiniMax-M3` (default), `MiniMax-M2.5`,
`MiniMax-M2.7`, `MiniMax-M2.7-highspeed`.

### NVIDIA NIM

```bash
export NVIDIA_API_KEY=...
```

Hosted NIM, vision on, `NVIDIA_BASE_URL` for local or proxied deployments. See
[Compat Breadth](#compat-breadth-nvidia-alibaba-fireworks) for the billing
header, verified limits and aliases.

### Alibaba DashScope

```bash
export DASHSCOPE_API_KEY=...
```

Qwen Cloud through the international `compatible-mode` endpoint. Vision is not
verified and images are suppressed; see
[Compat Breadth](#compat-breadth-nvidia-alibaba-fireworks).

### Fireworks AI

```bash
export FIREWORKS_API_KEY=...
```

OpenAI-compatible endpoint with Donkey attribution headers and
`reasoning_effort: "none"` when reasoning is off. The default model is a Donkey
choice, not an upstream default; see
[Compat Breadth](#compat-breadth-nvidia-alibaba-fireworks).

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
| Google ecosystem and large context | `gemini / gemini-3.8-flash` |
| Verified vision on a hosted endpoint | `nvidia / nvidia/nemotron-3.5-super-vl-120b-a12b` |
| Local-only setup | `ollama / <local-model>` |

The three compat-breadth providers are explicit choices: they are not in the
auto-routing signal groups, and their limits are unknown except for NVIDIA's
verified output cap, vision and tool support (its context window is still
unknown).

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
