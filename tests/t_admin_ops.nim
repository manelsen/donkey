## The administration operations the TUI and `ctl` share (PRD-roadmap E6):
## each returns what happened, or why not, and prints nothing, so the TUI
## shows it in place and `ctl` echoes it.

import std/[os, strutils, unittest]
import donkey/admin_ops
import donkey/adapters/memory/dm_allowlist
import donkey/adapters/memory/md_file
import donkey/adapters/state/pairing_store
import donkey/config/types
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message

proc home(tag: string): DonkeyConfig =
  let dir = getTempDir() / ("donkey_admin_ops_" & tag)
  removeDir(dir)
  createDir(dir / "paddocks")
  createDir(dir / "state")
  result = defaultConfig(dir)
  result.paddocks = dir / "paddocks"

proc runTests*() =
  suite "admin operations":

    test "revoking and restoring a person changes the allowlist and their profile":
      let cfg = home("access")
      let memory = MdFileAdapter(paddocksDir: cfg.paddocks)
      createDir(cfg.paddocks / "u-1")
      writeFile(cfg.paddocks / "u-1" / "USER.md", "# User\n**Access:** active\n")
      let revoked = setUserAccess(memory, "u-1", revoked = true)
      check revoked.isOk and "Revoked" in revoked.get
      check not dmAllowlistOf(cfg.paddocks).isAllowed(UserId("u-1")).get
      check memory.listUsers()[0].access == "revoked"
      check setUserAccess(memory, "u-1", revoked = false).get.startsWith("Restored")
      check dmAllowlistOf(cfg.paddocks).isAllowed(UserId("u-1")).get

    test "a pairing is approved into the allowlist, or rejected; an unknown code is an error":
      let cfg = home("pairing")
      let memory = MdFileAdapter(paddocksDir: cfg.paddocks)
      let store = newPairingStore(cfg.home / "state" / "pairings.json")
      check store.requestPairing(ckTelegram, "42").isOk
      check store.requestPairing(ckDiscord, "77").isOk
      let codes = store.load().get
      let approved = approvePairing(cfg, memory, store, codes[0].code)
      check approved.isOk and "Paired" in approved.get
      check store.load().get.len == 1
      check rejectPairing(store, codes[1].code).isOk
      check store.load().get.len == 0
      check approvePairing(cfg, memory, store, "000000").isErr
      check rejectPairing(store, "000000").isErr

when isMainModule:
  runTests()
