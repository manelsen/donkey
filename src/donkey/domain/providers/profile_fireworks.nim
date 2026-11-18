## profile_fireworks.nim — Fireworks AI compat profile.
##
## Data only: the endpoint comes from the descriptor row, the attribution
## headers are constant, and the provider's only reasoning switch is the
## top-level `reasoning_effort`. The transport is
## `adapters/provider/compat_adapter.nim`; there is no Fireworks adapter.
##
## Verified against Hermes (read-only):
##   - `hermes_cli/providers.py:75-76`: `FIREWORKS_API_KEY`, hosted base URL
##     `https://api.fireworks.ai/inference/v1`; there is no Fireworks
##     `*_BASE_URL` env var (the docs use `model.base_url` instead).
##   - `plugins/model-providers/fireworks/__init__.py:9-49`: aliases
##     `fireworks-ai`/`fw`; attribution headers (`HTTP-Referer`, `X-Title`,
##     `User-Agent`); `fallback_models[0]` is `kimi-k2p6`;
##     `enabled=false` is sent as top-level `reasoning_effort: "none"` because
##     Fireworks rejects the nested `extra_body.reasoning` fallback.
##   - `website/docs/integrations/providers.md:227-229,293`: slash-form model
##     ids and the default endpoint.
##   - `agent/transports/chat_completions.py:40-46,288`: Fireworks is named as a
##     strict provider that rejects `extra_content`; no source claims vision.
##
## Vision is **not** verified, so images are suppressed (PRD FR-3: absence is
## never a promise). `includeReasoningField = false` is a Donkey extension
## switch: Fireworks gets no `include_reasoning`. `req.reasoning = true` sends
## no effort either — `CompletionRequest` has no effort field (PRD §11).
##
## `reasoning_effort: "none"` is not accepted by every model on the service:
## Muse Spark Open rejects the value even with reasoning off. The off switch is
## therefore an allowlist of model ids, and a model that is not on it gets no
## effort field at all (review E2). Only the default model is verified in the
## Hermes sources above; a missing entry sends nothing, which is the safe
## failure for a model whose acceptance was never proven.
##
## Pure: no I/O, no network. The `JsonNode` is profile data, not transport code.

import std/json
import ../../core/providers/provider_defaults
import ./compat
import ./descriptors
import ./openai_pure

const
  FireworksReferer*   = "https://github.com/donkey-ai/donkey"
  FireworksTitle*     = "Donkey"
  FireworksUserAgent* = "Donkey"

  FireworksReasoningNoneModels* = [DefaultModelFireworks]
    ## Model ids that accept the top-level `reasoning_effort: "none"` off
    ## switch. Anything absent sends no effort field.

  MuseSparkOpenModel* = "accounts/fireworks/models/muse-spark-open"
    ## Rejects `reasoning_effort: "none"` with reasoning off (review E2).

func fireworksReasoningOffExtrasFor*(model: string): JsonNode =
  ## The off switch for one model, or nil when the model is not on the
  ## allowlist. `CompatProfile` is per bundle while the allowlist is per model,
  ## so the extras are chosen by the model the bundle will send.
  if model in FireworksReasoningNoneModels:
    %* {"reasoning_effort": "none"}
  else:
    nil

func fireworksCompatProfileAt*(endpoint: string;
                               reasoningOffExtras: JsonNode): CompatProfile =
  ## The Fireworks deviations from the OpenAI transport, at an explicit
  ## endpoint (tests, a proxy) and with the off switch of one model.
  ## Attribution headers are sent on every request; the values are Donkey's,
  ## never Hermes'.
  result = CompatProfile(
    id: "fireworks",
    endpoint: endpoint,
    extraHeaders: @[
      ("HTTP-Referer", FireworksReferer),
      ("X-Title", FireworksTitle),
      ("User-Agent", FireworksUserAgent),
    ],
    reasoningOffExtras: reasoningOffExtras,
    supportsImages: FireworksSupportsImages,
    quirks: defaultOpenAiQuirks(),
  )
  result.quirks.includeReasoningField = false

func fireworksCompatProfileAt*(endpoint: string): CompatProfile =
  ## The default model's profile, for callers that only name an endpoint.
  fireworksCompatProfileAt(endpoint,
                           fireworksReasoningOffExtrasFor(DefaultModelFireworks))

func fireworksCompatProfile*(): CompatProfile =
  ## The profile the adapter/runtime builder passes as `profileFn`; zero-arg so
  ## it matches `CompatProfileFn` exactly. The endpoint is the descriptor's, so
  ## there is one source of truth.
  fireworksCompatProfileAt(descriptorOr("fireworks").baseUrl)
