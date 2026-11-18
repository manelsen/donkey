## webhook_auth.nim — the single definition site for webhook MAC primitives.
##
## Pure helpers shared by every webhook channel. `safeEquals` is the only
## comparison used for secrets/MACs and `hmacSha256Hex`/`hmacSha256Base64` are
## the only HMAC-SHA256 constructors in the tree (PRD Canais, US-003/§9). Domain
## policy modules must not define or import their own copies.

import std/[base64, strutils]
import nimcrypto/[hmac, sha2]

func safeEquals*(a, b: string): bool =
  ## Constant-time-ish comparison for secrets and MACs.
  if a.len != b.len:
    return false
  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (ord(a[i]) xor ord(b[i]))
  diff == 0

func hmacSha256Hex*(secret, body: string): string =
  ($sha256.hmac(secret, body)).toLowerAscii()

func hmacSha256Base64*(secret, body: string): string =
  let digest = sha256.hmac(secret, body)
  var raw = newString(digest.data.len)
  for i, b in digest.data:
    raw[i] = char(b)
  base64.encode(raw)
