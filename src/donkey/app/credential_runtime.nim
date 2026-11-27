## credential_runtime.nim — process-wide provider credential pools.
##
## A provider may carry several keys: the plural env next to the single one
## (`OPENAI_API_KEYS` beside `OPENAI_API_KEY`). Selection rotates over healthy
## keys, and a key that returned an auth/rate/quota error cools down so the
## next request uses another one.
##
## The keys come from the environment snapshot, installed once at startup
## with `useCredentials` (tests install their own instead of `putEnv`).
## Provider specs are built on the event loop and the credential hooks run
## there after each await, so the snapshot and the pools are thread-local to
## it: gcsafe with no lock and no cast. Another thread would see no keys;
## `ThreadOwner` logs such a use instead of letting it pass as "no credential".

import std/[options, strutils, tables]
import ../core/pipeops
import ../core/providers/credential_pool
import ../core/providers/smart_routing
import ../config/environment
import ../domain/providers/bedrock_pure
import ../domain/providers/descriptors
import ../infra/thread_owner
import ../domain/a2a/a2a_client_pure

var
  gPools {.threadvar.}: Table[string, CredentialPool]
  gCredentials {.threadvar.}: Environment
  gCredentialsOwner: ThreadOwner
  gA2aAgents {.threadvar.}: seq[A2aAgent]

proc useCredentials*(env: Environment) {.gcsafe, raises: [].} =
  ## Installs the snapshot the provider keys are read from, and forgets the
  ## pools built from the previous one.
  if gCredentialsOwner.isOwner("provider credentials"):
    gCredentials = env
    gPools.clear()

proc setCredentialForTest*(name, value: string) {.gcsafe, raises: [].} =
  ## Test hook: sets one variable in the installed snapshot ("" unsets it).
  if gCredentialsOwner.isOwner("provider credentials"):
    gCredentials = gCredentials.with(name, value)

proc credentialValue(name: string): string {.gcsafe, raises: [].} =
  if gCredentialsOwner.isOwner("provider credentials"):
    gCredentials.stripped(name)
  else:
    ""

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

proc credentialSet*(name: string): bool {.gcsafe, raises: [].} =
  ## Whether the installed snapshot has a value for `name`: presence only,
  ## for status views that list what is configured (never the value).
  credentialValue(name).len > 0

proc useA2aAgents*(agents: seq[A2aAgent]) {.gcsafe, raises: [].} =
  ## `[[a2a.agents]]` (E13.4): the agents delegate_to_agent may call; their
  ## tokens are read from the same snapshot as the providers' keys.
  if gCredentialsOwner.isOwner("provider credentials"):
    gA2aAgents = agents

proc a2aAgents*(): seq[A2aAgent] {.gcsafe, raises: [].} =
  if gCredentialsOwner.isOwner("provider credentials"): gA2aAgents else: @[]

proc a2aToken*(agent: A2aAgent): string {.gcsafe, raises: [].} =
  ## The token the agent gave by pairing, from its `token_env`; "" when unset.
  credentialValue(agent.tokenEnv)

proc githubToken*(): string {.gcsafe, raises: [].} =
  ## The token behind the github tool; "" when it is off.
  credentialValue("GITHUB_TOKEN")

proc webSearchKey*(): string {.gcsafe, raises: [].} =
  ## The Brave Search key behind the web_search tool; "" when it is off.
  credentialValue("BRAVE_API_KEY")

func firstCredential*(env: Environment; envNames: openArray[string]): string =
  ## The first value over the names, single or plural; "" when none is set.
  for envName in envNames:
    let single = env.stripped(envName)
    if single.len > 0:
      return single
    let plural = splitKeys(env.get(poolEnvName(envName)))
    if plural.len > 0:
      return plural[0]
  ""

func configuredIn*(env: Environment; id: string): bool =
  ## True when the descriptor's env has a single or plural value in `env`.
  ## Local providers use their endpoint env instead of a credential.
  let d = descriptorOr(id)
  if d.authType == atNone:
    return d.envNames.len > 0 and env.has(d.envNames[0])
  if d.id == "bedrock" and env.stripped("AWS_ACCESS_KEY_ID").len > 0 and
      env.stripped("AWS_SECRET_ACCESS_KEY").len > 0:
    return true  ## IAM credentials, signed with SigV4
  firstCredential(env, d.envNames).len > 0

