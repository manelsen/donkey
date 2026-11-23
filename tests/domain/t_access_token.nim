import std/unittest
import donkey/domain/channels/access_token_pure

proc runTests*() =
  suite "access token":
    test "a token never fetched is not fresh":
      check not AccessToken().isFresh(0)

    test "a token is fresh until the skew before its expiry":
      let t = issuedToken("abc", expiresInSec = 7200, nowSec = 1000)
      check t.expiresAtSec == 8200
      check t.isFresh(1000)
      check t.isFresh(8200 - AccessTokenSkewSec - 1)
      check not t.isFresh(8200 - AccessTokenSkewSec)
      check not t.isFresh(9000)

    test "an empty value is never fresh":
      check not issuedToken("", 7200, 0).isFresh(0)

when isMainModule:
  runTests()
