## Failover State Machine — pure logic for API timeout and fallback chains.
##
## Usage:
##   var ctx = newFailoverContext(selections)
##   while ctx.hasMoreProviders and not ctx.isExhausted:
##     let resp = provider.complete(req)
##     if resp.isOk:
##       ctx.recordSuccess()
##       break
##     ctx.recordFailure(resp.error)
##   if ctx.isExhausted:
##     return err(ctx.formatTrace)
##
## The state machine tracks: idle → attempting → succeeded | failed → exhausted.

import std/[strutils]
import ../../core/providers/smart_routing
import ../../domain/message

export smart_routing

const
  MaxFailoverAttempts* = 5

type
  FailoverState* = enum
    fsIdle
    fsAttempting
    fsSucceeded
    fsFailed
    fsExhausted

  FailoverAttempt* = object
    providerName*: string
    modelName*: string
    error*: string
    latencyMs*: int64

  FailoverContext* = object
    state*: FailoverState
    providers*: seq[ProviderSelection]
    currentIndex*: int
    attempts*: seq[FailoverAttempt]

  FailoverResult* = object
    response*: CompletionResponse
    context*: FailoverContext

func `$`*(s: FailoverState): string =
  case s
  of fsIdle: "idle"
  of fsAttempting: "attempting"
  of fsSucceeded: "succeeded"
  of fsFailed: "failed"
  of fsExhausted: "exhausted"

func newFailoverContext*(providers: seq[ProviderSelection]): FailoverContext =
  FailoverContext(
    state: fsIdle,
    providers: providers,
    currentIndex: 0,
    attempts: @[],
  )

func currentProvider*(ctx: FailoverContext): ProviderSelection =
  if ctx.currentIndex < ctx.providers.len:
    ctx.providers[ctx.currentIndex]
  else:
    ProviderSelection(providerName: "", modelName: "")

func hasMoreProviders*(ctx: FailoverContext): bool =
  ctx.currentIndex < ctx.providers.len

func attemptCount*(ctx: FailoverContext): int =
  ctx.attempts.len

func isExhausted*(ctx: FailoverContext): bool =
  ctx.state == fsExhausted

func isSucceeded*(ctx: FailoverContext): bool =
  ctx.state == fsSucceeded

func lastError*(ctx: FailoverContext): string =
  if ctx.attempts.len > 0:
    ctx.attempts[^1].error
  else:
    ""

func formatAttempt*(a: FailoverAttempt): string =
  if a.latencyMs > 0:
    "[" & a.providerName & "/" & a.modelName & " failed after " & $a.latencyMs & "ms: " & a.error & "]"
  else:
    "[" & a.providerName & "/" & a.modelName & " failed: " & a.error & "]"

func formatTrace*(ctx: FailoverContext): string =
  ## Returns human-readable failover trace for logging/errors.
  if ctx.attempts.len == 0:
    return "No failover attempts"
  var parts: seq[string] = @[]
  for attempt in ctx.attempts:
    parts.add(formatAttempt(attempt))
  "Failover trace (" & $ctx.attempts.len & " attempts): " & parts.join(" → ")

func recordAttemptStart*(ctx: var FailoverContext) =
  ## Mark that we're about to attempt the current provider.
  ctx.state = fsAttempting

func recordSuccess*(ctx: var FailoverContext) =
  ## Mark the current provider succeeded.
  ctx.state = fsSucceeded

func recordFailure*(ctx: var FailoverContext; error: string; latencyMs: int64 = 0) =
  ## Record a failure and advance to next provider or exhaust.
  let provider = ctx.currentProvider
  ctx.attempts.add(FailoverAttempt(
    providerName: provider.providerName,
    modelName: provider.modelName,
    error: error,
    latencyMs: latencyMs,
  ))
  ctx.currentIndex += 1
  if ctx.currentIndex >= ctx.providers.len:
    ctx.state = fsExhausted
  else:
    ctx.state = fsFailed

func recordTimeout*(ctx: var FailoverContext; latencyMs: int64 = 0) =
  ## Convenience: record a timeout as a specific failure.
  ctx.recordFailure("timeout after " & $latencyMs & "ms", latencyMs)

func recordHttpError*(ctx: var FailoverContext; code: int; latencyMs: int64 = 0) =
  ## Convenience: record an HTTP error as a specific failure.
  ctx.recordFailure("HTTP " & $code, latencyMs)

func recordParseError*(ctx: var FailoverContext; latencyMs: int64 = 0) =
  ## Convenience: record a parse error as a specific failure.
  ctx.recordFailure("parse error", latencyMs)

func isRetriable*(error: string): bool =
  ## Returns true if the error is likely transient and worth retrying.
  let lower = error.toLowerAscii
  lower.contains("timeout") or
  lower.contains("rate limit") or
  lower.contains("429") or
  lower.contains("500") or
  lower.contains("502") or
  lower.contains("503") or
  lower.contains("504") or
  lower.contains("connection refused") or
  lower.contains("network error") or
  lower.contains("temporary failure")

func shouldContinueFailover*(ctx: FailoverContext; lastError: string): bool =
  ## Decides whether to continue trying next providers.
  ## Returns false if exhausted, succeeded, or error is non-retriable.
  if ctx.isExhausted or ctx.isSucceeded:
    return false
  if not lastError.isRetriable:
    return false
  true

func formatProviderChain*(providers: seq[ProviderSelection]): string =
  ## Returns human-readable provider chain for logging.
  var parts: seq[string] = @[]
  for p in providers:
    parts.add(p.formatSelection)
  parts.join(" → ")

func failoverSummary*(ctx: FailoverContext): string =
  ## One-line summary of failover outcome.
  case ctx.state
  of fsIdle: "no attempts made"
  of fsAttempting: "attempt in progress"
  of fsSucceeded: "succeeded on attempt " & $ctx.attemptCount
  of fsFailed: "failed " & $ctx.attemptCount & " of " & $ctx.providers.len
  of fsExhausted: "exhausted all " & $ctx.providers.len & " providers after " & $ctx.attemptCount & " attempts"
