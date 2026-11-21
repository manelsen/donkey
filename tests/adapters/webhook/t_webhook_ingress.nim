## webhook_ingress tests — the single ingress decision for webhook channels.
##
## The MAC known-answer vector is external (same one as
## `tests/core/security/t_webhook_auth.nim`):
##
##   printf '%s' '{"events":[]}' | \
##     openssl dgst -sha256 -hmac 'test-channel-secret' -binary | base64
##
## Everything here is pure: no sockets, no wall clock (the decision receives
## `nowUnixMs`), and the request body is always the exact bytes that were
## signed.

import std/[json, strutils, tables, unittest]
import donkey/domain/channels/line_policy
import donkey/adapters/webhook/webhook_ingress

const
  KatSecret = "test-channel-secret"
  KatBody   = """{"events":[]}"""
  KatSig    = "sKRrt+MTE71nWWZPaYrvYSdH9JGlgckmBidZxDuPgPc="

  FixedNowMs = 1_700_000_000_000'i64

var gMacCalls = 0

proc countingMac(secret, payload: string): string {.gcsafe, raises: [].} =
  ## Test seam: counts every MAC computation so a decision can be proven to
  ## reject before reaching the crypto path.
  inc gMacCalls
  hmacSha256Base64(secret, payload)

proc mkReq(httpMethod = "POST";
           body = KatBody;
           headers: openArray[(string, string)] = []): WebhookRequest =
  var h: Table[string, string]
  for (k, v) in headers:
    h[k.toLowerAscii()] = v
  WebhookRequest(httpMethod: httpMethod, path: "/webhook/test", query: initTable[string, string](),
                 headers: h, body: body)

func lineSpec(secret = KatSecret; maxBodyBytes = 0): WebhookAuthSpec =
  WebhookAuthSpec(
    scheme: wasHmacSha256Base64,
    signedPayload: wspBody,
    secret: secret,
    signatureHeader: LineSignatureHeader,
    timestampScale: wtsNone,
    maxBodyBytes: maxBodyBytes,
  )

