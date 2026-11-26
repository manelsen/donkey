## Shared by the Google Chat tests: the throwaway key in
## tests/fixtures/google_chat, as a private PEM and as a JWKS, and a way to
## mint tokens "from Google" with it.

import std/[base64, json, os, strutils]
import donkey/core/pipeops
import donkey/adapters/crypto/rs256

const
  KeyPath* = currentSourcePath().parentDir.parentDir.parentDir / "fixtures" /
             "google_chat" / "test_only_rsa.pem"
  ModulusB64u* = "2FVrAvWd8z_wl9H2OOtOTcmCLAWWVL9XaNp_VbZ4OkkNq3jBPFCCyxG6WDmdMzlZ2QWqbrJBLi0wTtNLVCrTCuT0YGmkhH3naypirgnqQF8COpcMIBS-aNfVjsNzlu67FYQq_3X2F4m6FtMUylPuYKICNsLpozgx6yWtOQ8h-hWwJ89LEK7nCpGWoz-Um_FPaNhMHB38UZRI0CEUwzZI0FGQ9yX84xsWGgX0vIu-bCBQVyUUtGkWgY8Qqaf-ePEESPyg9LspRNm70N6noBab8goUlIsAZ_uqBP7CbEHUkeBtMZGk-d7Lg-SJm235VqzoFzlrmu03iFNSVa5q4byT_w"
  TestJwks* = """{"keys":[{"kty":"RSA","alg":"RS256","use":"sig","kid":"k1","n":"""" &
              ModulusB64u & """","e":"AQAB"}]}"""

proc b64url(s: string): string =
  encode(s).replace('+', '-').replace('/', '_').strip(leading = false, chars = {'='})

proc mintToken*(claims: JsonNode; kid = "k1"): string =
  let input = b64url($(%* {"alg": "RS256", "kid": kid, "typ": "JWT"})) & "." & b64url($claims)
  input & "." & b64url(rs256Sign(readFile(KeyPath), input).get)

proc serviceAccountJson*(): string =
  $(%* {"type": "service_account", "client_email": "donkey@proj.iam.gserviceaccount.com",
        "private_key": readFile(KeyPath), "token_uri": "https://oauth2.googleapis.com/token"})
