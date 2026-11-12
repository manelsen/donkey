## SecretStore contract tests — nullclaw pattern.
## runContractTests/1 is called against every implementation.
## Add new impls here; tests apply automatically.

import std/[os, strutils, unittest]
import results
import donkey/adapters/secrets/file_key
import donkey/ports/secrets

# ── contract ──────────────────────────────────────────────────────────────────

proc verifySecretStore(s: SecretStore) = discard

proc runContractTests(store: FileKeyStore) =
  verifySecretStore(store)
  suite "SecretStore contract [" & store.label & "]":

    test "isEncrypted: enc2: prefix → true":
      check store.isEncrypted("enc2:deadbeef")

    test "isEncrypted: plaintext → false":
      check not store.isEncrypted("plaintext-value")
      check not store.isEncrypted("")

    test "roundtrip: encrypt then decrypt returns original":
      let plain = "sk-12345-super-secret"
      let ct    = store.encrypt(plain).get()
      let rt    = store.decrypt(ct).get()
      check rt == plain

    test "encrypt produces enc2: prefix when enabled":
      if store.enabled:
        let ct = store.encrypt("anything").get()
        check ct.startsWith("enc2:")

    test "encrypt is non-deterministic (nonce randomised)":
      if store.enabled:
        let a = store.encrypt("same").get()
        let b = store.encrypt("same").get()
        check a != b   # different nonces → different ciphertext

    test "decrypt returns plaintext value unchanged":
      check store.decrypt("no-prefix-here").get() == "no-prefix-here"

    test "decrypt rejects tampered ciphertext":
      if store.enabled:
        let ct     = store.encrypt("sensitive").get()
        let tamper = ct[0..^3] & "XX"   # corrupt last 2 bytes
        check store.decrypt(tamper).isErr

    test "empty string roundtrips without crash":
      check store.decrypt(store.encrypt("").get()).get() == ""

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
