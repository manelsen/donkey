## SecretStore contract tests — nullclaw pattern.
## runContractTests/1 is called against every implementation.
## Add new impls here; tests apply automatically.

import std/[os, strutils, unittest]
import donkey/adapters/secrets/file_key

# ── contract ──────────────────────────────────────────────────────────────────

proc runContractTests(store: FileKeyStore) =
  suite "SecretStore contract [" & store.label & "]":

    test "isEncrypted: enc2: prefix → true":
      check store.isEncrypted("enc2:deadbeef")

    test "isEncrypted: plaintext → false":
      check not store.isEncrypted("plaintext-value")
      check not store.isEncrypted("")

    test "roundtrip: encrypt then decrypt returns original":
      let plain = "sk-12345-super-secret"
      let ct    = store.encrypt(plain)
      let rt    = store.decrypt(ct)
      check rt == plain

    test "encrypt produces enc2: prefix when enabled":
      if store.enabled:
        let ct = store.encrypt("anything")
        check ct.startsWith("enc2:")

    test "encrypt is non-deterministic (nonce randomised)":
      if store.enabled:
        let a = store.encrypt("same")
        let b = store.encrypt("same")
        check a != b   # different nonces → different ciphertext

    test "decrypt returns plaintext value unchanged":
      check store.decrypt("no-prefix-here") == "no-prefix-here"

    test "decrypt rejects tampered ciphertext":
      if store.enabled:
        let ct     = store.encrypt("sensitive")
        let tamper = ct[0..^3] & "XX"   # corrupt last 2 bytes
        expect DecryptionError:
          discard store.decrypt(tamper)

    test "empty string roundtrips without crash":
      check store.decrypt(store.encrypt("")) == ""

# ── implementations under test ────────────────────────────────────────────────

block fileKey:
  let keyPath = getTempDir() / "donkey_test_secret_key"
  removeFile(keyPath)
  defer: removeFile(keyPath)
  let store = newFileKeyStore(keyPath)
  runContractTests(store)

block disabledMode:
  let store = newFileKeyStore("/dev/null", enable = false)
  runContractTests(store)
