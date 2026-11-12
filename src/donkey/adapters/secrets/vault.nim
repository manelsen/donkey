## SecretVault — encrypted operator secrets stored under {home}/.secrets/.
##
## Cipher:   AES-256-GCM via FileKeyStore.
## Layout:   {home}/.secret_key            256-bit key, 0600
##           {home}/.secrets/secrets.json  {"version":1,"secrets":{NAME:"enc2:..."}}
##
## The key is deliberately outside `.secrets/`: copying or backing up that
## directory does not expose the values.
##
## `ctl secret` writes values; the daemon decrypts them into the process
## environment at startup only for variables that are not already set (shell
## env and donkey.env keep precedence). The vault protects secrets at rest
## (backups, accidental copies); it does not protect against another process
## running as the same Unix user, which can read the key.

import std/[algorithm, json, os, strutils, tables]
when defined(posix):
  import std/posix
import ../../core/pipeops
import ../../core/security/secret_names
import ./file_key

const
  VaultDirName*    = ".secrets"
  VaultFileName*   = "secrets.json"
  VaultKeyFileName* = ".secret_key"
  VaultVersion*    = 1

  ## Variables that must remain in the bootstrap environment: the vault is
  ## located under DONKEY_HOME, so storing it in the vault creates a cycle.
  BootstrapEnvVars* = ["DONKEY_HOME"]

type
  SecretVault* = ref object
    dir*:      string
    path*:     string
    keyPath*:  string
    keyStore:  FileKeyStore

when defined(posix):
  proc cFlock(fd: cint; operation: cint): cint {.
    importc: "flock", header: "<sys/file.h>".}
  const
    VaultLockExclusive = cint(2)
    VaultLockUnlock    = cint(8)

proc newSecretVault*(home: string): SecretVault =
  let dir = home / VaultDirName
  SecretVault(
    dir:      dir,
    path:     dir / VaultFileName,
    keyPath:  home / VaultKeyFileName,
    keyStore: newFileKeyStore(home / VaultKeyFileName),
  )

proc hardenDirPermissions(dir: string) =
  when defined(posix):
    discard posix.chmod(dir.cstring, posix.Mode(0o700))

proc hardenFilePermissions(path: string) =
  when defined(posix):
    discard posix.chmod(path.cstring, posix.Mode(0o600))

proc withVaultLock*[T](vault: SecretVault;
                       body: proc(): Result[T, string] {.gcsafe, raises: [].}):
                       Result[T, string] {.gcsafe, raises: [].} =
  ## Serializes read-modify-write cycles between concurrent `ctl` processes.
  when defined(posix):
    let lockPath = vault.path & ".lock"
    try:
      createDir(vault.dir)
      hardenDirPermissions(vault.dir)
      var lockFile = open(lockPath, fmReadWrite)
      hardenFilePermissions(lockPath)
      let fd = cint(lockFile.getFileHandle())
      if cFlock(fd, VaultLockExclusive) != 0:
        lockFile.close()
        return err("secret vault lock failed")
      try:
        result = body()
      finally:
        discard cFlock(fd, VaultLockUnlock)
        lockFile.close()
    except CatchableError as e:
      result = err("secret vault lock failed: " & e.msg)
  else:
    result = body()

proc readStored(vault: SecretVault):
                Result[OrderedTable[string, string], string] {.raises: [].} =
  if not fileExists(vault.path):
    return ok(initOrderedTable[string, string]())
  try:
    let root = parseJson(readFile(vault.path))
    if root.kind != JObject:
      return err("secret vault is not a JSON object")
    let version = root.getOrDefault("version").getInt(0)
    if version != VaultVersion:
      return err("unsupported secret vault version: " & $version)
    let secrets = root.getOrDefault("secrets")
    if secrets == nil or secrets.kind != JObject:
      return err("secret vault has no secrets object")
    var stored = initOrderedTable[string, string]()
    for name, value in secrets:
      if not isValidSecretName(name):
        return err("invalid secret name in vault: " & name)
      if value.kind != JString:
        return err("secret '" & name & "' is not a string")
      let ciphertext = value.getStr
      if not ciphertext.startsWith(EncPrefix):
        return err("secret '" & name & "' is not encrypted")
      stored[name] = ciphertext
    ok(stored)
  except CatchableError as e:
    err("secret vault read failed: " & e.msg)

