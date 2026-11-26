## RS256 signing (second round, front 1, for Google Chat's service account):
## a PKCS#8 PEM key signs a JWT signing input with PKCS#1 v1.5 and SHA-256.
## The key in tests/fixtures/google_chat is a throwaway generated for this
## test; the expected signature was made with `openssl dgst -sha256 -sign`.

import std/[base64, os, strutils, unittest]
import donkey/core/pipeops
import donkey/adapters/crypto/rs256
import donkey/adapters/channel/teams_auth

const
  KeyPath = currentSourcePath().parentDir.parentDir.parentDir / "fixtures" /
            "google_chat" / "test_only_rsa.pem"
  ModulusB64u = "2FVrAvWd8z_wl9H2OOtOTcmCLAWWVL9XaNp_VbZ4OkkNq3jBPFCCyxG6WDmdMzlZ2QWqbrJBLi0wTtNLVCrTCuT0YGmkhH3naypirgnqQF8COpcMIBS-aNfVjsNzlu67FYQq_3X2F4m6FtMUylPuYKICNsLpozgx6yWtOQ8h-hWwJ89LEK7nCpGWoz-Um_FPaNhMHB38UZRI0CEUwzZI0FGQ9yX84xsWGgX0vIu-bCBQVyUUtGkWgY8Qqaf-ePEESPyg9LspRNm70N6noBab8goUlIsAZ_uqBP7CbEHUkeBtMZGk-d7Lg-SJm235VqzoFzlrmu03iFNSVa5q4byT_w"
  ExpectedB64u = "sEcUDWNvom8stcDYVkWaY_reO_691ogNfvYoF7suW3KLXFOiqegWhHHzk-XJI2CPzPc6x3je4VsMx5K3pFTlWC19uhe0XbHWHogTnCprTzXBv0EdV2wBbTHu2l1Pgb-BVWaquhlxR3D4Dt0PRzP3-4kXKTBQ7XrcwWlA6WTLNbdGg7DvSh4v2v039VSRKOfitvNJyyZnPvC6zrJUSaf_KuY6hz5wXRGm1DrZfMXi54RsY6NLNrO2okHahzjUz-t7g2Fpujo_qzY_8xsAMstA0v5bIs5YynvU8GAcK7IxqvBxpGw9WrZkHYZtDCXGDn8yB_6GNvD5-WQjcqxTMBivwQ"

proc b64u(s: string): string =
  var t = s.replace('-', '+').replace('_', '/')
  while t.len mod 4 != 0: t.add '='
  decode(t)

proc runTests*() =
  suite "rs256 signing":

    test "the signature is the one openssl makes for the same key and input":
      let sig = rs256Sign(readFile(KeyPath), "header.payload").get
      check sig.len == 256
      check sig == b64u(ExpectedB64u)

    test "what it signs passes the RS256 check the webhooks use":
      let sig = rs256Sign(readFile(KeyPath), "a.b").get
      check rs256Valid("a.b", sig, b64u(ModulusB64u), "\x01\x00\x01")
      check not rs256Valid("a.c", sig, b64u(ModulusB64u), "\x01\x00\x01")

    test "a broken or missing key is an error, not a crash":
      check rs256Sign("", "x").isErr
      check rs256Sign("-----BEGIN PRIVATE KEY-----\nbm90IGEga2V5\n-----END PRIVATE KEY-----\n", "x").isErr
      check rs256Sign("not pem at all", "x").isErr

    test "the private key may come with escaped newlines, as in a JSON file":
      let escaped = readFile(KeyPath).replace("\n", "\\n")
      check rs256Sign(escaped, "header.payload").get == b64u(ExpectedB64u)

when isMainModule:
  runTests()
