## credential_runtime.nim — process-wide provider credential pools.
##
## A provider may carry several keys: the plural env next to the single one
## (`OPENAI_API_KEYS` beside `OPENAI_API_KEY`). Selection rotates over healthy
## keys, and a key that returned an auth/rate/quota error cools down so the
## next request uses another one.
##
## Provider specs are built on the event loop, so the table needs no lock.

import std/[options, os, strutils, tables]
import ../core/pipeops
import ../core/providers/credential_pool

var gPools: Table[string, CredentialPool]

func poolEnvName*(envName: string): string =
  ## `openai` + `OPENAI_API_KEY` -> `OPENAI_API_KEYS`.
  if envName.endsWith("KEY"):
    envName[0 ..< envName.len - 3] & "KEYS"
  else:
    envName & "_KEYS"

func splitKeys*(raw: string): seq[string] =
  for part in raw.split(','):
    let key = part.strip
    if key.len > 0 and key notin result:
      result.add key

func hasCredentialKey*(envNames: openArray[string]): bool =
  ## True when any name has a single or plural value. Pure: availability is
  ## computed without touching the pool.
  for envName in envNames:
    if getEnv(envName).strip.len > 0:
      return true
    if splitKeys(getEnv(poolEnvName(envName))).len > 0:
      return true
  false

proc resetCredentialPools*() {.gcsafe, raises: [].} =
  ## Test hook: forget rotation and cooldown state.
  {.cast(gcsafe).}:
    gPools.clear()

proc resolveCredentialKey*(providerName: string;
                           envNames: openArray[string];
                           nowMs = nowMs()): string {.gcsafe, raises: [].} =
  ## First env name with a value wins. When its plural pool exists, the next
  ## healthy key is returned; otherwise the single value becomes a one-key
  ## pool.
  if providerName.len == 0:
    return ""
  for envName in envNames:
    var keys = splitKeys(getEnv(poolEnvName(envName)))
    if keys.len == 0:
      let single = getEnv(envName).strip
      if single.len > 0:
        keys = @[single]
    if keys.len == 0:
      continue
    {.cast(gcsafe).}:
      var pool = gPools.getOrDefault(providerName)
      if pool.keys != keys:
        pool = initCredentialPool(keys)
      let picked = pool.pick(nowMs)
      gPools[providerName] = pool
      if picked.isSome:
        return picked.get()
    return ""
  ""

proc nextCredentialKey*(providerName, currentKey: string;
                        nowMs = nowMs()): string {.gcsafe, raises: [].} =
  ## Another healthy key for an in-flight retry; "" when there is none.
  {.cast(gcsafe).}:
    if not gPools.hasKey(providerName):
      return ""
    let picked = gPools.getOrDefault(providerName).nextHealthy(currentKey, nowMs)
    if picked.isSome: return picked.get()
  ""

func cooldownForError*(message: string): int64 =
  ## A rate limit recovers in a minute; auth and quota problems need a human
  ## or a billing change, so the key rests for much longer.
  let text = message.toLowerAscii()
  if text.contains("429") or text.contains("rate limit") or
     text.contains("too many requests"):
    60_000
  elif text.contains("quota") or text.contains("insufficient"):
    15 * 60_000
  else:
    30 * 60_000

proc noteCredentialResult*(providerName, key: string; ok: bool;
                           error = ""; nowMs = nowMs())
                           {.gcsafe, raises: [].} =
  if key.len == 0:
    return
  {.cast(gcsafe).}:
    if not gPools.hasKey(providerName):
      return
    var pool = gPools.getOrDefault(providerName)
    if ok:
      pool.noteSuccess(key)
    else:
      pool.noteFailure(key, nowMs, cooldownForError(error))
    gPools[providerName] = pool
