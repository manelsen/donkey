## bedrock.nim — AWS Bedrock through the Converse API.
##
## Two credentials, in this order:
##   1. a Bedrock API key (`AWS_BEARER_TOKEN_BEDROCK`), sent as a bearer;
##   2. IAM credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional
##      `AWS_SESSION_TOKEN`), signed with SigV4 for the `bedrock` service
##      (`core/security/aws_sigv4`, checked against AWS's published example).
## No SDK. The request body and the response are `domain/providers/bedrock_pure`.
## The transport is `provider_http`'s (deadline, no redirect, no repeated POST).
##
## Not implemented: ConverseStream (AWS binary event-stream framing), so the
## bundle has no `streamFn` and the turn runs without streaming.

import std/[json, strutils, times, uri]
import ../../core/pipeops
import ../../core/security/aws_sigv4
import ../../domain/message
import ../../domain/providers/bedrock_pure
import ../../ports/http
import ../../ports/provider
import ./provider_http

const BedrockSigningService = "bedrock"

type
  AmzClock* = proc(): string {.gcsafe.}
    ## `YYYYMMDDTHHMMSSZ` in UTC; injected so a signature is reproducible.

  BedrockAdapter* = object
    model*:           string
    baseUrl*:         string   ## `https://bedrock-runtime.<region>.amazonaws.com`
    bearer*:          string
    accessKeyId*:     string
    secretAccessKey*: string
    sessionToken*:    string
    http*:            HttpRuntimePort
    clock*:           AmzClock

proc utcAmzDate*(): string {.gcsafe.} =
  getTime().utc.format("yyyyMMdd'T'HHmmss'Z'")

proc newBedrockAdapter*(model: string; baseUrl = ""; bearer = "";
                        accessKeyId = ""; secretAccessKey = "";
                        sessionToken = ""; http = HttpRuntimePort();
                        clock: AmzClock = nil): BedrockAdapter =
  BedrockAdapter(
    model: model,
    baseUrl: if baseUrl.len > 0: baseUrl else: bedrockRuntimeUrl(""),
    bearer: bearer, accessKeyId: accessKeyId,
    secretAccessKey: secretAccessKey, sessionToken: sessionToken,
    http: http, clock: if clock != nil: clock else: utcAmzDate)

func hasCredential*(a: BedrockAdapter): bool =
  a.bearer.len > 0 or (a.accessKeyId.len > 0 and a.secretAccessKey.len > 0)

proc caps*(a: BedrockAdapter): ProviderCaps =
  ProviderCaps(name: "bedrock/" & a.model, streaming: false, toolCalling: true)

func hostOf(url: string): string =
  let parsed = parseUri(url)
  if parsed.port.len > 0 and parsed.port notin ["443", "80"]:
    parsed.hostname & ":" & parsed.port
  else:
    parsed.hostname

proc requestHeaders*(a: BedrockAdapter; url, body: string): seq[HttpHeader] =
  ## The headers sent with one request. With IAM credentials the `host` header
  ## is signed but not sent: the transport sets it from the URL, same value.
  result = @[(name: "Content-Type", value: "application/json"),
             (name: "Accept", value: "application/json")]
  if a.bearer.len > 0:
    result.add((name: "Authorization", value: "Bearer " & a.bearer))
    return
  let amzDate = a.clock()
  var signed = @[("content-type", "application/json"),
                 ("host", hostOf(url)),
                 ("x-amz-date", amzDate)]
  if a.sessionToken.len > 0:
    signed.add(("x-amz-security-token", a.sessionToken))
  let auth = authorizationHeader(SigV4Request(
      httpMethod: "POST",
      canonicalUri: canonicalUriOf(parseUri(url).path),
      headers: signed,
      payload: body),
    a.accessKeyId, a.secretAccessKey, amzDate, regionOfRuntimeUrl(a.baseUrl),
    BedrockSigningService)
  result.add((name: "X-Amz-Date", value: amzDate))
  if a.sessionToken.len > 0:
    result.add((name: "X-Amz-Security-Token", value: a.sessionToken))
  result.add((name: "Authorization", value: auth))

proc complete*(a: BedrockAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  if not a.hasCredential:
    return err("Bedrock: no credential (AWS_BEARER_TOKEN_BEDROCK or " &
               "AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)")
  providerGuard:
    let url = converseUrl(a.baseUrl, a.model)
    let body = $converseBody(req)
    let text = ? postProvider(a.http, "Bedrock", url, body,
                              a.requestHeaders(url, body))
    parseConverseResponse(parseJson(text))
