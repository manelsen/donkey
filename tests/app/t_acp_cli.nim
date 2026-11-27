## `donkey acp`'s shell (E10.1): which daemon, and the credential per URL.

import std/[os, posix, unittest]
import donkey/core/pipeops
import donkey/config/environment
import donkey/adapters/filesystem/fs_adapter
import donkey/acp_cli

proc runTests*() =
  suite "acp cli":
    test "the URL: the argument, else DONKEY_ACP_URL, else the local gateway":
      check acpUrl(environmentOf({"DONKEY_ACP_URL": "https://d.example"}), @["https://x"]) == "https://x"
      check acpUrl(environmentOf({"DONKEY_ACP_URL": "https://d.example"}), @[]) == "https://d.example"
      check acpUrl(environmentOf({"X": "y"}), @[]) == DefaultAcpUrl

    test "one credential per URL, 0600; forgetting one keeps the others":
      let dir = getTempDir() / "donkey_acp_cli"
      removeDir(dir)
      let path = dir / "acp_credentials.json"
      let fs = newFsAdapter()
      check loadCredential(fs, path, "https://a") == ""
      check saveCredential(fs, path, "https://a", "tok-a").isOk
      check saveCredential(fs, path, "https://b", "tok-b").isOk
      check loadCredential(fs, path, "https://a") == "tok-a"
      var st: Stat
      check stat(path.cstring, st) == 0 and (st.st_mode.int and 0o777) == 0o600
      check saveCredential(fs, path, "https://a", "").isOk
      check loadCredential(fs, path, "https://a") == "" and loadCredential(fs, path, "https://b") == "tok-b"

when isMainModule:
  runTests()