proc installedCredentials(): Environment {.gcsafe, raises: [].} =
  if gCredentialsOwner.isOwner("provider credentials"): gCredentials
  else: Environment()

proc hasCredentialKey*(envNames: openArray[string]): bool {.gcsafe, raises: [].} =
  ## True when any name has a single or plural value in the installed
  ## snapshot. Availability is computed without touching the pool.
  firstCredential(installedCredentials(), envNames).len > 0

proc resetCredentialPools*() {.gcsafe, raises: [].} =
  ## Test hook: forget rotation and cooldown state.
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
    var keys = splitKeys(credentialValue(poolEnvName(envName)))
    if keys.len == 0:
      let single = credentialValue(envName)
      if single.len > 0:
        keys = @[single]
    if keys.len == 0:
      continue
    var pool = gPools.getOrDefault(providerName)
    if pool.keys != keys:
      pool = initCredentialPool(keys)
    let picked = pool.pick(nowMs)
    gPools[providerName] = pool
    if picked.isSome:
      return picked.get()
    return ""
  ""

proc providerConfigured*(id: string): bool {.gcsafe, raises: [].} =
  ## `configuredIn` over the installed snapshot.
  configuredIn(installedCredentials(), id)

proc descriptorApiKey*(d: ProviderDescriptor; nowMs = nowMs()): string
                       {.gcsafe, raises: [].} =
  ## The credential (or endpoint for local providers) the descriptor names.
  if d.authType == atNone:
    if d.envNames.len == 0:
      return ""
    return credentialValue(d.envNames[0])
  resolveCredentialKey(d.id, d.envNames, nowMs)

proc descriptorBaseUrl*(d: ProviderDescriptor): string {.gcsafe, raises: [].} =
  ## The descriptor's `baseUrlEnv` override from the installed snapshot.
  ## Bedrock without an override is the runtime URL of `AWS_REGION`
  ## (then `AWS_DEFAULT_REGION`, then us-east-1).
  if d.id == "bedrock":
    let explicit = credentialValue(d.baseUrlEnv)
    if explicit.len > 0: return explicit
    var region = credentialValue("AWS_REGION")
    if region.len == 0: region = credentialValue("AWS_DEFAULT_REGION")
    return bedrockRuntimeUrl(region)
  if d.baseUrlEnv.len == 0: "" else: credentialValue(d.baseUrlEnv)

proc awsCredentialValue*(name: string): string {.gcsafe, raises: [].} =
  ## Bedrock's IAM credentials, read from the installed snapshot.
  credentialValue(name)

proc nextCredentialKey*(providerName, currentKey: string;
                        nowMs = nowMs()): string {.gcsafe, raises: [].} =
  ## Another healthy key for an in-flight retry; "" when there is none.
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
  if not gPools.hasKey(providerName):
    return
  var pool = gPools.getOrDefault(providerName)
  if ok:
    pool.noteSuccess(key)
  else:
    pool.noteFailure(key, nowMs, cooldownForError(error))
  gPools[providerName] = pool

proc detectProviderAvailability*(): ProviderAvailability {.gcsafe, raises: [].} =
  ## One field per provider, all derived from the descriptor env names. The
  ## plural credential env alone also marks a provider available.
  ProviderAvailability(
    openrouter: providerConfigured("openrouter"),
    anthropic: providerConfigured("anthropic"),
    openai: providerConfigured("openai"),
    deepseek: providerConfigured("deepseek"),
    zaiAnthropic: providerConfigured("zai-anthropic"),
    gemini: providerConfigured("gemini"),
    minimax: providerConfigured("minimax"),
    zai: providerConfigured("zai"),
    zaiCoding: providerConfigured("zai-coding"),
    groq: providerConfigured("groq"),
    ollama: providerConfigured("ollama"),
    opencodeGo: providerConfigured("opencode-go"),
    zen: providerConfigured("zen"),
    nvidia: providerConfigured("nvidia"),
    mistral: providerConfigured("mistral"),
    bedrock: providerConfigured("bedrock"),
    alibaba: providerConfigured("alibaba"),
    fireworks: providerConfigured("fireworks"),
    # Azure needs its resource URL as well as the key.
    azure: providerConfigured("azure") and
           descriptorBaseUrl(descriptorOr("azure")).len > 0,
  )
