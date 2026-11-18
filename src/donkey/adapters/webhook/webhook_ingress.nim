## webhook_ingress.nim — the shared ingress decision for webhook channels.
##
## One place decides whether an inbound webhook may be processed. Channels
## differ only in protocol data (`WebhookAuthSpec`): the header names, the
## secret, what the MAC covers and how the timestamp is encoded. The MAC
## primitives themselves exist exactly once, in
## `core/security/webhook_auth.nim`, and this module re-exports them.
##
## Decision order (a rejection always happens before the MAC when it can):
##   1. empty secret                → wioNotConfigured   (route answers 404)
##   2. method != POST              → wioMethodNotAllowed
##   3. raw body over maxBodyBytes  → wioTooLarge
##   4. timestamp missing/malformed → wioForbidden
##   5. timestamp outside window    → wioStale
##   6. signature missing/mismatch  → wioForbidden
##   7. otherwise                   → wioAccepted
##
## The clock is injected (`nowUnixMs`); this module never reads the wall clock.
## `safeEquals` (constant-time-ish) is the only comparison used for secrets
## and MACs.
##
## Note: the MAC is the *raw* body, byte for byte. No JSON normalisation, no
## newline trimming and no re-serialisation happens here or in any caller.

import std/[strutils, tables]
import ../../core/security/webhook_auth

export webhook_auth

type
  WebhookRequest* = object
    httpMethod*: string
    path*:       string
    query*:      Table[string, string]
    headers*:    Table[string, string]  ## keys are lowercase
    body*:       string

  WebhookAuthScheme* = enum
    ## How the MAC digest is encoded on the wire. Only base64 is implemented;
    ## hex/shared-token channels are out of scope (PRD §3) and must not grow a
    ## second MAC implementation.
    wasHmacSha256Base64

  WebhookSignedPayload* = enum
    ## What the MAC covers for this protocol.
    wspBody                    ## base64(HMAC-SHA256(secret, raw body))
    wspTimestampNewlineSecret  ## base64(HMAC-SHA256(secret, timestamp & "\n" & secret))

  WebhookTimestampScale* = enum
    ## Unit of the protocol's timestamp header. `wtsNone` means the protocol
    ## has no signed timestamp and `replayWindowSec` is ignored.
    wtsNone
    wtsSeconds
    wtsMilliseconds

  WebhookIngressOutcome* = enum
    wioAccepted
    wioForbidden          ## missing/malformed signature or timestamp header
    wioMethodNotAllowed
    wioNotConfigured      ## no secret: the route must look absent (404)
    wioTooLarge           ## raw body over the channel limit
    wioStale              ## timestamp outside the replay window

  WebhookMacFn* = proc(secret, payload: string): string {.gcsafe, raises: [].}
    ## Test seam for proving the MAC is never reached on a rejected request.
    ## `nil` means the core `hmacSha256Base64`.

  WebhookAuthSpec* = object
    ## Everything a channel supplies; no MAC or comparison logic lives here.
    scheme*:          WebhookAuthScheme
    signedPayload*:   WebhookSignedPayload
    secret*:          string
    signatureHeader*: string
    timestampHeader*: string   ## empty when `timestampScale == wtsNone`
    replayWindowSec*: int64    ## symmetric window; ignored when scale is none
    timestampScale*:  WebhookTimestampScale
    maxBodyBytes*:    int      ## 0 = unlimited; checked before the MAC

# ── Request helpers ───────────────────────────────────────────────────────────

func header*(req: WebhookRequest; name: string): string =
  req.headers.getOrDefault(name.toLowerAscii())

func hasQuery*(req: WebhookRequest; key: string): bool =
  req.query.hasKey(key)

# ── Decision ──────────────────────────────────────────────────────────────────

proc computeMac(spec: WebhookAuthSpec; req: WebhookRequest; timestamp: string;
                macFn: WebhookMacFn): string {.raises: [].} =
  let mac: WebhookMacFn =
    if macFn != nil: macFn
    else: hmacSha256Base64
  case spec.scheme
  of wasHmacSha256Base64:
    case spec.signedPayload
    of wspBody:
      mac(spec.secret, req.body)
    of wspTimestampNewlineSecret:
      mac(spec.secret, timestamp & "\n" & spec.secret)

func timestampInWindow(spec: WebhookAuthSpec; ts: int64;
                       nowUnixMs: int64): bool =
  ## Bounds are inclusive, matching the previous DingTalk check. Comparisons
  ## stay in the header's own unit so a hostile near-int64 value can never
  ## overflow a scaling multiplication.
  let window = spec.replayWindowSec
  case spec.timestampScale
  of wtsMilliseconds:
    let w = window * 1000
    ts >= nowUnixMs - w and ts <= nowUnixMs + w
  of wtsSeconds:
    let nowSec = nowUnixMs div 1000
    ts >= nowSec - window and ts <= nowSec + window
  of wtsNone:
    true

proc decideIngress*(spec: WebhookAuthSpec; req: WebhookRequest;
                    nowUnixMs: int64;
                    macFn: WebhookMacFn = nil): WebhookIngressOutcome {.raises: [].} =
  ## Pure decision for one inbound request. `nowUnixMs` is supplied by the
  ## adapter layer (it is ignored when the protocol has no timestamp).
  if spec.secret.len == 0:
    return wioNotConfigured
  if req.httpMethod != "POST":
    return wioMethodNotAllowed
  if spec.maxBodyBytes > 0 and req.body.len > spec.maxBodyBytes:
    return wioTooLarge

  var timestamp = ""
  if spec.timestampScale != wtsNone:
    timestamp = req.header(spec.timestampHeader)
    if timestamp.len == 0:
      return wioForbidden
    var parsed: int64
    try:
      parsed = parseBiggestInt(timestamp)
    except ValueError:
      return wioForbidden
    if not timestampInWindow(spec, parsed, nowUnixMs):
      return wioStale

  let signature = req.header(spec.signatureHeader)
  if signature.len == 0:
    return wioForbidden
  let expected = computeMac(spec, req, timestamp, macFn)
  if not safeEquals(signature, expected):
    return wioForbidden
  wioAccepted
