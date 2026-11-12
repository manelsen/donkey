import std/[options, os, times, unittest]
import donkey/config/types
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/memory/md_file
import donkey/adapters/identity/identity_resolver
import donkey/adapters/state/pairing_store
import donkey/ctl_handler

const CtlTmp = "/tmp/donkey_ctl_pairing_tests"

suite "ctl pairing":

  test "approve mints the identity and adds it to the allowlist":
    removeDir(CtlTmp / "approve")
    let cfg = DonkeyConfig(home: CtlTmp / "approve", paddocks: CtlTmp / "approve" / "paddocks")
    let memory = MdFileAdapter(paddocksDir: cfg.paddocks)
    let store = newPairingStore(cfg.home / "state" / "pairings.json")
    let request = store.requestPairing(ckTelegram, "777", now = epochTime()).get()

    let res = ctlPairApprove(cfg, memory, store, request.code)
    check res.isOk
    check store.load().len == 0

    let resolver = newIdentityResolver(cfg.home / "identities.tsv")
    let userId = resolver.lookup(ckTelegram, "777")
    check userId.isSome
    check memory.isDmAllowed(userId.get)

  test "reject removes the request without allowlisting":
    removeDir(CtlTmp / "reject")
    let cfg = DonkeyConfig(home: CtlTmp / "reject", paddocks: CtlTmp / "reject" / "paddocks")
    let memory = MdFileAdapter(paddocksDir: cfg.paddocks)
    let store = newPairingStore(cfg.home / "state" / "pairings.json")
    let request = store.requestPairing(ckSlack, "U9", now = epochTime()).get()

    let res = ctlPairReject(store, request.code)
    check res.isOk
    check store.load().len == 0

    let resolver = newIdentityResolver(cfg.home / "identities.tsv")
    check resolver.lookup(ckSlack, "U9").isNone

  test "approve rejects an unknown code":
    removeDir(CtlTmp / "missing")
    let cfg = DonkeyConfig(home: CtlTmp / "missing", paddocks: CtlTmp / "missing" / "paddocks")
    let memory = MdFileAdapter(paddocksDir: cfg.paddocks)
    let store = newPairingStore(cfg.home / "state" / "pairings.json")
    check ctlPairApprove(cfg, memory, store, "000000").isErr
