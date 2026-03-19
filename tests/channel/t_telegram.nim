## TelegramAdapter unit tests.
## HTTP calls are not made; tests cover IdentityResolver and pure logic.

import std/[os, unittest]
import donkey/adapters/channel/telegram
import donkey/adapters/identity/identity_resolver
import donkey/core/types

suite "IdentityResolver":

  test "creates new UUID for unknown telegram user":
    let path = getTempDir() / "donkey_test_identities.tsv"
    removeFile(path)
    defer: removeFile(path)

    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckTelegram, $12345678)
    check $uid != ""
    check ($uid).len > 0

  test "same telegram id returns same UserId":
    let path = getTempDir() / "donkey_test_identities2.tsv"
    removeFile(path)
    defer: removeFile(path)

    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckTelegram, $99)
    let u2 = r.resolve(ckTelegram, $99)
    check u1 == u2

  test "different telegram ids get different UserIds":
    let path = getTempDir() / "donkey_test_identities3.tsv"
    removeFile(path)
    defer: removeFile(path)

    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckTelegram, $1)
    let u2 = r.resolve(ckTelegram, $2)
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_identities4.tsv"
    removeFile(path)
    defer: removeFile(path)

    let uid1 = newIdentityResolver(path).resolve(ckTelegram, $555)
    let uid2 = newIdentityResolver(path).resolve(ckTelegram, $555)
    check uid1 == uid2

  test "generated id looks like a UUID":
    let path = getTempDir() / "donkey_test_identities5.tsv"
    removeFile(path)
    defer: removeFile(path)

    let uid = $newIdentityResolver(path).resolve(ckTelegram, $777)
    # UUID v4 format: 8-4-4-4-12 hex chars with dashes
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

suite "TelegramAdapter construction":

  test "token is stored":
    let a = newTelegramAdapter("MY_TOKEN", "/tmp/ids.tsv",
                               apiBase = "https://mock.local")
    check a.token == "MY_TOKEN"

  test "initial offset is zero":
    let a = newTelegramAdapter("tok", "/tmp/ids2.tsv")
    check a.offset == 0
