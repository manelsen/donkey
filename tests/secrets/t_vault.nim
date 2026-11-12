import std/[json, os, strutils, unittest]
import results
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
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", "")
    check reopened.applyToEnv().get() == 1
    check getEnv("TOKEN") == "value"

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
    putEnv("DONKEY_TEST_VAULT_B", "already-set")
    defer:
      putEnv("DONKEY_TEST_VAULT_A", "")
      putEnv("DONKEY_TEST_VAULT_B", "")

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
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", "")

    let applied = vault.applyToEnv()
    check applied.isErr
    check applied.error.contains("key is missing")

  test "missing key is tolerated when every value is already in the environment":
    removeDir(VaultTmp / "nokey2")
    let vault = newSecretVault(VaultTmp / "nokey2")
    check vault.setSecret("TOKEN", "value").isOk
    removeFile(vault.keyPath)
    putEnv("TOKEN", "already-set")
    defer: putEnv("TOKEN", "")

    let applied = vault.applyToEnv()
    check applied.isOk
    check applied.get() == 0

  test "tampered ciphertext is rejected":
    removeDir(VaultTmp / "tamper")
    let vault = newSecretVault(VaultTmp / "tamper")
    check vault.setSecret("TOKEN", "value").isOk
    writeFile(vault.path, readFile(vault.path).replace("enc2:", "enc2:00"))
    putEnv("TOKEN", "")
    defer: putEnv("TOKEN", "")

    let applied = vault.applyToEnv()
    check applied.isErr
    check applied.error.contains("could not decrypt")

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
