import std/[unittest, strutils]
import donkey/domain/routing/failover

suite "failover state machine":

  let providers = @[
    ProviderSelection(providerName: "openrouter", modelName: "gpt-4o-mini"),
    ProviderSelection(providerName: "anthropic", modelName: "claude-sonnet-4-6"),
    ProviderSelection(providerName: "gemini", modelName: "gemini-2.5-flash"),
  ]

  test "newFailoverContext initializes correctly":
    let ctx = newFailoverContext(providers)
    check ctx.state == fsIdle
    check ctx.providers.len == 3
    check ctx.currentIndex == 0
    check ctx.attempts.len == 0

  test "currentProvider returns first provider initially":
    let ctx = newFailoverContext(providers)
    let current = ctx.currentProvider
    check current.providerName == "openrouter"
    check current.modelName == "gpt-4o-mini"

  test "currentProvider returns empty when exhausted":
    var ctx = newFailoverContext(@[providers[0]])
    ctx.currentIndex = 1
    let current = ctx.currentProvider
    check current.providerName == ""

  test "hasMoreProviders returns true when providers remain":
    let ctx = newFailoverContext(providers)
    check ctx.hasMoreProviders == true

  test "hasMoreProviders returns false when index at end":
    var ctx = newFailoverContext(providers)
    ctx.currentIndex = 3
    check ctx.hasMoreProviders == false

  test "attemptCount starts at zero":
    let ctx = newFailoverContext(providers)
    check ctx.attemptCount == 0

  test "isExhausted returns false initially":
    let ctx = newFailoverContext(providers)
    check ctx.isExhausted == false

  test "isSucceeded returns false initially":
    let ctx = newFailoverContext(providers)
    check ctx.isSucceeded == false

  test "lastError returns empty initially":
    let ctx = newFailoverContext(providers)
    check ctx.lastError == ""

  test "recordAttemptStart transitions to attempting":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    check ctx.state == fsAttempting

  test "recordSuccess transitions to succeeded":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordSuccess()
    check ctx.state == fsSucceeded
    check ctx.isSucceeded == true

  test "recordFailure advances index and stays in failed":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordFailure("network error")
    check ctx.state == fsFailed
    check ctx.currentIndex == 1
    check ctx.attemptCount == 1
    check ctx.lastError == "network error"

  test "recordFailure exhausts when no more providers":
    var ctx = newFailoverContext(@[providers[0]])
    ctx.recordAttemptStart()
    ctx.recordFailure("timeout")
    check ctx.state == fsExhausted
    check ctx.isExhausted == true
    check ctx.attemptCount == 1

  test "recordFailure with latencyMs is captured":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordFailure("rate limit", latencyMs = 1500)
    check ctx.attempts[0].latencyMs == 1500
    check ctx.lastError == "rate limit"

  test "recordTimeout is convenience for timeout failure":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordTimeout(latencyMs = 30000)
    check ctx.state == fsFailed
    check "timeout" in ctx.lastError
    check "30000ms" in ctx.lastError

  test "recordHttpError captures status code":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordHttpError(503, latencyMs = 500)
    check "503" in ctx.lastError

  test "recordParseError captures parse failure":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordParseError(latencyMs = 100)
    check "parse error" in ctx.lastError

  test "isRetriable recognizes timeout":
    check isRetriable("timeout after 30000ms") == true
    check isRetriable("connection timeout") == true

  test "isRetriable recognizes rate limit":
    check isRetriable("rate limit exceeded") == true
    check isRetriable("429 Too Many Requests") == true

  test "isRetriable recognizes HTTP 5xx":
    check isRetriable("HTTP 500 Internal Server Error") == true
    check isRetriable("HTTP 502 Bad Gateway") == true
    check isRetriable("HTTP 503 Service Unavailable") == true
    check isRetriable("HTTP 504 Gateway Timeout") == true

  test "isRetriable recognizes network errors":
    check isRetriable("connection refused") == true
    check isRetriable("network error") == true
    check isRetriable("temporary failure") == true

  test "isRetriable returns false for non-retriable":
    check isRetriable("invalid api key") == false
    check isRetriable("HTTP 400 Bad Request") == false
    check isRetriable("unauthorized") == false
    check isRetriable("invalid model") == false

  test "shouldContinueFailover returns false when succeeded":
    var ctx = newFailoverContext(providers)
    ctx.recordSuccess()
    check shouldContinueFailover(ctx, "timeout") == false

  test "shouldContinueFailover returns false when exhausted":
    var ctx = newFailoverContext(providers)
    ctx.state = fsExhausted
    check shouldContinueFailover(ctx, "timeout") == false

  test "shouldContinueFailover returns false for non-retriable error":
    var ctx = newFailoverContext(providers)
    check shouldContinueFailover(ctx, "invalid api key") == false

  test "shouldContinueFailover returns true for retriable error":
    var ctx = newFailoverContext(providers)
    check shouldContinueFailover(ctx, "timeout after 30000ms") == true

  test "formatTrace shows all attempts":
    var ctx = newFailoverContext(providers)
    ctx.recordAttemptStart()
    ctx.recordFailure("network error", latencyMs = 500)
    ctx.recordAttemptStart()
    ctx.recordFailure("timeout after 1000ms", latencyMs = 1000)
    let trace = ctx.formatTrace
    check "openrouter/gpt-4o-mini" in trace
    check "anthropic/claude-sonnet-4-6" in trace
    check "network error" in trace
    check "timeout" in trace
    check "2 attempts" in trace

  test "formatTrace returns 'no attempts' for empty":
    let ctx = newFailoverContext(providers)
    check ctx.formatTrace == "No failover attempts"

  test "formatProviderChain formats chain":
    let chain = formatProviderChain(providers)
    check chain == "openrouter/gpt-4o-mini → anthropic/claude-sonnet-4-6 → gemini/gemini-2.5-flash"

  test "failoverSummary for idle":
    let ctx = newFailoverContext(providers)
    check ctx.failoverSummary == "no attempts made"

  test "failoverSummary for attempting":
    var ctx = newFailoverContext(providers)
    ctx.state = fsAttempting
    check ctx.failoverSummary == "attempt in progress"

  test "failoverSummary for succeeded":
    var ctx = newFailoverContext(providers)
    ctx.state = fsSucceeded
    check ctx.failoverSummary == "succeeded on attempt 0"

  test "failoverSummary for failed with attempts":
    var ctx = newFailoverContext(providers)
    ctx.state = fsFailed
    ctx.attempts.add(FailoverAttempt(providerName: "openrouter", modelName: "gpt-4o-mini", error: "timeout"))
    check "failed 1 of 3" in ctx.failoverSummary

  test "failoverSummary for exhausted":
    var ctx = newFailoverContext(providers)
    ctx.state = fsExhausted
    ctx.attempts.add(FailoverAttempt(providerName: "openrouter", modelName: "gpt-4o-mini", error: "timeout"))
    check "exhausted all 3 providers" in ctx.failoverSummary
    check "1 attempts" in ctx.failoverSummary

  test "multiple failures advance through chain":
    var ctx = newFailoverContext(providers)
    # First provider fails
    ctx.recordAttemptStart()
    ctx.recordFailure("timeout")
    check ctx.currentProvider.providerName == "anthropic"
    # Second provider fails
    ctx.recordAttemptStart()
    ctx.recordFailure("rate limit")
    check ctx.currentProvider.providerName == "gemini"
    # Third provider fails - exhausts
    ctx.recordAttemptStart()
    ctx.recordFailure("network error")
    check ctx.isExhausted == true
    check ctx.attemptCount == 3

  test "FailoverState string representation":
    check $fsIdle == "idle"
    check $fsAttempting == "attempting"
    check $fsSucceeded == "succeeded"
    check $fsFailed == "failed"
    check $fsExhausted == "exhausted"

  test "formatAttempt with latency":
    let attempt = FailoverAttempt(providerName: "openrouter", modelName: "gpt-4o-mini", error: "timeout", latencyMs: 5000)
    let formatted = formatAttempt(attempt)
    check "openrouter/gpt-4o-mini" in formatted
    check "5000ms" in formatted
    check "timeout" in formatted

  test "formatAttempt without latency":
    let attempt = FailoverAttempt(providerName: "gemini", modelName: "gemini-2.5-flash", error: "parse error")
    let formatted = formatAttempt(attempt)
    check "gemini" in formatted
    check "parse error" in formatted
