## compat_adapter.nim — the single ProviderPort for every provider that speaks
## the OpenAI chat/completions dialect.
##
## A provider contributes *data*, not code: a `CompatProfile` supplies the
## endpoint, the extra headers, the payload extras and the wire quirks, and this
## adapter turns it into I/O. There is no per-provider HTTP adapter.
##
## Thread discipline: a `CompatProfile` owns JsonNodes, so the adapter stores
## only a `profileFn` and rebuilds the profile inside `complete` and inside the
## stream worker. No JsonNode is captured across a thread; the closure holds
## strings and a top-level proc pointer only.
##
## Streaming reuses the OpenAI SSE content parser (`parseOpenAISseLine`): text
## deltas plus `[DONE]`. `delta.reasoning` is out of scope (see PRD §11). A body
## that never yields a `data:` event is an error, not an empty success — the
## same stance as the non-streaming path.
##
## Both paths take an optional `HttpRuntimePort`; without one they use the
## provider transport (deadline, no redirects, no repeated POST). The injected
## port is what makes the provider profile observable from a test: the fake
## captures the URL, the headers and the body the bundle actually emits.

import std/[json, streams, strutils]
import ../../domain/message
import ../../domain/providers/compat
import ../../domain/providers/openai_pure
import ../../ports/http
import ../../ports/provider
import ../../core/pipeops
import ./provider_http
import openai

const CompatHttpTimeoutSec* = ProviderHttpTimeoutSec
  ## Same deadline as every provider (see provider_http).

type
  CompatProfileFn* = proc(): CompatProfile {.gcsafe.}
    ## A gcsafe constructor that returns a fresh profile (and fresh JsonNodes)
    ## on every call. A closure is allowed because the per-model choice (the
    ## Fireworks reasoning_off allowlist) is captured; only the proc pointer
    ## crosses into the adapter, never a JsonNode.

  CompatAdapter* = object
    apiKey*:       string
    model*:        string
    providerName*: string   ## display label, e.g. "NVIDIA"
    profileFn*:    CompatProfileFn
    http*:         HttpRuntimePort
      ## Optional transport for `complete`. An empty port (both `post` and
      ## `postNoRedirect` nil) uses the provider transport; a set
      ## port owns its timeout and retry policy, so the adapter only adds the
      ## profile headers and parses the body.

# ── Concept conformance ───────────────────────────────────────────────────────

func displayName*(a: CompatAdapter): string =
  if a.providerName.len > 0: a.providerName else: "OpenAI"

func hasHttp*(a: CompatAdapter): bool =
  ## True when `complete` will use the injected port. Both POST entry points
  ## count: a fake may fill either one.
  a.http.post != nil or a.http.postNoRedirect != nil

proc caps*(a: CompatAdapter): ProviderCaps =
  ## The context window stays 0 (unknown) until `modelLimits` (US-002/US-005).
  ProviderCaps(
    name:              a.displayName.toLowerAscii & "/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  0,
    requiresUserFirst: false,
  )

# ── Pure request pieces ───────────────────────────────────────────────────────

proc buildBody*(a: CompatAdapter; req: CompletionRequest;
                stream = false): JsonNode =
  ## Exported for unit testing of the JSON body without live HTTP.
  buildCompatRequestBody(a.profileFn(), a.model, req, stream)

func requestHeaders*(a: CompatAdapter;
                     profile: CompatProfile): seq[(string, string)] =
  ## The credential and content type, then whatever the profile requires. The
  ## profile's headers may override the defaults (last write wins in HTTP).
  result = @[("Content-Type", "application/json"),
             ("Authorization", "Bearer " & a.apiKey)]
  for header in profile.extraHeaders:
    result.add header

func requestUrl*(profile: CompatProfile): string =
  profile.endpoint

