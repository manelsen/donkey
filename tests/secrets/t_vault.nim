import std/[json, os, strutils, unittest]
import donkey/core/pipeops
import donkey/adapters/secrets/vault

const VaultTmp = "/tmp/donkey_secret_vault_tests"

suite "SecretVault":

  test "set, list and remove without storing plaintext":
    removeDir(VaultTmp / "basic")
    let vault = newSecretVault(VaultTmp / "basic")

    check not vault.keyPath.startsWith(vault.dir)
    check vault.setSecret("OPENROUTER_API_KEY", "sk-super-secret").isOk
    let raw = readFile(vault.path)
    check raw.contains("enc2:")
    check not raw.contains("sk-super-secret")
    check vault.listSecretNames().get() == @["OPENROUTER_API_KEY"]

    check vault.removeSecret("OPENROUTER_API_KEY").get() == true
    check vault.listSecretNames().get().len == 0
    check vault.removeSecret("OPENROUTER_API_KEY").get() == false

  test "persists across vault instances":
    removeDir(VaultTmp / "persist")
    let home = VaultTmp / "persist"
    check newSecretVault(home).setSecret("TOKEN", "value").isOk
    let reopened = newSecretVault(home)
    check reopened.listSecretNames().get() == @["TOKEN"]
    let previous = getEnv("TOKEN")
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", previous)
    check reopened.applyToEnv().get() == 1
    check getEnv("TOKEN") == "value"

  test "batch validation leaves the vault untouched":
    removeDir(VaultTmp / "batch")
    let vault = newSecretVault(VaultTmp / "batch")
    check vault.setSecret("KEEP", "old").isOk

    let res = vault.setSecrets(@[
      ("NEW", "new-value"),
      ("bad-name", "x"),
    ])
    check res.isErr
    check vault.listSecretNames().get() == @["KEEP"]

  test "batch validation rejects any tampered existing entry":
    removeDir(VaultTmp / "batch-tamper")
    let vault = newSecretVault(VaultTmp / "batch-tamper")
    check vault.setSecret("A", "alpha").isOk
    check vault.setSecret("B", "beta").isOk

    var root = parseJson(readFile(vault.path))
    var ciphertext = root["secrets"]["B"].getStr()
    let firstCipherHex = "enc2:".len + 12 * 2
    ciphertext[firstCipherHex] =
      if ciphertext[firstCipherHex] == '0': '1' else: '0'
    root["secrets"]["B"] = %ciphertext
    writeFile(vault.path, $root)
    let before = readFile(vault.path)

    let res = vault.setSecret("C", "gamma")
    check res.isErr
    check "does not match" in res.error
    check readFile(vault.path) == before

  test "a substituted key cannot append to an existing vault":
    removeDir(VaultTmp / "subkey")
    let vault = newSecretVault(VaultTmp / "subkey")
    check vault.setSecret("TOKEN_A", "alpha").isOk

    ## Replace the key with another valid 32-byte key.
    writeFile(vault.keyPath, newString(32))
    let res = vault.setSecret("TOKEN_B", "beta")
    check res.isErr
    check res.error.contains("does not match")
    check vault.listSecretNames().get() == @["TOKEN_A"]

  test "does not mint a new key over an existing vault":
    removeDir(VaultTmp / "lostkey")
    let vault = newSecretVault(VaultTmp / "lostkey")
    check vault.setSecret("TOKEN_A", "alpha").isOk
    removeFile(vault.keyPath)

    let res = vault.setSecret("TOKEN_B", "beta")
    check res.isErr
    check res.error.contains("key is missing")
    check vault.listSecretNames().get() == @["TOKEN_A"]

  test "bootstrap variables cannot be stored in the vault":
    removeDir(VaultTmp / "bootstrap")
    let vault = newSecretVault(VaultTmp / "bootstrap")
    let res = vault.setSecret("DONKEY_HOME", "/srv/donkey")
    check res.isErr
    check res.error.contains("must stay")

  test "rejects invalid names and empty values":
    removeDir(VaultTmp / "invalid")
    let vault = newSecretVault(VaultTmp / "invalid")
    check vault.setSecret("bad-name", "x").isErr
    check vault.setSecret("GOOD_NAME", "").isErr
    check vault.listSecretNames().get().len == 0

  test "applyToEnv decrypts only unset variables":
    removeDir(VaultTmp / "env")
    let vault = newSecretVault(VaultTmp / "env")
    check vault.setSecret("DONKEY_TEST_VAULT_A", "alpha").isOk
    check vault.setSecret("DONKEY_TEST_VAULT_B", "beta").isOk
    let previousA = getEnv("DONKEY_TEST_VAULT_A")
    let previousB = getEnv("DONKEY_TEST_VAULT_B")
    putEnv("DONKEY_TEST_VAULT_A", "")
    putEnv("DONKEY_TEST_VAULT_B", "already-set")
    defer:
      putEnv("DONKEY_TEST_VAULT_A", previousA)
      putEnv("DONKEY_TEST_VAULT_B", previousB)

    let applied = vault.applyToEnv()
    check applied.isOk
    check applied.get() == 1
    check getEnv("DONKEY_TEST_VAULT_A") == "alpha"
    check getEnv("DONKEY_TEST_VAULT_B") == "already-set"

  test "vault without key fails closed when decryption is needed":
    removeDir(VaultTmp / "nokey")
    let vault = newSecretVault(VaultTmp / "nokey")
    check vault.setSecret("TOKEN", "value").isOk
    removeFile(vault.keyPath)
    let previous = getEnv("TOKEN")
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", previous)

    let applied = vault.applyToEnv()
    check applied.isErr
    check applied.error.contains("key is missing")

  test "missing key is tolerated when every value is already in the environment":
    removeDir(VaultTmp / "nokey2")
    let vault = newSecretVault(VaultTmp / "nokey2")
    check vault.setSecret("TOKEN", "value").isOk
    removeFile(vault.keyPath)
    let previous = getEnv("TOKEN")
    putEnv("TOKEN", "already-set")
    defer: putEnv("TOKEN", previous)

    let applied = vault.applyToEnv()
    check applied.isOk
    check applied.get() == 0

  test "tampered ciphertext is rejected":
    removeDir(VaultTmp / "tamper")
    let vault = newSecretVault(VaultTmp / "tamper")
    check vault.setSecret("TOKEN", "value").isOk
    writeFile(vault.path, readFile(vault.path).replace("enc2:", "enc2:00"))
    let previous = getEnv("TOKEN")
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", previous)

    let applied = vault.applyToEnv()
    check applied.isErr
    check applied.error.contains("could not decrypt")

  test "a single ciphertext byte flip is rejected without leaking":
    removeDir(VaultTmp / "tamper-byte")
    let vault = newSecretVault(VaultTmp / "tamper-byte")
    check vault.setSecret("TOKEN", "value").isOk

    var root = parseJson(readFile(vault.path))
    var ciphertext = root["secrets"]["TOKEN"].getStr()
    let firstCipherHex = "enc2:".len + 12 * 2  # skip IV
    check ciphertext.len > firstCipherHex
    ciphertext[firstCipherHex] =
      if ciphertext[firstCipherHex] == '0': '1' else: '0'
    root["secrets"]["TOKEN"] = %ciphertext
    writeFile(vault.path, $root)

    let previous = getEnv("TOKEN")
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", previous)
    let applied = vault.applyToEnv()
    check applied.isErr
    check applied.error.contains("could not decrypt")
    check getEnv("TOKEN") == ""

  test "plaintext entries in the vault are rejected":
    removeDir(VaultTmp / "plain")
    let vault = newSecretVault(VaultTmp / "plain")
    createDir(vault.dir)
    writeFile(vault.path, $(%* {"version": 1,
                                "secrets": {"TOKEN": "not-encrypted"}}))

    let loaded = vault.listSecretNames()
    check loaded.isErr
    check loaded.error.contains("not encrypted")

  test "file permissions are private on POSIX":
    when not defined(windows):
      removeDir(VaultTmp / "perms")
      let vault = newSecretVault(VaultTmp / "perms")
      check vault.setSecret("TOKEN", "value").isOk
      let vaultPerms = getFilePermissions(vault.path)
      check fpUserRead in vaultPerms
      check fpUserWrite in vaultPerms
      check fpGroupRead notin vaultPerms
      check fpOthersRead notin vaultPerms
      let keyPerms = getFilePermissions(vault.keyPath)
      check fpGroupRead notin keyPerms
      check fpOthersRead notin keyPerms

      ## A restored key with a permissive mode is corrected before decrypting.
      setFilePermissions(vault.keyPath,
                         {fpUserRead, fpUserWrite, fpGroupRead})
      let previous = getEnv("TOKEN")
      putEnv("TOKEN", "")
      defer: putEnv("TOKEN", previous)
      check vault.applyToEnv().isOk
      let fixedPerms = getFilePermissions(vault.keyPath)
      check fpGroupRead notin fixedPerms
      check fpOthersRead notin fixedPerms
