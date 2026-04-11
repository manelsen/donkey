## Declarative catalog of providers and models.
##
## Provides canonical names, aliases, capabilities, relative cost,
## tool/image/thinking support, and budget-based priority so routing
## is data-driven rather than hardcoded.

import std/[algorithm, strutils, tables, sequtils, options]

type
  ## Capabilities a model can support.
  ModelCapability* = enum
    mcTools        ## supports tool calling / function calling
    mcImage        ## supports image input
    mcThinking     ## supports extended thinking / CoT
    mcStreaming    ## supports token streaming

  ## Relative cost tier (abstract, not tied to specific currency).
  CostTier* = enum
    ctFree         ## genuinely free
    ctVeryCheap    ## e.g. < $0.001/1k tokens
    ctCheap       ## e.g. < $0.01/1k tokens
    ctModerate    ## e.g. < $0.10/1k tokens
    ctExpensive   ## premium models

  ## Priority level for budget-based routing.
  BudgetPriority* = enum
    bpDefault      ## normal priority
    bpHigh        ## prefer for quality-first
    bpLow         ## prefer for cheap-first

  ## A single model entry in the catalog.
  ProviderModelEntry* = object
    canonicalName*: string                ## e.g. "openai/gpt-4o-mini"
    aliases*: seq[string]                ## e.g. @["gpt-4o-mini", "4o-mini"]
    providerName*: string                ## e.g. "openrouter", "anthropic"
    capabilities*: set[ModelCapability]
    costTier*: CostTier
    budgetPriority*: BudgetPriority
    supportsTools*: bool                 ## derived from capabilities
    supportsImage*: bool                 ## derived from capabilities
    supportsThinking*: bool              ## derived from capabilities
    contextWindow*: int                  ## approximate context size in tokens (0 = unknown)

  ## Query filters for catalog lookups.
  ModelQuery* = object
    provider*: string                    ## filter by provider name
    hasTools*: bool                      ## require tool support
    hasImage*: bool                      ## require image support
    hasThinking*: bool                   ## require thinking support
    maxCostTier*: CostTier               ## upper bound on cost
    minContextWindow*: int               ## minimum context window (0 = any)

  ## The catalog itself.
  ProviderCatalog* = object
    entries*: Table[string, ProviderModelEntry]  # keyed by canonicalName
    aliasIndex*: Table[string, string]            # alias -> canonicalName
    providerIndex*: Table[string, seq[string]]    # provider -> [canonicalNames]

# ── Entry builders ────────────────────────────────────────────────────────────

func makeEntry*(canonicalName, providerName: string;
                aliases: seq[string] = @[];
                capabilities: set[ModelCapability] = {};
                costTier = ctModerate;
                budgetPriority = bpDefault;
                contextWindow = 0): ProviderModelEntry =
  ProviderModelEntry(
    canonicalName: canonicalName,
    aliases: aliases,
    providerName: providerName,
    capabilities: capabilities,
    costTier: costTier,
    budgetPriority: budgetPriority,
    supportsTools: mcTools in capabilities,
    supportsImage: mcImage in capabilities,
    supportsThinking: mcThinking in capabilities,
    contextWindow: contextWindow,
  )

# ── Catalog operations ────────────────────────────────────────────────────────

proc register*(cat: var ProviderCatalog; entry: ProviderModelEntry) =
  ## Register a model entry. Overwrites if canonical name already exists.
  cat.entries[entry.canonicalName] = entry
  for alias in entry.aliases:
    cat.aliasIndex[alias.toLowerAscii] = entry.canonicalName
  if entry.providerName notin cat.providerIndex:
    cat.providerIndex[entry.providerName] = @[]
  if entry.canonicalName notin cat.providerIndex[entry.providerName]:
    cat.providerIndex[entry.providerName].add(entry.canonicalName)

