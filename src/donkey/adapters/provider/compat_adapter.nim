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

import std/[httpclient, json, streams, strutils]
import ../../domain/message
import ../../domain/providers/compat
import ../../domain/providers/openai_pure
import ../../ports/provider
import ../../core/pipeops
import ../http/helpers
import openai

const CompatHttpTimeoutSec* = 120
  ## A stalled provider must not hang the turn forever, and `redirectLimit = 0`
  ## keeps the provider Bearer from being forwarded to another host.

type
  CompatProfileFn* = proc(): CompatProfile {.gcsafe, nimcall.}
    ## A top-level constructor, never a closure: it returns a fresh profile
    ## (and fresh JsonNodes) on every call.

  CompatAdapter* = object
    apiKey*:       string
    model*:        string
    providerName*: string   ## display label, e.g. "NVIDIA"
    profileFn*:    CompatProfileFn

# ── Concept conformance ───────────────────────────────────────────────────────

func displayName*(a: CompatAdapter): string =
  if a.providerName.len > 0: a.providerName else: "OpenAI"

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

proc complete*(a: CompatAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let profile = a.profileFn()
  try:
    let client = newHttpClient(timeout = CompatHttpTimeoutSec * 1000,
                               maxRedirects = 0)
    defer: client.close()
    var headers = newHttpHeaders()
    for (name, value) in a.requestHeaders(profile):
      headers[name] = value
    client.headers = headers
    let resp = client.post(requestUrl(profile), body = $a.buildBody(req))
    checkApiStatus(resp, a.displayName)
    resp.body |> parseJson |> parseCompatBody
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
      let client = newHttpClient(timeout = CompatHttpTimeoutSec * 1000,
                                 maxRedirects = 0)
      defer: client.close()
      var headers = newHttpHeaders()
      for (name, value) in a.requestHeaders(profile):
        headers[name] = value
      client.headers = headers
      let resp = client.request(requestUrl(profile), httpMethod = HttpPost,
                                body = $a.buildBody(req, stream = true))
      checkApiStatus(resp, a.displayName)
      consumeCompatSse(resp.bodyStream, onToken)
    except CatchableError as e:
      err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newCompatAdapter*(apiKey: string;
                       model: string;
                       providerName = "";
                       profileFn: CompatProfileFn): CompatAdapter =
  CompatAdapter(
    apiKey:       apiKey,
    model:        model,
    providerName: providerName,
    profileFn:    profileFn,
  )
