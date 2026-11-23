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
## Vision is **not** verified, so images are suppressed: absence is never a
## promise (PRD FR-3). `preserve_thinking` stays out because the transport does
## not replay prior-turn reasoning (PRD US-003, §11).
##
## Pure: no I/O, no network, no JsonNode construction.

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

func alibabaCompatProfile*(): CompatProfile =
  ## The profile the adapter/runtime builder passes as `profileFn`; zero-arg so
  ## it matches `CompatProfileFn` exactly.
  alibabaCompatProfileAt(AlibabaEndpoint)