proc lookup*(cat: ProviderCatalog; nameOrAlias: string): Option[ProviderModelEntry] =
  ## Look up a model by canonical name or alias.
  let key = nameOrAlias.strip()
  if key in cat.entries:
    return some(cat.entries[key])
  let lowerKey = key.toLowerAscii()
  if lowerKey in cat.aliasIndex:
    let canonical = cat.aliasIndex[lowerKey]
    if canonical in cat.entries:
      return some(cat.entries[canonical])
  none(ProviderModelEntry)

proc query*(cat: ProviderCatalog; q: ModelQuery): seq[ProviderModelEntry] =
  ## Query the catalog with filters.
  # maxCostTier defaults to first enum value (ctFree), so we only filter when
  # explicitly set to something other than ctFree by checking if the caller
  # actually wants cost filtering via a sentinel approach.
  let applyCostFilter = q.maxCostTier > ctFree
  for k, entry in cat.entries:
    if q.provider.len > 0 and entry.providerName != q.provider:
      continue
    if q.hasTools and not entry.supportsTools:
      continue
    if q.hasImage and not entry.supportsImage:
      continue
    if q.hasThinking and not entry.supportsThinking:
      continue
    if applyCostFilter and ord(entry.costTier) > ord(q.maxCostTier):
      continue
    if q.minContextWindow > 0 and entry.contextWindow < q.minContextWindow:
      continue
    result.add(entry)

proc orderByCost*(entries: seq[ProviderModelEntry]): seq[ProviderModelEntry] =
  ## Sort entries by cost tier ascending (cheapest first).
  result = entries
  result.sort(proc(a, b: ProviderModelEntry): int =
    cmp(ord(a.costTier), ord(b.costTier))
  )

proc orderByPriority*(entries: seq[ProviderModelEntry];
                      budgetPolicy: string = "balanced"): seq[ProviderModelEntry] =
  ## Sort entries by budget priority.
  ## "cheap-first": low cost first, then bpLow, bpDefault, bpHigh
  ## "quality-first": bpHigh first, then bpDefault, bpLow
  ## "balanced": bpDefault first, then by cost
  result = entries
  case budgetPolicy.toLowerAscii()
  of "cheap-first":
    result.sort(proc(a, b: ProviderModelEntry): int =
      let costCmp = cmp(ord(a.costTier), ord(b.costTier))
      if costCmp != 0: return costCmp
      cmp(ord(a.budgetPriority), ord(b.budgetPriority))
    )
  of "quality-first":
    result.sort(proc(a, b: ProviderModelEntry): int =
      let prioCmp = cmp(ord(b.budgetPriority), ord(a.budgetPriority))
      if prioCmp != 0: return prioCmp
      cmp(ord(a.costTier), ord(b.costTier))
    )
  else:  # balanced
    result.sort(proc(a, b: ProviderModelEntry): int =
      let prioCmp = cmp(ord(a.budgetPriority), ord(b.budgetPriority))
      if prioCmp != 0: return prioCmp
      cmp(ord(a.costTier), ord(b.costTier))
    )

proc getByProvider*(cat: ProviderCatalog; providerName: string): seq[ProviderModelEntry] =
  ## Get all entries for a specific provider.
  if providerName in cat.providerIndex:
    for canonicalName in cat.providerIndex[providerName]:
      if canonicalName in cat.entries:
        result.add(cat.entries[canonicalName])

proc allProviders*(cat: ProviderCatalog): seq[string] =
  ## List all registered provider names.
  toSeq(cat.providerIndex.keys)

proc len*(cat: ProviderCatalog): int =
  ## Number of entries in the catalog.
  cat.entries.len

# ── Default catalog populated with currently hardcoded models ─────────────────

