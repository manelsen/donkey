## rs256 — signing a JWT with an RSA private key (PKCS#1 v1.5, SHA-256),
## through BearSSL, already linked for TLS: no new dependency.
##
## The key is a PEM, PKCS#8 (`-----BEGIN PRIVATE KEY-----`, the `private_key`
## of a Google service account) or PKCS#1 (`BEGIN RSA PRIVATE KEY`). A key
## read from a JSON string may keep its newlines escaped (`\n`); both forms
## are accepted.

import std/[base64, strutils]
import bearssl/[hash, rsa, x509]
import ../../core/pipeops

proc pemBody(pem: string): Result[string, string] =
  ## The DER bytes between the BEGIN and END lines.
  let text = pem.replace("\\n", "\n").replace("\r", "")
  let begin = text.find("-----BEGIN ")
  if begin < 0:
    return err("not a PEM key")
  let headerEnd = text.find("-----\n", begin + 11)
  let footer = text.find("-----END ", max(begin, headerEnd))
  if headerEnd < 0 or footer < 0:
    return err("not a PEM key")
  var b64 = ""
  for c in text[headerEnd + 6 ..< footer]:
    if c notin Whitespace: b64.add c
  try:
    let der = decode(b64)
    if der.len == 0: return err("empty PEM key")
    ok(der)
  except CatchableError:
    err("the PEM key is not base64")

proc rs256Sign*(pem, signingInput: string): Result[string, string] =
  ## The raw signature (the modulus length) of `signingInput`.
  let der = ? pemBody(pem)
  var dec: SkeyDecoderContext
  skeyDecoderInit(dec)
  skeyDecoderPush(dec, unsafeAddr der[0], csize_t(der.len))
  if skeyDecoderLastError(dec) != 0:
    return err("the private key cannot be read")
  if skeyDecoderKeyType(dec) != KEYTYPE_RSA:
    return err("the private key is not RSA")
  let sk = skeyDecoderGetRsa(dec)
  if sk == nil or sk.nBitlen < 2048:
    return err("the RSA key is missing or shorter than 2048 bits")
  var digest: array[sha256SIZE, byte]
  var ctx: Sha256Context
  sha256Init(ctx)
  if signingInput.len > 0:
    sha256Update(ctx, unsafeAddr signingInput[0], csize_t(signingInput.len))
  sha256Out(ctx, addr digest[0])
  var sig = newString(int((sk.nBitlen + 7) div 8))
  let oid = HASH_OID_SHA256
  let signer = rsaPkcs1SignGetDefault()
  if signer(cast[ptr byte](unsafeAddr oid[0]), addr digest[0], csize_t(sha256SIZE),
            sk, cast[ptr byte](addr sig[0])) != 1:
    return err("RSA signing failed")
  ok(sig)
