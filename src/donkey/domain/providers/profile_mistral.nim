## profile_mistral.nim — Mistral AI compat profile.
##
## Data only. Mistral speaks the OpenAI chat dialect, strictly: unknown fields
## are rejected with 422 (hermes lists it with Groq and Cerebras among the
## strict routes, `agent/message_sanitization.py`), so the Donkey-only
## `include_reasoning` is off, and a tool id must be exactly 9 alphanumerics
## (hermes b33ed35968, 9a90a82502), which `shortToolIds` enforces on the wire.
## The transport is `adapters/provider/compat_adapter.nim`.
##
## Pure: no I/O, no network.

import ./compat
import ./descriptors
import ./openai_pure

export openai_pure.mistralToolId

func mistralCompatProfileAt*(endpoint: string): CompatProfile =
  ## The Mistral deviations from the OpenAI transport at an explicit endpoint
  ## (tests, `MISTRAL_BASE_URL`, a proxy).
  CompatProfile(
    id: "mistral",
    endpoint: endpoint,
    supportsImages: true,  ## per-model decision: media_pure.visionSupport
    quirks: OpenAiWireQuirks(
      toolResultName: true,
      imageWithToolCalls: true,
      includeReasoningField: false,
      shortToolIds: true,
    ),
  )

func mistralCompatProfile*(): CompatProfile =
  ## Zero-arg, so it matches `CompatProfileFn`; the endpoint is the
  ## descriptor's.
  mistralCompatProfileAt(descriptorOr("mistral").baseUrl)
