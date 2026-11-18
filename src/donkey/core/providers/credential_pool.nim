## credential_pool.nim — rotation and cooling for provider API keys.
##
## A provider may be configured with several keys (`OPENAI_API_KEYS`, plural).
## Selection is round-robin over healthy keys; a key that returned auth, rate
## or quota errors cools down and is skipped until its deadline. Pure state:
## the caller supplies the clock.
##
## No I/O.

import std/[options, strutils]

type
  CredentialPool* = object
    keys*:             seq[string]
    cooldownUntilMs*:  seq[int64]
    nextIndex*:        int

func initCredentialPool*(keys: seq[string]): CredentialPool =
  CredentialPool(
    keys: keys,
    cooldownUntilMs: newSeq[int64](keys.len),
    nextIndex: 0,
  )

func credentialCount*(p: CredentialPool): int =
  p.keys.len

func pick*(p: var CredentialPool; nowMs: int64): Option[string] =
  ## Next healthy key in round-robin order. When every key is cooling, returns
  ## the one whose deadline is nearest: trying it beats failing without a
  ## request.
  if p.keys.len == 0:
    return none(string)
  for offset in 0 ..< p.keys.len:
    let index = (p.nextIndex + offset) mod p.keys.len
    if p.cooldownUntilMs[index] <= nowMs:
      p.nextIndex = (index + 1) mod p.keys.len
      return some(p.keys[index])
  var best = 0
  for index in 1 ..< p.keys.len:
    if p.cooldownUntilMs[index] < p.cooldownUntilMs[best]:
      best = index
  p.nextIndex = (best + 1) mod p.keys.len
  some(p.keys[best])

func nextHealthy*(p: CredentialPool; currentKey: string;
                  nowMs: int64): Option[string] =
  ## A different healthy key, for an in-flight retry. Does not advance the
  ## round-robin cursor.
  for index in 0 ..< p.keys.len:
    if p.keys[index] == currentKey:
      continue
    if p.cooldownUntilMs[index] <= nowMs:
      return some(p.keys[index])
  none(string)

func indexOf(p: CredentialPool; key: string): int =
  for index in 0 ..< p.keys.len:
    if p.keys[index] == key:
      return index
  -1

func noteFailure*(p: var CredentialPool; key: string;
                  nowMs, cooldownMs: int64) =
  let index = p.indexOf(key)
  if index < 0:
    return
  p.cooldownUntilMs[index] = max(p.cooldownUntilMs[index], nowMs + cooldownMs)

func noteSuccess*(p: var CredentialPool; key: string) =
  let index = p.indexOf(key)
  if index >= 0:
    p.cooldownUntilMs[index] = 0

func isRetryableCredentialError*(message: string): bool =
  ## The failures another key can plausibly fix. Transport errors and payload
  ## problems are not key-specific and must not burn through the pool.
  let text = message.toLowerAscii()
  for marker in ["401", "403", "429", "unauthorized", "invalid api key",
                 "invalid_api_key", "rate limit", "rate_limit", "quota",
                 "too many requests", "insufficient"]:
    if text.contains(marker):
      return true
  false
