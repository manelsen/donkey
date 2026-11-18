## US-000 — LINE survives a PairingStore save/load round-trip.

import std/[os, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/state/pairing_store

const PairingLineTmp = "/tmp/donkey_pairing_line_tests"

suite "PairingStore — LINE":

  test "line pairing round-trips through save and load":
    removeDir(PairingLineTmp)
    let store = newPairingStore(PairingLineTmp / "pairings.json")
    let created = store.requestPairing(ckLine, "U4af4980629", now = 1000.0)
    check created.isOk
    check created.get().channel == ckLine

    let loaded = store.load(now = 1001.0).get()
    check loaded.len == 1
    check loaded[0].channel == ckLine
    check loaded[0].rawId == "U4af4980629"
