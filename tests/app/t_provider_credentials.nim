## Provider credential pool tests: env resolution, rotation and retry.

import std/[os, unittest]
import chronos
import donkey/app/credential_runtime
import donkey/app/provider_executor
import donkey/app/session_bootstrap
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

proc clearCreds() =
  resetCredentialPools()
  for name in ["OPENAI_API_KEY", "OPENAI_API_KEYS",
               "GROQ_API_KEY", "GROQ_API_KEYS"]:
    delEnv(name)

suite "credential runtime":

  test "the plural env sits next to the single key":
    check poolEnvName("OPENAI_API_KEY") == "OPENAI_API_KEYS"
    check poolEnvName("ZAI_API_KEY") == "ZAI_API_KEYS"
    check poolEnvName("SOMETHING") == "SOMETHING_KEYS"

  test "a plural-only value still counts as available":
    clearCreds()
    defer: clearCreds()
    putEnv("OPENAI_API_KEYS", "a,b")
    check hasCredentialKey(["OPENAI_API_KEY"])
    check detectProviderAvailability().openai

  test "resolve rotates through the pool":
    clearCreds()
    defer: clearCreds()
    putEnv("OPENAI_API_KEYS", "a,b")
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "a"
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "b"
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "a"

  test "a single key becomes a one-key pool":
    clearCreds()
    defer: clearCreds()
    putEnv("OPENAI_API_KEY", "solo")
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "solo"
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "solo"

  test "a failed key cools down and the next request uses another":
    clearCreds()
    defer: clearCreds()
    putEnv("OPENAI_API_KEYS", "a,b")
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "a"
    noteCredentialResult("openai", "a", ok = false, error = "429 rate limit")
    check resolveCredentialKey("openai", ["OPENAI_API_KEY"]) == "b"

  test "cooldown depends on the failure kind":
    check cooldownForError("429 Too Many Requests") == 60_000
    check cooldownForError("rate limit exceeded") == 60_000
    check cooldownForError("insufficient_quota") == 15 * 60_000
    check cooldownForError("401 Unauthorized") == 30 * 60_000

  test "buildProviderSpec takes its key from the pool":
    clearCreds()
    defer: clearCreds()
    putEnv("OPENAI_API_KEYS", "a,b")
    let first = buildProviderSpec(ProviderPrefs(providerName: "openai"))
    let second = buildProviderSpec(ProviderPrefs(providerName: "openai"))
    check first.apiKey == "a"
    check second.apiKey == "b"

var gSeenKeys: seq[string]

proc keyedBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    gSeenKeys.add(spec.apiKey)
  let key = spec.apiKey
  let fn: CompleteFn = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    if key == "a":
      err("429 rate limit exceeded")
    else:
      ok(CompletionResponse(text: "ok from " & key))
  ProviderBundle(completeFn: fn, streamFn: nil)

proc staleKeyBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    gSeenKeys.add(spec.apiKey)
  let fn: CompleteFn = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    err("500 internal server error")
  ProviderBundle(completeFn: fn, streamFn: nil)

proc hooks(): tuple[res: CredentialResultHook, next: CredentialNextHook] =
  result.res = proc (providerName, key: string; ok: bool;
                     error: string) {.gcsafe.} =
    noteCredentialResult(providerName, key, ok, error)
  result.next = proc (providerName, currentKey: string): string {.gcsafe.} =
    nextCredentialKey(providerName, currentKey)

suite "in-flight credential retry":

  test "a 429 retries the same provider with the next key":
    clearCreds()
    defer: clearCreds()
    gSeenKeys = @[]
    putEnv("OPENAI_API_KEYS", "a,b")
    let h = hooks()
    let fn = buildAsyncCompleteFn(
      "provider = \"openai\"", keyedBuilderImpl,
      credentialResultHook = h.res, credentialNextHook = h.next)
    let res = waitFor fn(CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")]))
    check res.isOk
    check res.get().text == "ok from b"
    check gSeenKeys == @["a", "b"]

  test "a transport error does not burn another key":
    clearCreds()
    defer: clearCreds()
    gSeenKeys = @[]
    putEnv("OPENAI_API_KEYS", "a,b")
    let h = hooks()
    let fn = buildAsyncCompleteFn(
      "provider = \"openai\"", staleKeyBuilderImpl,
      credentialResultHook = h.res, credentialNextHook = h.next)
    let res = waitFor fn(CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")]))
    check res.isErr
    check gSeenKeys == @["a"]
