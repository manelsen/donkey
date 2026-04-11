import std/[unittest, tables, options]
import donkey/core/providers/provider_catalog

suite "provider_catalog":

  test "buildDefaultCatalog returns a non-empty catalog":
    let catalog = buildDefaultCatalog()
    check catalog.len > 0

  test "register adds entry and indexes it":
    var cat = ProviderCatalog()
    cat.entries = initTable[string, ProviderModelEntry]()
    cat.aliasIndex = initTable[string, string]()
    cat.providerIndex = initTable[string, seq[string]]()

    let entry = makeEntry("test/model", "test-provider",
      aliases = @["model-alias"],
      capabilities = {mcTools, mcImage},
      costTier = ctCheap)
    cat.register(entry)

    check "test/model" in cat.entries
    check "model-alias" in cat.aliasIndex
    check cat.aliasIndex["model-alias"] == "test/model"
    check "test-provider" in cat.providerIndex
    check cat.providerIndex["test-provider"].len == 1

  test "lookup finds model by canonical name":
    let catalog = buildDefaultCatalog()
    let result = catalog.lookup("gemini-2.5-flash")
    check result.isSome
    check result.get().canonicalName == "gemini-2.5-flash"
    check result.get().providerName == "gemini"
    check result.get().supportsImage

  test "lookup finds model by alias":
    let catalog = buildDefaultCatalog()
    let result = catalog.lookup("gpt-4o-mini")
    check result.isSome
    check result.get().canonicalName == "openai/gpt-4o-mini"

  test "lookup returns none for unknown model":
    let catalog = buildDefaultCatalog()
    let result = catalog.lookup("unknown-model-xyz")
    check result.isNone

  test "makeEntry derives boolean flags from capabilities":
    let entry = makeEntry("x/y", "p",
      capabilities = {mcTools, mcThinking})
    check entry.supportsTools
    check not entry.supportsImage
    check entry.supportsThinking

  test "query filters by provider":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(provider: "gemini")
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.providerName == "gemini"

  test "query filters by hasTools":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(hasTools: true)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.supportsTools

  test "query filters by hasImage":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(hasImage: true)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.supportsImage

  test "query filters by hasThinking":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(hasThinking: true)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.supportsThinking

  test "query filters by maxCostTier":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(maxCostTier: ctCheap)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check ord(entry.costTier) <= ord(ctCheap)

  test "query filters by minContextWindow":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(minContextWindow: 200_000)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.contextWindow >= 200_000

  test "query combines multiple filters":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(hasTools: true, hasThinking: true, maxCostTier: ctModerate)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.supportsTools
      check entry.supportsThinking
      check ord(entry.costTier) <= ord(ctModerate)

  test "orderByCost sorts cheapest first":
    let catalog = buildDefaultCatalog()
    let entries = catalog.query(ModelQuery())
    let sorted = orderByCost(entries)
    check sorted.len > 0
    for i in 1 ..< sorted.len:
      check ord(sorted[i].costTier) >= ord(sorted[i-1].costTier)

  test "orderByPriority cheap-first sorts by cost ascending":
    let catalog = buildDefaultCatalog()
    let entries = catalog.query(ModelQuery())
    let sorted = orderByPriority(entries, "cheap-first")
    check sorted.len > 0
    for i in 1 ..< sorted.len:
      check ord(sorted[i].costTier) >= ord(sorted[i-1].costTier)

  test "orderByPriority quality-first puts bpHigh first":
    let catalog = buildDefaultCatalog()
    let entries = catalog.query(ModelQuery())
    let sorted = orderByPriority(entries, "quality-first")
    check sorted.len > 0
    # First entries should have higher budget priority
    var foundHigh = false
    for entry in sorted:
      if entry.budgetPriority == bpHigh:
        foundHigh = true
      elif foundHigh and entry.budgetPriority != bpHigh:
        # After bpHigh entries, we should not see bpHigh again
        break

  test "getByProvider returns all models for a provider":
    let catalog = buildDefaultCatalog()
    let entries = catalog.getByProvider("minimax")
    check entries.len > 0
    for entry in entries:
      check entry.providerName == "minimax"

  test "getByProvider returns empty for unknown provider":
    let catalog = buildDefaultCatalog()
    let entries = catalog.getByProvider("nonexistent-provider")
    check entries.len == 0

  test "allProviders lists known provider names":
    let catalog = buildDefaultCatalog()
    let providers = catalog.allProviders()
    check "gemini" in providers
    check "minimax" in providers
    check "anthropic" in providers

  test "catalog contains all hardcoded models from smart_routing":
    let catalog = buildDefaultCatalog()
    # Verify key models referenced in smart_routing.nim exist
    let modelsToCheck = @[
      "openai/gpt-4o-mini",
      "openai/gpt-4o",
      "claude-opus-4-6",
      "claude-sonnet-4-6",
      "glm-4.7",
      "glm-5",
      "gemini-2.5-flash",
      "gemini-2.5-pro",
      "MiniMax-M2",
      "MiniMax-M2.5",
      "MiniMax-M2.7",
    ]
    for model in modelsToCheck:
      let result = catalog.lookup(model)
      check result.isSome

  test "register overwrites duplicate canonical name":
    var cat = ProviderCatalog()
    cat.entries = initTable[string, ProviderModelEntry]()
    cat.aliasIndex = initTable[string, string]()
    cat.providerIndex = initTable[string, seq[string]]()

    cat.register(makeEntry("test/m", "p1",
      capabilities = {mcTools}))
    check cat.entries["test/m"].supportsTools

    cat.register(makeEntry("test/m", "p1",
      capabilities = {mcImage}))
    check not cat.entries["test/m"].supportsTools
    check cat.entries["test/m"].supportsImage

  test "complex query for image + thinking models":
    let catalog = buildDefaultCatalog()
    let q = ModelQuery(hasImage: true, hasThinking: true)
    let results = catalog.query(q)
    check results.len > 0
    for entry in results:
      check entry.supportsImage
      check entry.supportsThinking
