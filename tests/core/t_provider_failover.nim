import std/unittest
import std/options
import donkey/core/providers/provider_failover

suite "Provider Failover":

  test "ProviderHealth string representation":
    check $phHealthy == "healthy"
    check $phDegraded == "degraded"
    check $phUnhealthy == "unhealthy"

  test "parseHealth parses health strings":
    check parseHealth("healthy") == phHealthy
    check parseHealth("degraded") == phDegraded
    check parseHealth("unhealthy") == phUnhealthy
    check parseHealth("unknown") == phHealthy  # default

  test "isHealthy returns true for healthy provider":
    let state = ProviderState(providerId: "openai", health: phHealthy)
    check isHealthy(state) == true

  test "isHealthy returns false for degraded/unhealthy":
    let degraded = ProviderState(providerId: "openai", health: phDegraded)
    let unhealthy = ProviderState(providerId: "openai", health: phUnhealthy)
    check isHealthy(degraded) == false
    check isHealthy(unhealthy) == false

  test "newProviderState creates healthy state":
    let state = newProviderState("anthropic")
    check state.providerId == "anthropic"
    check state.health == phHealthy
    check state.consecutiveFailures == 0
    check state.consecutiveSuccesses == 0

  test "recordFailure increments failure count":
    var state = newProviderState("openai")
    discard recordFailure(state, 1000.0)
    check state.consecutiveFailures == 1
    check state.consecutiveSuccesses == 0
    check state.health == phDegraded  # 1 failure = degraded

  test "recordFailure marks unhealthy after 3 failures":
    var state = newProviderState("openai")
    discard recordFailure(state, 1000.0)
    discard recordFailure(state, 1001.0)
    discard recordFailure(state, 1002.0)
    check state.consecutiveFailures == 3
    check state.health == phUnhealthy

  test "recordSuccess resets failures and updates health":
    var state = ProviderState(
      providerId: "openai",
      health: phDegraded,
      consecutiveFailures: 2,
      consecutiveSuccesses: 0
    )
    discard recordSuccess(state, 1000.0)
    check state.consecutiveFailures == 0
    check state.consecutiveSuccesses == 1
    check state.health == phDegraded  # need 3 successes

  test "recordSuccess marks healthy after 3 consecutive successes":
    var state = ProviderState(
      providerId: "openai",
      health: phDegraded,
      consecutiveFailures: 1,
      consecutiveSuccesses: 0
    )
    discard recordSuccess(state, 1000.0)
    discard recordSuccess(state, 1001.0)
    discard recordSuccess(state, 1002.0)
    check state.health == phHealthy

  test "isInCooldown checks cooldown expiry":
    var cooldown = ProviderCooldown(providerId: "openai", until: 1000.0)
    check isInCooldown(cooldown, 999.0) == true
    check isInCooldown(cooldown, 1000.0) == false
    check isInCooldown(cooldown, 1001.0) == false

  test "newCooldown sets correct expiry":
    let cooldown = newCooldown("openai", 300.0, 1000.0)
    check cooldown.providerId == "openai"
    check cooldown.until == 1300.0

  test "findNextAvailableProvider finds first available":
    let providers = @["openai", "anthropic", "google"]
    let states = @[
      newProviderState("openai"),  # healthy
      newProviderState("anthropic"),
      newProviderState("google")
    ]
    let result = findNextAvailableProvider(
      providers, states, @[], 0, 1000.0, 300.0
    )
    check result.isSome()
    check result.get()[0] == 0
    check result.get()[1] == "openai"

  test "findNextAvailableProvider skips unhealthy":
    let providers = @["openai", "anthropic"]
    var openaiState = newProviderState("openai")
    openaiState.health = phUnhealthy
    let states = @[openaiState, newProviderState("anthropic")]
    let result = findNextAvailableProvider(
      providers, states, @[], 0, 1000.0, 300.0
    )
    check result.isSome()
    check result.get()[1] == "anthropic"

  test "findNextAvailableProvider skips providers in cooldown":
    let providers = @["openai", "anthropic"]
    let states = @[newProviderState("openai"), newProviderState("anthropic")]
    let cooldowns = @[newCooldown("openai", 300.0, 999.0)]  # expires at 1299
    let result = findNextAvailableProvider(
      providers, states, cooldowns, 0, 1000.0, 300.0  # current time 1000, cooldown expires 1299
    )
    check result.isSome()
    check result.get()[1] == "anthropic"

  test "FailoverConfig defaults":
    let config = FailoverConfig(
      enabled: true,
      maxRetries: 3,
      cooldownSeconds: 300.0,
      healthCheckInterval: 60.0
    )
    check config.enabled == true
    check config.maxRetries == 3
    check config.cooldownSeconds == 300.0