proc writeStored(vault: SecretVault;
                 stored: OrderedTable[string, string]): Result[void, string] {.raises: [].} =
  var secrets = newJObject()
  for name, value in stored:
    secrets[name] = %value
  let payload = %* {"version": VaultVersion, "secrets": secrets}
  var tmp = ""
  try:
    createDir(vault.dir)
    hardenDirPermissions(vault.dir)
    tmp = vault.path & ".tmp." & $getCurrentProcessId() & "-" & $epochMs()
    writeFile(tmp, payload.pretty & "\n")
    hardenFilePermissions(tmp)
    {.cast(raises: []).}:
      moveFile(tmp, vault.path)
    ok()
  except CatchableError as e:
    if tmp.len > 0 and fileExists(tmp):
      try:
        removeFile(tmp)
      except CatchableError:
        discard
    err("secret vault write failed: " & e.msg)

proc setSecret*(vault: SecretVault;
                name, value: string): Result[void, string] {.raises: [].} =
  if not isValidSecretName(name):
    return err("invalid secret name: '" & name &
               "' (use letters, digits and _, starting with a letter or _)")
  if name in BootstrapEnvVars:
    return err("'" & name & "' must stay in donkey.env: it locates the secret vault")
  if value.len == 0:
    return err("secret value is empty")
  vault.withVaultLock(proc(): Result[void, string] {.gcsafe, raises: [].} =
    let loaded = vault.readStored()
    if loaded.isErr:
      return err(loaded.error)
    var stored = loaded.get()
    if stored.len > 0 and not fileExists(vault.keyPath):
      ## Never mint a new key over an existing vault: the old entries would
      ## become unrecoverable while the new one silently used a different key.
      return err("secret vault key is missing; restore " & vault.keyPath &
                 " or reset the vault explicitly")
    let encrypted = vault.keyStore.encrypt(value)
    if encrypted.isErr:
      return err("secret encryption failed: " & encrypted.error)
    stored[name] = encrypted.get()
    vault.writeStored(stored))

proc listSecretNames*(vault: SecretVault):
                      Result[seq[string], string] {.raises: [].} =
  let loaded = vault.readStored()
  if loaded.isErr:
    return err(loaded.error)
  var names: seq[string]
  for name in loaded.get().keys:
    names.add(name)
  names.sort()
  ok(names)

proc removeSecret*(vault: SecretVault;
                   name: string): Result[bool, string] {.raises: [].} =
  if not isValidSecretName(name):
    return err("invalid secret name: '" & name & "'")
  vault.withVaultLock(proc(): Result[bool, string] {.gcsafe, raises: [].} =
    let loaded = vault.readStored()
    if loaded.isErr:
      return err(loaded.error)
    var stored = loaded.get()
    if not stored.hasKey(name):
      return ok(false)
    stored.del(name)
    let saved = vault.writeStored(stored)
    if saved.isErr:
      return err(saved.error)
    ok(true))

proc applyToEnv*(vault: SecretVault): Result[int, string] {.raises: [].} =
  ## Decrypts stored values into the process environment. Existing variables
  ## are never overwritten, so shell env and donkey.env keep precedence.
  let loaded = vault.readStored()
  if loaded.isErr:
    return err(loaded.error)
  let stored = loaded.get()
  var applied = 0
  for name, ciphertext in stored:
    if getEnv(name).len > 0:
      continue
    if not fileExists(vault.keyPath):
      return err("secret vault key is missing: " & vault.keyPath)
    let decrypted = vault.keyStore.decrypt(ciphertext)
    if decrypted.isErr:
      return err("could not decrypt secret '" & name & "': " & decrypted.error)
    let plaintext = decrypted.get()
    if plaintext.len == 0:
      return err("secret '" & name & "' decrypted to an empty value")
    try:
      putEnv(name, plaintext)
    except CatchableError as e:
      return err("could not set secret '" & name & "': " & e.msg)
    inc applied
  ok(applied)