proc parseCompatBody*(body: JsonNode): Result[CompletionResponse, string] =
  ## `openai_pure` owns the wire parse; this guard turns a body without
  ## `choices` (or an error payload) into a Result instead of a nil deref.
  let choices = if body.isNil: nil else: body{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    var detail = ""
    if not body.isNil and body.kind == JObject:
      detail = body{"error"}{"message"}.getStr("")
    if detail.len > 0:
      return err("compat provider error: " & detail)
    return err("Invalid compat response: missing 'choices'")
  parseResponseFrom(body)

# ── HTTP call ─────────────────────────────────────────────────────────────────

func wireHeaders(a: CompatAdapter; profile: CompatProfile): seq[HttpHeader] =
  ## `requestHeaders` as the port's tuple type.
  for (name, value) in a.requestHeaders(profile):
    result.add (name: name, value: value)

proc completeWithPort(a: CompatAdapter; profile: CompatProfile;
                      body: string): Result[CompletionResponse, string] =
  ## The injected transport: `postNoRedirect` when available (the production
  ## no-redirect contract), otherwise `post`. Status handling mirrors
  ## `apiError`, including the provider label.
  if not a.hasHttp:
    return err("compat adapter: no injected http port")
  let post = if a.http.postNoRedirect != nil: a.http.postNoRedirect
             else: a.http.post
  let sent = post(requestUrl(profile), body, a.wireHeaders(profile))
  if sent.isErr:
    return err(sent.error)
  let resp = sent.get()
  if resp.status < 200 or resp.status >= 300:
    return err(apiError(a.displayName, resp.status, resp.body))
  parseCompatBody(parseJson(resp.body))

proc complete*(a: CompatAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let profile = a.profileFn()
  try:
    if a.hasHttp:
      return a.completeWithPort(profile, $a.buildBody(req))
    let body = ? postProvider(HttpRuntimePort(), a.displayName, requestUrl(profile),
                              $a.buildBody(req), a.wireHeaders(profile))
    body |> parseJson |> parseCompatBody
  except CatchableError as e:
    err(e.msg)

# ── Streaming ─────────────────────────────────────────────────────────────────

proc consumeCompatSse*(input: Stream;
                       onToken: proc(tok: string) {.gcsafe.}
                      ): Result[CompletionResponse, string] =
  ## Reads the OpenAI SSE dialect from `input`. Exported so the error paths can
  ## be tested without a socket. `onToken` may be nil (tests).
  ##
  ## Errors mirror `complete`: a malformed `data:` payload surfaces the parse
  ## error, and a body with no `data:` event at all (HTML error page, JSON
  ## error with status 200) is an error carrying a short diagnostic — never an
  ## empty success.
  var accumulated = ""
  var inputTokens = 0
  var outputTokens = 0
  var sawEvent = false
  var sawDone = false
  var diagnostic = ""
  var line = ""
  while input.readLine(line):
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed == "data:" or trimmed.startsWith(":"):
      continue                       ## blank line, heartbeat, SSE comment
    if not trimmed.startsWith("data:"):
      if diagnostic.len < 200:
        diagnostic.add(trimmed)
        diagnostic.add(' ')
      continue
    let parsed = parseOpenAISseLine(trimmed)
    if parsed.isErr:
      return err("compat provider stream error: " & parsed.error)
    let chunk = parsed.value
    sawEvent = true
    if chunk.done:
      sawDone = true
      break
    if chunk.token.len > 0:
      accumulated.add(chunk.token)
      if onToken != nil:
        onToken(chunk.token)
    if chunk.inputTokens > 0: inputTokens = chunk.inputTokens
    if chunk.outputTokens > 0: outputTokens = chunk.outputTokens

  if not sawEvent:
    let detail = diagnostic.strip
    if detail.len > 0:
      return err("compat provider returned a non-SSE response: " & detail)
    return err("compat provider returned a non-SSE response: empty body")
  if not sawDone:
    ## EOF without `[DONE]` is a cut connection, not a finished answer: the
    ## accumulated text is partial and must not be reported as complete.
    return err("compat provider stream ended without [DONE] (truncated)")

  ok CompletionResponse(
    text:         accumulated,
    inputTokens:  inputTokens,
    outputTokens: outputTokens,
  )

proc makeStreamFn*(a: CompatAdapter): StreamFn =
  ## SSE streaming in the OpenAI dialect: content deltas and `[DONE]`.
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    ## The profile is rebuilt inside the worker: no JsonNode is captured.
    let profile = a.profileFn()
    try:
      ## A fake that fills only `post` keeps the production transport here.
      let stream = ? postProviderStream(
        (if a.http.postNoRedirect != nil: a.http else: HttpRuntimePort()),
        a.displayName, requestUrl(profile), $a.buildBody(req, stream = true),
        a.wireHeaders(profile))
      consumeCompatSse(stream, onToken)
    except CatchableError as e:
      err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newCompatAdapter*(apiKey: string;
                       model: string;
                       providerName = "";
                       profileFn: CompatProfileFn;
                       http = HttpRuntimePort()): CompatAdapter =
  CompatAdapter(
    apiKey:       apiKey,
    model:        model,
    providerName: providerName,
    profileFn:    profileFn,
    http:         http,
  )
