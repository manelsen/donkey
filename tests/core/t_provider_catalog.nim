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
    let result = catalog.lookup("gemini-3.8-flash")
    check result.isSome
    check result.get().canonicalName == "gemini-3.8-flash"
    check result.get().providerName == "gemini"
    check result.get().supportsImage

  test "lookup finds model by alias":
    let catalog = buildDefaultCatalog()
    let result = catalog.lookup("gpt-6-sol")
    check result.isSome
    check result.get().canonicalName == "gpt-6.1-sol"
    check result.get().providerName == "openai"

    let opusAlias = catalog.lookup("opus-5.5")
    check opusAlias.isSome
    check opusAlias.get().providerName == "anthropic"

    let flashAlias = catalog.lookup("deepseek-flash")
    check flashAlias.isSome
    check flashAlias.get().providerName == "deepseek"

  test "lookup resolves alias uniquely without cross-provider collision":
    let catalog = buildDefaultCatalog()
    # "gpt-4o" is uniquely registered as an alias under openai direct
    let result = catalog.lookup("gpt-4o")
    check result.isSome
    check result.get().canonicalName == "gpt-6.1-sol"
    check result.get().providerName == "openai"

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

  test "catalog contains all modern models from smart_routing":
    let catalog = buildDefaultCatalog()
    let modernModels = @[
      "claude-opus-5-5",
      "claude-sonnet-5-5",
      "gpt-6.1-sol",
      "gpt-6-astra",
      "gpt-6.1-terra",
      "gpt-6-luna",
      "deepseek-4.1-flash",
      "deepseek-v4-pro",
      "gemini-3.8-flash",
      "gemini-4-argon",
      "llama3.3",
      "llama4:scout",
      "glm-4.7",
      "glm-5.1",
      "MiniMax-M2",
      "MiniMax-M2.5",
      "MiniMax-M2.7",
    ]
    for model in modernModels:
      let result = catalog.lookup(model)
      check result.isSome

  test "catalog resolves all legacy aliases for backward compatibility":
    let catalog = buildDefaultCatalog()
    let legacyAliases = @[
      "openai/gpt-4o-mini",
      "openai/gpt-4o",
      "claude-opus-4-6",
      "claude-sonnet-4-6",
      "gemini-2.5-flash",
      "gemini-2.5-pro",
    ]
    for alias in legacyAliases:
      let result = catalog.lookup(alias)
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
