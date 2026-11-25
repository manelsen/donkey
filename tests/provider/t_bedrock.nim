## t_bedrock.nim — AWS Bedrock Converse on the wire, no network.
##
## Two auth modes: a Bedrock API key (`AWS_BEARER_TOKEN_BEDROCK`, sent as a
## bearer) and IAM credentials signed with SigV4 (service `bedrock`). The
## signature is recomputed here from the request the adapter sent, with the
## same fixed clock, so the header is checked against an independent signing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/bedrock
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/core/security/aws_sigv4
import donkey/domain/message
import donkey/domain/providers/bedrock_pure
import donkey/domain/providers/bedrock_stream_pure
import donkey/domain/providers/descriptors
import donkey/domain/providers/media_pure
import donkey/ports/http
import donkey/ports/provider

type
  Capture = ref object
    url:     string
    body:    string
    headers: seq[HttpHeader]
    calls:   int

const ReplyBody = """{"output":{"message":{"role":"assistant",
  "content":[{"text":"ok"}]}},"stopReason":"end_turn",
  "usage":{"inputTokens":3,"outputTokens":1}}"""

proc recordingPort(cap: Capture): HttpRuntimePort =
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      inc cap.calls
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: 200, body: ReplyBody)),
  )

func headerValue(headers: seq[HttpHeader]; name: string): string =
  for header in headers:
    if header.name.toLowerAscii() == name.toLowerAscii():
      return header.value
  ""

proc fixedClock(): string {.gcsafe.} = "20261123T120000Z"

proc adapterFor(cap: Capture; bearer = ""; access = ""; secret = "";
                token = ""; baseUrl = ""): BedrockAdapter =
  newBedrockAdapter(model = "amazon.nova-pro-v1:0", baseUrl = baseUrl,
    bearer = bearer, accessKeyId = access, secretAccessKey = secret,
    sessionToken = token, http = recordingPort(cap), clock = fixedClock)

proc hello(): CompletionRequest =
  CompletionRequest(messages: @[ChatMessage(role: roleUser, text: "oi")])

