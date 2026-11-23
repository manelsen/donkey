## profile_nvidia.nim — NVIDIA NIM compat profile.
##
## Data only: the endpoint comes from the descriptor row, the billing header is
## scoped to the hosted endpoint, and the wire deviations live in the quirks.
## The transport is `adapters/provider/compat_adapter.nim`; there is no
## NVIDIA-specific adapter.
##
## Verified against Hermes (read-only):
##   - `hermes_cli/providers.py:62`: nvidia, `NVIDIA_BASE_URL`, hosted base URL
##     `https://integrate.api.nvidia.com/v1`.
##   - `plugins/model-providers/nvidia/__init__.py:12-24`: tool messages are
##     copied without `name`/`tool_name` before sending (the NIM quirk).
##   - `plugins/model-providers/nvidia/__init__.py:27-32`: `NVIDIA_API_KEY`,
##     aliases, `default_max_tokens=16384`.
##   - `website/docs/integrations/providers.md:513-573`: Nemotron 3.5 Super VL
##     "supports text and image inputs, reasoning, and tool calls"
##     (`:517-518`); hosted requests carry the NIM billing-origin header
##     (`:535-538`); local NIM uses `NVIDIA_BASE_URL` (`:546-560`).
##
## The descriptor's `baseUrlEnv` (`NVIDIA_BASE_URL`) is consumed by
## `runtime_builder.providerEndpointFor`, which builds this profile at the
## configured endpoint. The billing header is attached only when the endpoint is
## the hosted base URL, so a local/deployment endpoint never claims
## build.nvidia.com billing.
##
## Pure: no I/O, no network, no JsonNode construction.

import ../../core/providers/provider_defaults
import ./compat
import ./descriptors
import ./openai_pure

const
  NvidiaBillingHeaderName* = "X-BILLING-INVOKE-ORIGIN"
  NvidiaBillingHeaderValue* = "Donkey"

func nvidiaCompatProfileAt*(endpoint: string): CompatProfile =
  ## The NVIDIA deviations from the OpenAI transport, at an explicit endpoint
  ## (tests, local NIM, a proxy). `includeReasoningField` is a Donkey extension
  ## switch: NIM gets no `include_reasoning`, and the reasoning text comes back
  ## in `reasoning_content`, which the response parser already reads.
  result = CompatProfile(
    id: "nvidia",
    endpoint: endpoint,
    supportsImages: true,  ## per-model decision: media_pure.visionSupport
    quirks: OpenAiWireQuirks(
      toolResultName: false,
      imageWithToolCalls: true,
      includeReasoningField: false,
    ),
  )
  if endpoint == descriptorOr("nvidia").baseUrl:
    ## Billing attribution belongs to the hosted NIM only (PRD §11).
    result.extraHeaders = @[(NvidiaBillingHeaderName, NvidiaBillingHeaderValue)]

func nvidiaCompatProfile*(): CompatProfile =
  ## The profile the adapter/runtime builder passes as `profileFn`; zero-arg so
  ## it matches `CompatProfileFn` exactly. The endpoint is the descriptor's, so
  ## there is one source of truth.
  nvidiaCompatProfileAt(descriptorOr("nvidia").baseUrl)
