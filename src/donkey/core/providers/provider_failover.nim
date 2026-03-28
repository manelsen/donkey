## provider_failover — Pure provider failover and health management.
##
## Supports automatic failover between LLM providers when primary fails.
## Includes health checking, cooldown management, and fallback chains.

import std/options

type
  ProviderHealth* = enum
    phHealthy    ## Provider is working normally
    phDegraded   ## Provider is slow (>10s response) or intermittent
    phUnhealthy  ## Provider has failed multiple times consecutively

  ProviderCooldown* = object
    providerId*: string     ## Provider identifier
    until*:      float     ## Unix timestamp when cooldown expires

  FailoverConfig* = object
    enabled*:         bool    ## Enable failover (default: true)
    maxRetries*:      int     ## Max retries per provider (default: 3)
    cooldownSeconds*: float    ## Cooldown duration after failure (default: 300)
    healthCheckInterval*: float  ## Seconds between health checks (default: 60)

  ProviderState* = object
    providerId*: string
    health*:      ProviderHealth
    consecutiveFailures*: int
    consecutiveSuccesses*: int
    lastFailure*: float     ## Unix timestamp
    lastSuccess*: float     ## Unix timestamp

  FailoverChain* = object
    providers*:    seq[string]  ## Ordered list of provider IDs
    currentIndex*: int         ## Index of current provider

func `$`*(health: ProviderHealth): string =
  case health
  of phHealthy: "healthy"
  of phDegraded: "degraded"
  of phUnhealthy: "unhealthy"

func parseHealth*(s: string): ProviderHealth =
  case s
  of "healthy": phHealthy
  of "degraded": phDegraded
  of "unhealthy": phUnhealthy
  else: phHealthy

func isHealthy*(state: ProviderState): bool =
  state.health == phHealthy

func newProviderState*(providerId: string): ProviderState =
  ProviderState(
    providerId: providerId,
    health: phHealthy,
    consecutiveFailures: 0,
    consecutiveSuccesses: 0,
    lastFailure: 0.0,
    lastSuccess: 0.0,
  )

func recordFailure*(state: var ProviderState; now: float): ProviderState =
  state.consecutiveFailures += 1
  state.consecutiveSuccesses = 0
  state.lastFailure = now
  if state.consecutiveFailures >= 3:
    state.health = phUnhealthy
  elif state.consecutiveFailures >= 1:
    state.health = phDegraded
  state

func recordSuccess*(state: var ProviderState; now: float): ProviderState =
  state.consecutiveSuccesses += 1
  state.consecutiveFailures = 0
  state.lastSuccess = now
  if state.consecutiveSuccesses >= 3:
    state.health = phHealthy
  state

func isInCooldown*(cooldown: ProviderCooldown; now: float): bool =
  now < cooldown.until

func newCooldown*(providerId: string; seconds: float; now: float): ProviderCooldown =
  ProviderCooldown(providerId: providerId, until: now + seconds)

func findNextAvailableProvider*(
  providers: seq[string];
  states: seq[ProviderState];
  cooldowns: seq[ProviderCooldown];
  currentIndex: int;
  now: float;
  cooldownSeconds: float
): Option[(int, string)] =
  ## Finds the next available provider in the chain.
  ## Returns (index, providerId) or none if no providers available.
  
  for i in 0 ..< providers.len:
    let idx = (currentIndex + i) mod providers.len
    let providerId = providers[idx]
    
    # Find state for this provider
    var isHealthyProvider = true
    var isInCooldownNow = false
    
    for state in states:
      if state.providerId == providerId:
        isHealthyProvider = state.health != phUnhealthy
        break
    
    for cd in cooldowns:
      if cd.providerId == providerId and now < cd.until:
        isInCooldownNow = true
        break
    
    if isHealthyProvider and not isInCooldownNow:
      return some((idx, providerId))
  
  none((int, string))