func dingtalkSpec(secret = "dt-secret"; windowSec = 3_600'i64): WebhookAuthSpec =
  WebhookAuthSpec(
    scheme: wasHmacSha256Base64,
    signedPayload: wspTimestampNewlineSecret,
    secret: secret,
    signatureHeader: "sign",
    timestampHeader: "timestamp",
    replayWindowSec: windowSec,
    timestampScale: wtsMilliseconds,
  )

func signLine(secret: string; body: string): string =
  hmacSha256Base64(secret, body)

func signDingTalk(secret: string; timestamp: string): string =
  hmacSha256Base64(secret, timestamp & "\n" & secret)

proc runTests*() =
  suite "webhook ingress — known-answer vector":

    test "the external LINE/DingTalk vector is accepted":
      let req = mkReq(headers = [(LineSignatureHeader, KatSig)])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioAccepted

    test "the ingress re-exports the core MAC primitives":
      check hmacSha256Base64(KatSecret, KatBody) == KatSig
      check safeEquals(KatSig, KatSig)

  suite "webhook ingress — signature verdicts":

    test "a wrong signature is invalid":
      let req = mkReq(headers = [(LineSignatureHeader, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "a truncated signature is invalid":
      let req = mkReq(headers = [(LineSignatureHeader, KatSig[0 ..< 10])])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "a one-byte-changed signature is invalid":
      var changed = KatSig
      changed[0] = if changed[0] == 'A': 'B' else: 'A'
      check changed.len == KatSig.len
      let req = mkReq(headers = [(LineSignatureHeader, changed)])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "a valid signature under the wrong secret is invalid":
      let req = mkReq(headers = [(LineSignatureHeader, KatSig)])
      check decideIngress(lineSpec(secret = "other-secret"), req, FixedNowMs) ==
        wioForbidden

    test "a missing signature header is invalid":
      check decideIngress(lineSpec(), mkReq(), FixedNowMs) == wioForbidden

  suite "webhook ingress — configuration verdict":

    test "an empty secret is not configured, never accepted":
      let req = mkReq(headers = [(LineSignatureHeader, KatSig)])
      check decideIngress(lineSpec(secret = ""), req, FixedNowMs) == wioNotConfigured

    test "not-configured is distinguishable from invalid":
      ## The route answers 404 for not-configured and 403 for invalid.
      check wioNotConfigured != wioForbidden
      let valid = mkReq(headers = [(LineSignatureHeader, KatSig)])
      check decideIngress(lineSpec(secret = ""), valid, FixedNowMs) == wioNotConfigured
      check decideIngress(lineSpec(), mkReq(headers = [(LineSignatureHeader, "bogus")]),
                          FixedNowMs) == wioForbidden

  suite "webhook ingress — raw body bytes are signed":

    test "a trailing newline invalidates the signature":
      let signed = signLine(KatSecret, KatBody & "\n")
      let req = mkReq(body = KatBody, headers = [(LineSignatureHeader, signed)])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "a trailing space invalidates the signature":
      let signed = signLine(KatSecret, KatBody & " ")
      let req = mkReq(body = KatBody, headers = [(LineSignatureHeader, signed)])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "a re-serialised JSON body invalidates the signature":
      let spaced = """{"events": []}"""
      let reserialised = $parseJson(spaced)
      check reserialised != spaced
      let signed = signLine(KatSecret, reserialised)
      let req = mkReq(body = spaced, headers = [(LineSignatureHeader, signed)])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioForbidden

    test "the exact raw bytes are accepted even when they contain spaces":
      let spaced = """{"events": []}"""
      let req = mkReq(body = spaced,
                      headers = [(LineSignatureHeader, signLine(KatSecret, spaced))])
      check decideIngress(lineSpec(), req, FixedNowMs) == wioAccepted

  suite "webhook ingress — raw body limit":

    test "a body over the limit is refused before the MAC":
      gMacCalls = 0
      let body = repeat('x', 11)
      let req = mkReq(body = body,
                      headers = [(LineSignatureHeader, signLine(KatSecret, body))])
      check decideIngress(lineSpec(maxBodyBytes = 10), req, FixedNowMs) == wioTooLarge
      check gMacCalls == 0

    test "a body exactly at the limit still reaches the MAC":
      gMacCalls = 0
      let body = repeat('x', 10)
      let req = mkReq(body = body,
                      headers = [(LineSignatureHeader, signLine(KatSecret, body))])
      check decideIngress(lineSpec(maxBodyBytes = 10), req, FixedNowMs, countingMac) ==
        wioAccepted
      check gMacCalls == 1

    test "a nil MAC override uses the core implementation":
      let req = mkReq(headers = [(LineSignatureHeader, KatSig)])
      check decideIngress(lineSpec(), req, FixedNowMs, nil) == wioAccepted

  suite "webhook ingress — timestamp and replay window":

    test "a fresh timestamp is accepted with an injected clock":
      let ts = $(FixedNowMs - 1_000)
      let req = mkReq(headers = [("timestamp", ts), ("sign", signDingTalk("dt-secret", ts))])
      check decideIngress(dingtalkSpec(), req, FixedNowMs) == wioAccepted

    test "the window boundary is inclusive":
      let ts = $(FixedNowMs - 3_600_000)
      let req = mkReq(headers = [("timestamp", ts), ("sign", signDingTalk("dt-secret", ts))])
      check decideIngress(dingtalkSpec(), req, FixedNowMs) == wioAccepted

    test "an old timestamp is stale even with a valid MAC":
      let ts = $(FixedNowMs - 3_600_001)
      let req = mkReq(headers = [("timestamp", ts), ("sign", signDingTalk("dt-secret", ts))])
      check decideIngress(dingtalkSpec(), req, FixedNowMs) == wioStale

    test "a future timestamp is stale":
      let ts = $(FixedNowMs + 3_600_001)
      let req = mkReq(headers = [("timestamp", ts), ("sign", signDingTalk("dt-secret", ts))])
      check decideIngress(dingtalkSpec(), req, FixedNowMs) == wioStale

    test "a stale timestamp is refused before the MAC":
      gMacCalls = 0
      let ts = $(FixedNowMs - 3_600_001)
      let req = mkReq(headers = [("timestamp", ts), ("sign", signDingTalk("dt-secret", ts))])
      check decideIngress(dingtalkSpec(), req, FixedNowMs, countingMac) == wioStale
      check gMacCalls == 0

    test "a missing or non-numeric timestamp is invalid before the MAC":
      gMacCalls = 0
      let sign = signDingTalk("dt-secret", "0")
      check decideIngress(dingtalkSpec(),
                          mkReq(headers = [("sign", sign)]), FixedNowMs,
                          countingMac) == wioForbidden
      check decideIngress(dingtalkSpec(),
                          mkReq(headers = [("timestamp", "not-a-number"),
                                           ("sign", sign)]), FixedNowMs) ==
        wioForbidden
      check gMacCalls == 0

    test "a second-scale window is compared against the same clock":
      gMacCalls = 0
      let spec = WebhookAuthSpec(
        scheme: wasHmacSha256Base64,
        signedPayload: wspTimestampNewlineSecret,
        secret: "dt-secret",
        signatureHeader: "sign",
        timestampHeader: "timestamp",
        replayWindowSec: 300,
        timestampScale: wtsSeconds,
      )
      let nowSec = FixedNowMs div 1000
      let fresh = $nowSec
      check decideIngress(spec,
                          mkReq(headers = [("timestamp", fresh),
                                           ("sign", signDingTalk("dt-secret", fresh))]),
                          FixedNowMs) == wioAccepted
      let old = $(nowSec - 301)
      check decideIngress(spec,
                          mkReq(headers = [("timestamp", old),
                                           ("sign", signDingTalk("dt-secret", old))]),
                          FixedNowMs) == wioStale

  suite "webhook ingress — method verdict":

    test "a non-POST request is refused":
      check decideIngress(lineSpec(), mkReq(httpMethod = "GET"), FixedNowMs) ==
        wioMethodNotAllowed

    test "an unconfigured route answers not-configured before the method":
      check decideIngress(lineSpec(secret = ""), mkReq(httpMethod = "GET"), FixedNowMs) ==
        wioNotConfigured

  suite "webhook ingress — request helpers":

    test "header lookup is case-insensitive and hasQuery sees the table":
      let req = mkReq(headers = [("X-Custom", "v")])
      check req.header("x-custom") == "v"
      check req.header("X-CUSTOM") == "v"
      check not req.hasQuery("access_token")

when isMainModule:
  runTests()
