## aws_sigv4.nim — AWS Signature Version 4, pure.
##
## Only what a JSON POST to an AWS endpoint needs (Bedrock Converse): canonical
## request, string to sign, signing key and the `Authorization` header. No
## clock and no I/O: the caller passes the timestamp. Verified against the
## example AWS publishes (tests/core/security/t_aws_sigv4.nim).
##
## Steps (AWS General Reference, SigV4):
##   canonical request = method \n canonical URI \n canonical query \n
##                       canonical headers \n signed headers \n sha256(payload)
##   string to sign    = "AWS4-HMAC-SHA256" \n amzDate \n scope \n sha256(canonical)
##   signing key       = HMAC chain "AWS4"+secret → date → region → service → "aws4_request"

import std/[algorithm, strutils]
import nimcrypto/sha2
import ./webhook_auth

type
  SigV4Request* = object
    httpMethod*:     string
    canonicalUri*:   string   ## already in canonical form (see `canonicalUriOf`)
    canonicalQuery*: string   ## already sorted and encoded; "" for none
    headers*:        seq[(string, string)]  ## every header to sign, host included
    payload*:        string

func sha256Hex*(data: string): string =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())
  ctx.clear()

func uriEncode*(s: string): string =
  ## RFC 3986 unreserved characters kept; everything else %XX, uppercase hex.
  for c in s:
    if c in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_', '.', '~'}:
      result.add(c)
    else:
      result.add('%' & toHex(ord(c), 2))

func canonicalUriOf*(requestPath: string): string =
  ## The request path is sent with each segment encoded once; SigV4 (every
  ## service but S3) encodes each segment again for the canonical URI.
  if requestPath.len == 0: return "/"
  var parts: seq[string]
  for segment in requestPath.split('/'):
    parts.add(uriEncode(segment))
  parts.join("/")

func canonicalHeaderValue(value: string): string =
  value.strip().splitWhitespace().join(" ")

func sortedHeaders(req: SigV4Request): seq[(string, string)] =
  for (name, value) in req.headers:
    result.add((name.toLowerAscii(), canonicalHeaderValue(value)))
  result.sort(proc(a, b: (string, string)): int = cmp(a[0], b[0]))

func signedHeaders*(req: SigV4Request): string =
  var names: seq[string]
  for (name, _) in sortedHeaders(req):
    names.add(name)
  names.join(";")

func canonicalRequest*(req: SigV4Request): string =
  var headerBlock = ""
  for (name, value) in sortedHeaders(req):
    headerBlock.add(name & ":" & value & "\n")
  [req.httpMethod, req.canonicalUri, req.canonicalQuery, headerBlock,
   signedHeaders(req), sha256Hex(req.payload)].join("\n")

func credentialScope*(date, region, service: string): string =
  date & "/" & region & "/" & service & "/aws4_request"

func signingKey*(secret, date, region, service: string): string =
  hmacSha256Raw(hmacSha256Raw(hmacSha256Raw(hmacSha256Raw(
    "AWS4" & secret, date), region), service), "aws4_request")

func signingKeyHex*(secret, date, region, service: string): string =
  for c in signingKey(secret, date, region, service):
    result.add(ord(c).toHex(2).toLowerAscii())

func stringToSign*(req: SigV4Request; amzDate, region, service: string): string =
  ["AWS4-HMAC-SHA256", amzDate,
   credentialScope(amzDate[0 ..< 8], region, service),
   sha256Hex(canonicalRequest(req))].join("\n")

func authorizationHeader*(req: SigV4Request; accessKeyId, secret, amzDate,
                          region, service: string): string =
  ## `amzDate` is `YYYYMMDDTHHMMSSZ` (UTC); its first 8 characters are the
  ## scope date.
  let date = amzDate[0 ..< 8]
  let key = signingKey(secret, date, region, service)
  let signature = hmacSha256Hex(key, stringToSign(req, amzDate, region, service))
  "AWS4-HMAC-SHA256 Credential=" & accessKeyId & "/" &
    credentialScope(date, region, service) &
    ", SignedHeaders=" & signedHeaders(req) & ", Signature=" & signature
