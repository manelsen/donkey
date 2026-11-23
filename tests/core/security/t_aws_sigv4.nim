## AWS Signature Version 4, checked against AWS's documented example: the IAM
## `ListUsers` request of 2015-08-30 signed with the documentation's example
## key (AWS General Reference, "Signature Version 4 signing process" /
## "Create a signed AWS API request"). The canonical request hash, the
## signing key and the signature below are the values that page publishes.

import std/[strutils, unittest]
import donkey/core/security/aws_sigv4

const
  ExampleSecret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
  ExampleAccess = "AKIDEXAMPLE"
  EmptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

proc exampleRequest(): SigV4Request =
  SigV4Request(
    httpMethod: "GET",
    canonicalUri: "/",
    canonicalQuery: "Action=ListUsers&Version=2010-05-08",
    headers: @[
      ("Content-Type", "application/x-www-form-urlencoded; charset=utf-8"),
      ("Host", "iam.amazonaws.com"),
      ("X-Amz-Date", "20150830T123600Z")],
    payload: "",
  )

proc runTests*() =
  suite "aws_sigv4 — AWS's documented example":
    test "the payload hash of an empty body":
      check sha256Hex("") == EmptyHash

    test "the canonical request and its hash":
      let canonical = canonicalRequest(exampleRequest())
      check canonical == "GET\n/\nAction=ListUsers&Version=2010-05-08\n" &
        "content-type:application/x-www-form-urlencoded; charset=utf-8\n" &
        "host:iam.amazonaws.com\nx-amz-date:20150830T123600Z\n\n" &
        "content-type;host;x-amz-date\n" & EmptyHash
      check sha256Hex(canonical) ==
        "f536975d06c0309214f805bb90ccff089219ecd68b2577efef23edd43b7e1a59"

    test "the signing key":
      check signingKeyHex(ExampleSecret, "20150830", "us-east-1", "iam") ==
        "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9"

    test "the signature and the Authorization header":
      let auth = authorizationHeader(exampleRequest(), ExampleAccess, ExampleSecret,
                                     "20150830T123600Z", "us-east-1", "iam")
      check auth == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, " &
        "SignedHeaders=content-type;host;x-amz-date, " &
        "Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7"

  suite "aws_sigv4 — path encoding":
    test "a path segment is encoded once more for the canonical URI":
      ## Bedrock model ids carry ':' — the request path has %3A, and SigV4 for
      ## every service but S3 encodes each segment again (%253A).
      check canonicalUriOf("/model/anthropic.claude-v2%3A1/converse") ==
        "/model/anthropic.claude-v2%253A1/converse"
      check uriEncode("a b:c/~_-.") == "a%20b%3Ac%2F~_-."

    test "header values are trimmed and inner spaces collapsed":
      let req = SigV4Request(httpMethod: "POST", canonicalUri: "/",
        headers: @[("X-Pad", "  a   b  "), ("Host", "h")], payload: "x")
      check "x-pad:a b\n" in canonicalRequest(req)

when isMainModule:
  runTests()