proc runTests*() =
  suite "bedrock — wire":
    test "a Bedrock API key goes as a bearer to the regional Converse URL":
      let cap = Capture()
      let res = adapterFor(cap, bearer = "bdk-test").complete(hello())
      require res.isOk
      check res.get.text == "ok"
      check res.get.inputTokens == 3
      check cap.url == "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.nova-pro-v1%3A0/converse"
      check headerValue(cap.headers, "Authorization") == "Bearer bdk-test"
      check parseJson(cap.body) == converseBody(hello())

    test "IAM credentials are signed with SigV4 for the bedrock service":
      let cap = Capture()
      let res = adapterFor(cap, access = "AKIDTEST", secret = "secret-test",
                           baseUrl = bedrockRuntimeUrl("eu-west-1")).complete(hello())
      require res.isOk
      check cap.url.startsWith("https://bedrock-runtime.eu-west-1.amazonaws.com/model/")
      check headerValue(cap.headers, "X-Amz-Date") == "20261123T120000Z"
      check headerValue(cap.headers, "X-Amz-Security-Token") == ""
      let expected = authorizationHeader(SigV4Request(
          httpMethod: "POST",
          canonicalUri: canonicalUriOf("/model/amazon.nova-pro-v1%3A0/converse"),
          headers: @[("content-type", "application/json"),
                     ("host", "bedrock-runtime.eu-west-1.amazonaws.com"),
                     ("x-amz-date", "20261123T120000Z")],
          payload: cap.body),
        "AKIDTEST", "secret-test", "20261123T120000Z", "eu-west-1", "bedrock")
      check headerValue(cap.headers, "Authorization") == expected
      check expected.startsWith(
        "AWS4-HMAC-SHA256 Credential=AKIDTEST/20261123/eu-west-1/bedrock/aws4_request")

    test "a session token is sent and signed":
      let cap = Capture()
      discard adapterFor(cap, access = "AKIDTEST", secret = "s", token = "tok").complete(hello())
      check headerValue(cap.headers, "X-Amz-Security-Token") == "tok"
      check "x-amz-security-token" in headerValue(cap.headers, "Authorization")

    test "the bearer wins when both are configured":
      let cap = Capture()
      discard adapterFor(cap, bearer = "bdk", access = "AKID", secret = "s").complete(hello())
      check headerValue(cap.headers, "Authorization") == "Bearer bdk"

    test "no credential: an error and no request":
      let cap = Capture()
      check adapterFor(cap).complete(hello()).isErr
      check cap.calls == 0

    test "an HTTP error keeps the provider name and body":
      let cap = Capture()
      let port = HttpRuntimePort(
        postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                         Result[HttpResponse, string] {.gcsafe.} =
          ok(HttpResponse(status: 403, body: """{"message":"denied"}""")))
      let a = newBedrockAdapter(model = "m", bearer = "b", http = port, clock = fixedClock)
      let res = a.complete(hello())
      check res.isErr
      check "Bedrock" in res.error and "denied" in res.error

  suite "bedrock — descriptor and bundle":
    test "identity, aliases and default model":
      let d = descriptorOr("bedrock")
      check d.id == "bedrock"
      check d.envNames == @["AWS_BEARER_TOKEN_BEDROCK"]
      check d.defaultModel == DefaultModelBedrock
      check descriptorOr("aws-bedrock").id == "bedrock"
      check descriptorOr("amazon-bedrock").id == "bedrock"

    test "the runtime builder wires the Bedrock adapter, streaming included":
      let bundle = buildProviderBundle(ProviderSpec(providerName: "bedrock",
        apiKey: "bdk", modelName: "amazon.nova-pro-v1:0"))
      check bundle.completeFn != nil
      check bundle.streamFn != nil
      check streamsToolCalls("bedrock")

    test "the stream calls converse-stream, asks for an event stream and reads it":
      let cap = Capture()
      let streamBody =
        encodeEventMessage(@[(":event-type", "contentBlockDelta"), (":message-type", "event")],
          $ %* {"contentBlockIndex": 0, "delta": {"text": "oi"}}) &
        encodeEventMessage(@[(":event-type", "contentBlockStart"), (":message-type", "event")],
          $ %* {"contentBlockIndex": 1, "start": {"toolUse": {"toolUseId": "t1", "name": "calc"}}}) &
        encodeEventMessage(@[(":event-type", "contentBlockDelta"), (":message-type", "event")],
          $ %* {"contentBlockIndex": 1, "delta": {"toolUse": {"input": "{}"}}}) &
        encodeEventMessage(@[(":event-type", "messageStop"), (":message-type", "event")],
          $ %* {"stopReason": "tool_use"})
      let port = HttpRuntimePort(
        postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                         Result[HttpResponse, string] {.gcsafe.} =
          cap.url = url
          cap.headers = headers
          ok(HttpResponse(status: 200, body: streamBody)))
      let a = newBedrockAdapter(model = "amazon.nova-pro-v1:0", bearer = "b",
                                http = port, clock = fixedClock)
      let r = a.makeStreamFn()(hello(), proc(tok: string) {.gcsafe.} = discard)
      check r.isOk
      check r.get.text == "oi"
      check r.get.toolCalls.len == 1 and r.get.toolCalls[0].name == "calc"
      check cap.url.endsWith("/model/amazon.nova-pro-v1%3A0/converse-stream")
      check headerValue(cap.headers, "Accept") == "application/vnd.amazon.eventstream"

    test "the streamed request is signed for its own URL":
      ## SigV4 covers the path: a signature made for /converse would fail.
      let cap = Capture()
      let a = adapterFor(cap, access = "AKIDEXAMPLE", secret = "s")
      let url = converseStreamUrl(a.baseUrl, a.model)
      check url.endsWith("/converse-stream")
      let signed = a.requestHeaders(url, "{}", accept = "application/vnd.amazon.eventstream")
      let plain = a.requestHeaders(converseUrl(a.baseUrl, a.model), "{}")
      check headerValue(signed, "Authorization") != headerValue(plain, "Authorization")

    test "vision by model":
      check visionSupport("bedrock", "us.anthropic.claude-sonnet-5-v1:0") == vsYes
      check visionSupport("bedrock", "amazon.nova-pro-v1:0") == vsYes
      check visionSupport("bedrock", "amazon.nova-micro-v1:0") == vsNo
      check visionSupport("bedrock", "meta.llama4-scout") == vsUnknown

when isMainModule:
  runTests()
