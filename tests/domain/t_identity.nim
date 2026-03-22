## Cross-channel identity domain unit tests.
##
## Covers all three pipeops operators:
##   |>   — unary pure transforms (validateRawId, isValidLinkCode)
##   |>-> — last-arg pipe (channelKey with rawId as last arg)
##   >>=  — Result chaining (parseChannelKind, validateRawId, validateLinkCode)

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/identity

# ── channelKey ────────────────────────────────────────────────────────────────

suite "identity — channelKey":

  test "telegram key format":
    check channelKey(ckTelegram, "12345") == "telegram:12345"

  test "discord key format":
    check channelKey(ckDiscord, "678901234") == "discord:678901234"

  test "wecom key format":
    check channelKey(ckWeCom, "uid99") == "wecom:uid99"

  test "qq key format":
    check channelKey(ckQQ, "100200300") == "qq:100200300"

suite "identity — channelKey pipeops |>->":

  test "|>-> pipes rawId as last arg":
    let r = "12345" |>-> channelKey(ckTelegram)
    check r == "telegram:12345"

  test "|>-> discord last-arg":
    let r = "678901234" |>-> channelKey(ckDiscord)
    check r == "discord:678901234"

  test "|>-> then string contains check":
    let r = "abc" |>-> channelKey(ckFeishu)
    check "feishu:" in r
    check "abc" in r

# ── parseChannelKind ──────────────────────────────────────────────────────────

suite "identity — parseChannelKind":

  test "parses telegram":
    let r = parseChannelKind("telegram")
    check r.isOk
    check r.get() == ckTelegram

  test "parses discord":
    let r = parseChannelKind("discord")
    check r.isOk
    check r.get() == ckDiscord

  test "parses wecom":
    let r = parseChannelKind("wecom")
    check r.isOk
    check r.get() == ckWeCom

  test "parses wechat":
    let r = parseChannelKind("wechat")
    check r.isOk
    check r.get() == ckWeChat

  test "parses qq":
    let r = parseChannelKind("qq")
    check r.isOk
    check r.get() == ckQQ

  test "parses feishu":
    let r = parseChannelKind("feishu")
    check r.isOk
    check r.get() == ckFeishu

  test "unknown channel returns Err":
    let r = parseChannelKind("slack")
    check r.isErr
    check "unknown" in r.error

  test "empty string returns Err":
    let r = parseChannelKind("")
    check r.isErr

# ── parseChannelKey ───────────────────────────────────────────────────────────

suite "identity — parseChannelKey":

  test "parses telegram key":
    let r = parseChannelKey("telegram:12345")
    check r.isOk
    let (kind, rawId) = r.get()
    check kind  == ckTelegram
    check rawId == "12345"

  test "parses discord key":
    let r = parseChannelKey("discord:678901234")
    check r.isOk
    let (kind, rawId) = r.get()
    check kind  == ckDiscord
    check rawId == "678901234"

  test "missing colon returns Err":
    let r = parseChannelKey("telegram12345")
    check r.isErr
    check "missing" in r.error

  test "empty rawId returns Err":
    let r = parseChannelKey("telegram:")
    check r.isErr
    check "empty" in r.error

  test "unknown channel returns Err":
    let r = parseChannelKey("slack:12345")
    check r.isErr

  test "empty key returns Err":
    let r = parseChannelKey("")
    check r.isErr

# ── validateRawId ─────────────────────────────────────────────────────────────

suite "identity — validateRawId":

  test "non-empty rawId returns Ok":
    let r = validateRawId("12345")
    check r.isOk
    check r.get() == "12345"

  test "empty rawId returns Err":
    let r = validateRawId("")
    check r.isErr
    check "empty" in r.error

  test "whitespace-only rawId is accepted (not empty)":
    ## The domain only guards against zero-length — callers trim if needed
    let r = validateRawId("  ")
    check r.isOk

suite "identity — validateRawId pipeops |>":

  test "|> validateRawId unary pipe — valid input":
    let r = "abc123" |> validateRawId
    check r.isOk
    check r.get() == "abc123"

  test "|> validateRawId unary pipe — empty input":
    let r = "" |> validateRawId
    check r.isErr

suite "identity — validateRawId pipeops >>=":

  test ">>= passes Ok value through validateRawId":
    let r = Result[string, string].ok("99") >>= validateRawId
    check r.isOk
    check r.get() == "99"

  test ">>= propagates Err without calling validateRawId":
    let r = Result[string, string].err("upstream error") >>= validateRawId
    check r.isErr
    check r.error == "upstream error"

  test ">>= fails when validateRawId rejects empty":
    let r = Result[string, string].ok("") >>= validateRawId
    check r.isErr

# ── isValidLinkCode ───────────────────────────────────────────────────────────

suite "identity — isValidLinkCode":

  test "valid 6-char code is accepted":
    check isValidLinkCode("ABCDE2") == true

  test "all-uppercase valid chars":
    check isValidLinkCode("MNPQRS") == true

  test "digits from alphabet are accepted":
    check isValidLinkCode("234567") == true

  test "too short is rejected":
    check isValidLinkCode("ABCD") == false

  test "too long is rejected":
    check isValidLinkCode("ABCDE2345") == false

  test "lowercase is rejected":
    check isValidLinkCode("abcde2") == false

  test "ambiguous 'O' is rejected":
    check isValidLinkCode("ABCDO2") == false

  test "ambiguous 'I' is rejected":
    check isValidLinkCode("ABCDI2") == false

  test "ambiguous '0' is rejected":
    check isValidLinkCode("0ABCD2") == false

  test "ambiguous '1' is rejected":
    check isValidLinkCode("1ABCD2") == false

  test "empty string is rejected":
    check isValidLinkCode("") == false

suite "identity — isValidLinkCode pipeops |>":

  test "|> isValidLinkCode — valid code":
    let valid = "ABCDE2" |> isValidLinkCode
    check valid == true

  test "|> isValidLinkCode — invalid code":
    let valid = "abc" |> isValidLinkCode
    check valid == false

# ── validateLinkCode >>= ─────────────────────────────────────────────────────

suite "identity — validateLinkCode pipeops >>=":

  test ">>= passes valid code":
    let r = Result[string, string].ok("ABCDE2") >>= validateLinkCode
    check r.isOk
    check r.get() == "ABCDE2"

  test ">>= rejects invalid code":
    let r = Result[string, string].ok("bad") >>= validateLinkCode
    check r.isErr
    check "invalid" in r.error

  test ">>= propagates upstream Err":
    let r = Result[string, string].err("no code") >>= validateLinkCode
    check r.isErr
    check r.error == "no code"

  test ">>= chain: validateRawId then validateLinkCode":
    ## Demonstrates two-step Result chain
    let r = (Result[string, string].ok("ABCDE2") >>= validateRawId) >>= validateLinkCode
    check r.isOk
    check r.get() == "ABCDE2"
