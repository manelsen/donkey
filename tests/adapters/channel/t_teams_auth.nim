## Microsoft Teams (Bot Framework) inbound authentication, PRD-roadmap E2.1.
##
## Every POST from the Bot Connector carries a JWT signed RS256 with a key
## from login.botframework.com. The bot must check the issuer, the audience
## (its App ID), the validity window (5 minutes of skew), the signature, the
## `serviceurl` claim against the activity, and that the key endorses the
## activity's channel id (403 when it does not). Source: "Authenticate requests
## with the Bot Connector API", learn.microsoft.com, checked 25/11/2026.

import std/[json, sequtils, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/teams_auth_pure
import donkey/adapters/channel/teams_auth
import ./teams_jwt_vectors

const
  AppId = "app-123"
  ServiceUrl = "https://smba.trafficmanager.net/amer/"

proc keys(endorsements = @["msteams"]): seq[BotJwk] =
  let parsed = parseJwks("""{"keys":[{"kty":"RSA","use":"sig","kid":"k1","n":"""" &
    vecN & """","e":"""" & vecE & """","endorsements":""" &
    "[" & endorsements.mapIt("\"" & it & "\"").join(",") & "]}]}")
  doAssert parsed.isOk, parsed.error
  parsed.get

proc verify(token: string; serviceUrl = ServiceUrl; channelId = "msteams";
            ks = keys(); nowSec = VecNowSec): Result[void, AuthFailure] =
  verifyBotRequest("Bearer " & token, serviceUrl, channelId, AppId, ks, nowSec)

proc runTests*() =
  suite "teams auth — the pieces":

    test "the bearer token is taken from the header, nothing else":
      check bearerToken("Bearer abc.def.ghi") == "abc.def.ghi"
      check bearerToken("bearer abc") == "abc"
      check bearerToken("Basic abc") == ""
      check bearerToken("Bearer") == ""
      check bearerToken("") == ""

    test "a token splits into its header, claims and signature":
      let parts = splitJwt(vecGood)
      check parts.isOk
      check parts.get.kid == "k1" and parts.get.alg == "RS256"
      check parts.get.claims["aud"].getStr == AppId
      check parts.get.signature.len == 256
      check parts.get.signingInput == vecGood.rsplit('.', 1)[0]

    test "a malformed token is refused":
      check splitJwt("").isErr
      check splitJwt("a.b").isErr
      check splitJwt("a.b.c.d").isErr
      check splitJwt("!!.??.**").isErr
      check splitJwt("e30.e30.").isErr   ## empty signature

    test "the keys document gives each key with its endorsements":
      let ks = keys(@["msteams", "skype"])
      check ks.len == 1
      check ks[0].kid == "k1"
      check ks[0].n.len == 256 and ks[0].e == "\x01\x00\x01"
      check ks[0].endorses("msteams")
      check not ks[0].endorses("webchat")

    test "keys that are not RSA signing keys are left out":
      let parsed = parseJwks("""{"keys":[{"kty":"EC","kid":"x","x":"a","y":"b"},
        {"kty":"RSA","kid":"k1","n":"""" & vecN & """","e":"AQAB"}]}""")
      check parsed.isOk and parsed.get.len == 1
      check parseJwks("not json").isErr
      check parseJwks("""{"nokeys":[]}""").isErr

    test "the keys address comes from the OpenID document":
      check jwksUriOf("""{"issuer":"https://api.botframework.com",
        "jwks_uri":"https://login.botframework.com/v1/.well-known/keys"}""").get ==
        "https://login.botframework.com/v1/.well-known/keys"
      check jwksUriOf("""{"jwks_uri":"http://plain.example/keys"}""").isErr
      check jwksUriOf("{}").isErr

  suite "teams auth — a request":

    test "a token from the connector for this bot passes":
      check verify(vecGood).isOk

    test "the skew is five minutes, no more":
      check verify(vecGood, nowSec = VecNowSec - 60 - 300).isOk
      check verify(vecGood, nowSec = VecNowSec - 60 - 301).isErr
      check verify(vecGood, nowSec = VecNowSec + 3600 + 300).isOk
      check verify(vecGood, nowSec = VecNowSec + 3600 + 301).isErr

    test "no token, a broken one or another scheme is a 401":
      check verifyBotRequest("", ServiceUrl, "msteams", AppId, keys(), VecNowSec).error.status == 401
      check verifyBotRequest("Basic x", ServiceUrl, "msteams", AppId, keys(), VecNowSec).error.status == 401
      check verify("abc").error.status == 401

    test "a token for another bot is a 401":
      check verify(vecOtherAud).error.status == 401

    test "a token from another issuer is a 401":
      check verify(vecOtherIss).error.status == 401

    test "an expired token is a 401":
      check verify(vecExpired).error.status == 401

    test "a token for another service url is a 401":
      check verify(vecOtherService).error.status == 401
      check verify(vecGood, serviceUrl = "https://evil.example/").error.status == 401

    test "a token signed with another key is a 401":
      let r = verify(vecForged)
      check r.isErr and r.error.status == 401
      check "signature" in r.error.reason

    test "a key nobody published asks for the keys again":
      let r = verify(vecUnknownKid)
      check r.isErr and r.error.status == 401 and r.error.unknownKey
      check not verify(vecOtherAud).error.unknownKey

    test "a key that does not endorse the channel is a 403":
      check verify(vecGood, ks = keys(@["skype"])).error.status == 403
      check verify(vecGood, channelId = "webchat").error.status == 403

    test "only RS256 is accepted":
      let header = "eyJhbGciOiJub25lIiwia2lkIjoiazEifQ"   ## {"alg":"none","kid":"k1"}
      let parts = vecGood.split('.')
      check verify(header & "." & parts[1] & "." & parts[2]).error.status == 401

    test "a signature cut short or padded is refused":
      let parts = vecGood.split('.')
      check verify(parts[0] & "." & parts[1] & "." & parts[2][0 .. ^5]).isErr
      check verify(parts[0] & "." & parts[1] & "." & parts[2] & "AAAA").isErr

when isMainModule:
  runTests()
