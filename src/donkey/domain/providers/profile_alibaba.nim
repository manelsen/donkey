## profile_alibaba.nim — Alibaba DashScope (Qwen Cloud) compat profile.
##
## Data only: the endpoint, the OpenAI quirks and the vision flag. The
## transport lives in `adapters/provider/compat_adapter.nim`; there is no
## Alibaba-specific adapter.
##
## Verified against Hermes (read-only): `hermes_cli/auth.py:212-213`
## (DASHSCOPE_API_KEY, intl endpoint, DASHSCOPE_BASE_URL),
## `plugins/model-providers/alibaba/__init__.py:22-25` (aliases),
## `website/docs/integrations/providers.md:36,259-260`,
## `hermes_cli/models_catalog_static.py:209-212` (`qwen3.8-max` is first).
##
## Vision is decided per model (media_pure.visionSupport).
##
## `preserve_thinking` (Model Studio's Chat Completions reference,
## alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions):
## for the models it lists, the reasoning_content of historical assistant
## messages is read as model input. Those models get the parameter and the
## earlier turns' reasoning in `reasoning_content` (never concatenated into
## the content; a turn without reasoning carries no field, which the reference
## says is not an error). Kimi K3 on Model Studio keeps client reasoning by
## default: echoed, no parameter. Everything else is unchanged.
##
## Pure: no I/O, no network, no JsonNode construction.

import std/[json, strutils]
import ../../core/providers/provider_defaults
import ./compat
import ./openai_pure

const
  AlibabaEndpoint* = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"

func alibabaCompatProfileAt*(endpoint: string): CompatProfile =
  ## The DashScope deviations from the OpenAI transport, at an explicit
  ## endpoint (tests, a regional gateway). Everything else is the OpenAI
  ## default; `includeReasoningField` is a Donkey extension switch, so DashScope
  ## gets no `include_reasoning`. DashScope returns reasoning in
  ## `reasoning_content`, which the response parser already reads.
  result = CompatProfile(
    id: "alibaba",
    endpoint: endpoint,
    supportsImages: true,  ## per-model decision: media_pure.visionSupport
    quirks: defaultOpenAiQuirks(),
  )
  result.quirks.includeReasoningField = false

const
  PreserveThinkingModels = [
    "qwen4-max", "qwen3.8-max", "qwen3.8-flash", "qwen3.8-omni-flash",
    "qwen3.7-max", "qwen3.7-plus", "qwen3.7-flash",
    "qwen3.6-plus", "qwen3.6-flash",
    "kimi-k2.6", "kimi-k2.7-code",
    "kimi/kimi-k2.7-code", "kimi/kimi-k2.7-code-highspeed",
    "kimi/kimi-k3.1-pro", "kimi/kimi-k3.1-pro-highspeed"]
    ## The reference's list: these take `preserve_thinking`.
  KeepsClientReasoning = ["kimi-k3", "kimi-k3.1-pro"]
    ## Model Studio's Kimi K3 and K3.1 Pro keep client reasoning by default:
    ## echoed, no parameter (Moonshot-direct `kimi/kimi-k3.1-pro` takes it).

func isListedModel(model: string; names: openArray[string]): bool =
  ## A listed name, or that name with a dated snapshot after it
  ## (`qwen3.6-plus-2026-04-02`, `qwen3.8-max-0902`); not any longer name
  ## (`qwen3.6-plus-preview` is another model).
  let m = model.toLowerAscii.strip
  for name in names:
    if m == name: return true
    if m.startsWith(name & "-"):
      let suffix = m[name.len + 1 .. ^1]
      if suffix.len >= 4 and suffix.allCharsInSet({'0' .. '9', '-'}):
        return true
  false

func alibabaPreservesThinking*(model: string): bool =
  model.isListedModel(PreserveThinkingModels)

proc alibabaCompatProfileFor*(endpoint, model: string): CompatProfile =
  ## The profile for one model: preserve_thinking and reasoning replay where
  ## the reference lists the model. `proc`: the extras are a JsonNode.
  result = alibabaCompatProfileAt(endpoint)
  if alibabaPreservesThinking(model):
    result.payloadExtras = %* {"preserve_thinking": true}
    result.quirks.replayReasoning = true
  elif model.isListedModel(KeepsClientReasoning):
    result.quirks.replayReasoning = true

func alibabaCompatProfile*(): CompatProfile =
  ## The profile the adapter/runtime builder passes as `profileFn`; zero-arg so
  ## it matches `CompatProfileFn` exactly.
  alibabaCompatProfileAt(AlibabaEndpoint)
