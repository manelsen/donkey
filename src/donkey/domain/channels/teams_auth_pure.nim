## teams_auth_pure — the pure half of authenticating a Bot Connector request
## (Microsoft Teams, PRD-roadmap E2.1).
##
## Source: "Authenticate requests with the Bot Connector API",
## learn.microsoft.com (checked 25/11/2026). The connector signs each POST
## with an RS256 JWT; the keys are at the `jwks_uri` of a static OpenID
## document. A token is valid when its issuer is the Bot Framework, its
## audience the bot's App ID, it is inside its validity window (5 minutes of
## skew), its `serviceurl` claim matches the activity's, its signature checks
## against a published key, and that key endorses the activity's channel id.
## The signature check itself is in adapters/channel/teams_auth (BearSSL).
##
## `proc` where JSON is parsed (ADR-007 allows it).

import std/[base64, json, strutils]
import ../../core/pipeops

const
  BotFrameworkIssuer* = "https://api.botframework.com"
  BotFrameworkOpenIdUrl* =
    "https://login.botframework.com/v1/.well-known/openidconfiguration"
  ClockSkewSec* = 300'i64

type
  BotJwk* = object
    kid*:          string
    n*:            string   ## modulus, raw big-endian bytes
    e*:            string   ## exponent, raw big-endian bytes
    endorsements*: seq[string]

  JwtParts* = object
    kid*, alg*:    string
    claims*:       JsonNode
    signingInput*: string   ## `header.claims`, as signed
    signature*:    string   ## raw bytes

  AuthFailure* = object
    status*:     int        ## 401 or 403
    reason*:     string
    unknownKey*: bool       ## the token names a key not in hand: fetch again

func bearerToken*(header: string): string =
  ## The token of an `Authorization: Bearer …` header; "" otherwise.
  let h = header.strip
  if h.len <= "bearer ".len or not h.toLowerAscii.startsWith("bearer "):
    return ""
  h["bearer ".len .. ^1].strip

proc b64url(s: string): Result[string, string] =
  if s.len == 0:
    return err("empty segment")
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}:
      return err("not base64url")
  try: ok(decode(s))
  except CatchableError as e: err(e.msg)

proc splitJwt*(token: string): Result[JwtParts, string] =
  let parts = token.split('.')
  if parts.len != 3:
    return err("not a JWT")
  let header = ? b64url(parts[0])
  let claims = ? b64url(parts[1])
  let signature = ? b64url(parts[2])
  var h, c: JsonNode
  try:
    h = parseJson(header)
    c = parseJson(claims)
  except CatchableError:
    return err("JWT is not JSON")
  if h.kind != JObject or c.kind != JObject:
    return err("JWT is not JSON objects")
  ok(JwtParts(kid: h{"kid"}.getStr, alg: h{"alg"}.getStr, claims: c,
              signingInput: parts[0] & "." & parts[1], signature: signature))

proc parseJwks*(text: string): Result[seq[BotJwk], string] =
  ## The RSA keys of a JWKS document, with their endorsements.
  let j =
    try: parseJson(text)
    except CatchableError: return err("keys document is not JSON")
  if j.kind != JObject or j{"keys"}.isNil or j["keys"].kind != JArray:
    return err("keys document has no keys")
  var keys: seq[BotJwk]
  for k in j["keys"]:
    if k.kind != JObject or k{"kty"}.getStr != "RSA" or k{"kid"}.getStr.len == 0:
      continue
    let n = b64url(k{"n"}.getStr)
    let e = b64url(k{"e"}.getStr)
    if n.isErr or e.isErr:
      continue
    var key = BotJwk(kid: k["kid"].getStr, n: n.get, e: e.get)
    if not k{"endorsements"}.isNil and k["endorsements"].kind == JArray:
      for item in k["endorsements"]:
        if item.kind == JString:
          key.endorsements.add item.getStr
    keys.add key
  ok(keys)

proc jwksUriOf*(openIdDoc: string): Result[string, string] =
  let j =
    try: parseJson(openIdDoc)
    except CatchableError: return err("OpenID document is not JSON")
  let uri = j{"jwks_uri"}.getStr
  if not uri.startsWith("https://"):
    return err("OpenID document has no https jwks_uri")
  ok(uri)

func endorses*(key: BotJwk; channelId: string): bool =
  channelId.len > 0 and channelId in key.endorsements

proc claimString(claims: JsonNode; name: string): string =
  ## Claim names are matched without case: the connector sends `serviceurl`.
  for key, value in claims.pairs:
    if cmpIgnoreCase(key, name) == 0 and value.kind == JString:
      return value.getStr
  ""

proc checkClaims*(claims: JsonNode; appId, serviceUrl: string;
                  nowSec: int64): Result[void, string] =
  if claims{"iss"}.getStr != BotFrameworkIssuer:
    return err("issuer is not the Bot Framework")
  let aud = claims{"aud"}
  if aud.isNil or aud.kind != JString or aud.getStr != appId or appId.len == 0:
    return err("token is for another bot")
  let nbf = claims{"nbf"}
  let exp = claims{"exp"}
  if exp.isNil or exp.kind != JInt:
    return err("token has no expiry")
  if nowSec > exp.getBiggestInt + ClockSkewSec:
    return err("token expired")
  if not nbf.isNil and nbf.kind == JInt and nowSec < nbf.getBiggestInt - ClockSkewSec:
    return err("token not yet valid")
  let claimed = claimString(claims, "serviceUrl")
  if claimed.len == 0 or claimed != serviceUrl:
    return err("token is for another service url")
  ok()
