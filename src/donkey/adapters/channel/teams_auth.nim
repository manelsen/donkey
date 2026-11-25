## teams_auth — checking a Bot Connector request (Microsoft Teams, E2.1).
##
## The claims, keys and endorsement rules are pure
## (domain/channels/teams_auth_pure); this module adds the RS256 signature
## check through BearSSL, already linked for TLS, so no new dependency.

import bearssl/[hash, rsa]
import ../../core/pipeops
import ../../domain/channels/teams_auth_pure

export teams_auth_pure

proc sha256Of(data: string): array[sha256SIZE, byte] =
  var ctx: Sha256Context
  sha256Init(ctx)
  if data.len > 0:
    sha256Update(ctx, unsafeAddr data[0], csize_t(data.len))
  sha256Out(ctx, addr result[0])

proc rs256Valid*(signingInput, signature, n, e: string): bool =
  ## PKCS#1 v1.5 with SHA-256 against the RSA public key (n, e) as raw
  ## big-endian bytes. The signature must be exactly the modulus length.
  if n.len == 0 or e.len == 0 or signature.len != n.len:
    return false
  var key = RsaPublicKey(
    n: cast[ptr byte](unsafeAddr n[0]), nlen: csize_t(n.len),
    e: cast[ptr byte](unsafeAddr e[0]), elen: csize_t(e.len))
  var recovered: array[sha256SIZE, byte]
  let verifier = rsaPkcs1VrfyGetDefault()
  let oid = HASH_OID_SHA256
  let ok = verifier(cast[ptr byte](unsafeAddr signature[0]), csize_t(signature.len),
                    cast[ptr byte](unsafeAddr oid[0]), csize_t(sha256SIZE),
                    addr key, addr recovered[0])
  ok == 1 and recovered == sha256Of(signingInput)

proc verifyBotRequest*(authHeader, serviceUrl, channelId, appId: string;
                       keys: openArray[BotJwk];
                       nowSec: int64): Result[void, AuthFailure] =
  ## 401 when the token is missing, malformed, not RS256, not signed by a
  ## published key or its claims do not fit this bot and activity; 403 when
  ## the key does not endorse the activity's channel. `unknownKey` tells the
  ## caller to fetch the keys again before giving up.
  template deny(why: string; unknown = false): untyped =
    return err(AuthFailure(status: 401, reason: why, unknownKey: unknown))
  let token = bearerToken(authHeader)
  if token.len == 0:
    deny("no bearer token")
  let parts = splitJwt(token).valueOr:
    deny(error)
  if parts.alg != "RS256":
    deny("algorithm is not RS256")
  var found = -1
  for i, key in keys:
    if key.kid == parts.kid:
      found = i
      break
  if found < 0:
    deny("signed with an unknown key", unknown = true)
  let key = keys[found]
  if not rs256Valid(parts.signingInput, parts.signature, key.n, key.e):
    deny("bad signature")
  checkClaims(parts.claims, appId, serviceUrl, nowSec).isOkOr:
    deny(error)
  if not key.endorses(channelId):
    return err(AuthFailure(status: 403,
                           reason: "key does not endorse channel " & channelId))
  ok()