proc buildDefaultCatalog*(): ProviderCatalog =
  ## Creates and populates the default provider catalog with all known models.
  result = ProviderCatalog(
    entries: initTable[string, ProviderModelEntry](),
    aliasIndex: initTable[string, string](),
    providerIndex: initTable[string, seq[string]](),
  )

  # ── OpenRouter ──
  result.register(makeEntry(
    "openai/gpt-4o-mini", "openrouter",
    aliases = @["gpt-4o-mini"],
    capabilities = {mcTools, mcImage, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpLow,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "openai/gpt-4o", "openrouter",
    aliases = @["gpt-4o"],
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "anthropic/claude-opus-4-6", "openrouter",
    aliases = @["claude-opus-4-6", "opus-4"],
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctExpensive,
    budgetPriority = bpHigh,
    contextWindow = 200_000,
  ))
  result.register(makeEntry(
    "anthropic/claude-sonnet-4-6", "openrouter",
    aliases = @["claude-sonnet-4-6", "sonnet-4"],
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpDefault,
    contextWindow = 200_000,
  ))

  # ── Anthropic (direct) ──
  result.register(makeEntry(
    "claude-opus-4-6", "anthropic",
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctExpensive,
    budgetPriority = bpHigh,
    contextWindow = 200_000,
  ))
  result.register(makeEntry(
    "claude-sonnet-4-6", "anthropic",
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpDefault,
    contextWindow = 200_000,
  ))

  # ── Z.ai Anthropic (proxy) ──
  result.register(makeEntry(
    "glm-4.7", "zai-anthropic",
    aliases = @["glm-47"],
    capabilities = {mcTools, mcThinking, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.6", "zai-anthropic",
    capabilities = {mcTools, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.5", "zai-anthropic",
    capabilities = {mcTools, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.5-air", "zai-anthropic",
    capabilities = {mcTools, mcStreaming},
    costTier = ctVeryCheap,
    budgetPriority = bpLow,
    contextWindow = 64_000,
  ))

  # ── Gemini ──
  result.register(makeEntry(
    "gemini-2.5-flash", "gemini",
    aliases = @["gemini-flash"],
    capabilities = {mcTools, mcImage, mcStreaming},
    costTier = ctVeryCheap,
    budgetPriority = bpLow,
    contextWindow = 1_048_576,
  ))
  result.register(makeEntry(
    "gemini-2.5-pro", "gemini",
    aliases = @["gemini-pro"],
    capabilities = {mcTools, mcImage, mcThinking, mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpHigh,
    contextWindow = 1_048_576,
  ))

  # ── MiniMax ──
  result.register(makeEntry(
    "MiniMax-M2", "minimax",
    aliases = @["minimax-m2"],
    capabilities = {mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "MiniMax-M2.5", "minimax",
    aliases = @["minimax-m25"],
    capabilities = {mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "MiniMax-M2.7", "minimax",
    aliases = @["minimax-m27"],
    capabilities = {mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpDefault,
    contextWindow = 256_000,
  ))
  result.register(makeEntry(
    "MiniMax-M2.7-highspeed", "minimax",
    aliases = @["minimax-m27-hs"],
    capabilities = {mcStreaming},
    costTier = ctModerate,
    budgetPriority = bpDefault,
    contextWindow = 256_000,
  ))

  # ── Z.ai (direct) ──
  result.register(makeEntry(
    "glm-5.1", "zai",
    aliases = @["glm51"],
    capabilities = {mcTools, mcThinking, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-5", "zai",
    aliases = @["glm5"],
    capabilities = {mcTools, mcThinking, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.7", "zai",
    aliases = @["glm-47"],
    capabilities = {mcTools, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.6", "zai",
    capabilities = {mcTools, mcStreaming},
    costTier = ctVeryCheap,
    budgetPriority = bpLow,
    contextWindow = 128_000,
  ))

  # ── Z.ai Coding ──
  result.register(makeEntry(
    "glm-5.1", "zai-coding",
    aliases = @["glm51"],
    capabilities = {mcTools, mcThinking, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-5", "zai-coding",
    aliases = @["glm5"],
    capabilities = {mcTools, mcThinking, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
  result.register(makeEntry(
    "glm-4.7", "zai-coding",
    aliases = @["glm-47"],
    capabilities = {mcTools, mcStreaming},
    costTier = ctCheap,
    budgetPriority = bpDefault,
    contextWindow = 128_000,
  ))
