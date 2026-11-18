## model_limits.nim — verified context and capability facts per provider/model.
##
## This is the only place the runtime is allowed to learn a model's limits.
## Lookup is deterministic: one const table ordered by (provider, model) and a
## binary search, never hash-table iteration order. Everything the table does
## not prove stays 0/false/unknown: absence is not a promise of context,
## output, vision or tools (PRD FR-3).
##
## Pure: no I/O, no network, no exceptions, no catalog access.

import std/strutils
import ../../core/providers/provider_defaults

type
  ModelLimitSource* = enum
    ## `mlsUnknown` is first so a default-initialized `ModelLimits` is
    ## conservative rather than accidentally "verified".
    mlsUnknown     ## no verified fact; all fields stay 0/false/empty
    mlsDescriptor  ## defaults published by a provider descriptor
    mlsVerified    ## a documented provider/source states the value

  ModelLimits* = object
    contextWindow*:   int    ## input tokens; 0 = unknown, never a promise
    maxOutputTokens*: int    ## output tokens; 0 = unknown
    supportsVision*:  bool   ## image inputs accepted
    supportsTools*:   bool   ## tool/function calls accepted
    source*:          ModelLimitSource
    sourceRef*:       string ## non-empty when `source == mlsVerified`

  ModelLimitEntry* = object
    provider*: string
    model*:    string
    limits*:   ModelLimits

const ModelLimitEntries*: array[1, ModelLimitEntry] = [
  ModelLimitEntry(
    provider: "nvidia",
    model: DefaultModelNvidia,
    limits: ModelLimits(
      # No Hermes source states Nemotron's context window: leave it 0.
      contextWindow: 0,
      maxOutputTokens: 16384,
      supportsVision: NvidiaSupportsImages,
      supportsTools: true,
      source: mlsVerified,
      sourceRef: "hermes:plugins/model-providers/nvidia/__init__.py:31 " &
                 "(default_max_tokens=16384); " &
                 "hermes:providers.md:517-518 (text and image inputs, " &
                 "reasoning, tool calls)")),
]

func compareToEntry(provider, model: string; entry: ModelLimitEntry): int =
  ## Total order used by the table and its binary search.
  result = cmp(provider, entry.provider)
  if result == 0:
    result = cmp(model, entry.model)

static:
  # The table invariant the binary search relies on.
  for i in 1 ..< ModelLimitEntries.len:
    doAssert compareToEntry(ModelLimitEntries[i - 1].provider,
                            ModelLimitEntries[i - 1].model,
                            ModelLimitEntries[i]) < 0,
             "ModelLimitEntries must be sorted by (provider, model)"

func modelLimits*(provider, model: string): ModelLimits =
  ## Limits for an exact `(provider, model)` pair. The provider id is matched
  ## case-insensitively and trimmed; the model id is exact. Anything not in
  ## the verified table gets the conservative default (all 0/false, no ref).
  let key = provider.strip.toLowerAscii()
  var low = 0
  var high = ModelLimitEntries.len - 1
  while low <= high:
    let middle = (low + high) div 2
    let order = compareToEntry(key, model, ModelLimitEntries[middle])
    if order == 0:
      return ModelLimitEntries[middle].limits
    if order < 0:
      high = middle - 1
    else:
      low = middle + 1
  ModelLimits(source: mlsUnknown)
