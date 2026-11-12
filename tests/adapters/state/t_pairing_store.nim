import std/[os, times, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/state/pairing_store

const PairingTmp = "/tmp/donkey_pairing_store_tests"

suite "PairingStore":

  test "request persists and loads":
    removeDir(PairingTmp / "persist")
    let store = newPairingStore(PairingTmp / "persist" / "pairings.json")
    let created = store.requestPairing(ckTelegram, "12345", now = 1000.0)
    check created.isOk
    check created.get().code.len == 6
    check created.get().channel == ckTelegram

    let loaded = store.load(now = 1001.0).get()
    check loaded.len == 1
    check loaded[0].code == created.get().code
    check loaded[0].rawId == "12345"

  test "cooldown blocks duplicate requests":
    removeDir(PairingTmp / "cooldown")
    let store = newPairingStore(PairingTmp / "cooldown" / "pairings.json")
    check store.requestPairing(ckSlack, "U1", now = 1000.0).isOk
    check store.requestPairing(ckSlack, "U1", now = 1030.0).isErr
    check store.requestPairing(ckSlack, "U1", now = 1061.0).isOk
    check store.load(now = 1061.0).get().len == 2

  test "expired requests are pruned":
    removeDir(PairingTmp / "expiry")
    let store = newPairingStore(PairingTmp / "expiry" / "pairings.json")
    discard store.requestPairing(ckMatrix, "!room:server", now = 1000.0)
    check store.load(now = 1000.0).get().len == 1
    check store.load(now = 1000.0 + PairingRequestTtlSec + 1.0).get().len == 0

  test "removeByCode removes and reports whether it existed":
    removeDir(PairingTmp / "remove")
    let store = newPairingStore(PairingTmp / "remove" / "pairings.json")
    let created = store.requestPairing(ckFeishu, "ou_1", now = epochTime()).get()
    check store.removeByCode(created.code).get()
    check not store.removeByCode(created.code).get()
    check store.load().get().len == 0

  test "corrupt state is reported instead of silently dropped":
    removeDir(PairingTmp / "corrupt")
    createDir(PairingTmp / "corrupt")
    let path = PairingTmp / "corrupt" / "pairings.json"
    writeFile(path, "not json")
    let store = newPairingStore(path)
    check store.load().isErr
