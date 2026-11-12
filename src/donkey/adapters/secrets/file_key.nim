## FileKeyStore — SecretStore implementation using a local key file.
##
## Cipher:    AES-256-GCM (AEAD, RFC 5116)
## Key:       256-bit random, stored at the configured key path (created with
##            mode 0600; the vault uses {home}/.secret_key).
## Wire fmt:  enc2:<hex(iv[12] || ciphertext || tag[16])>
##
## Disabled mode (enable=false): encrypt/decrypt are identity functions.
## Used in tests and dev environments without a key file.
##
## The adapter returns Result on every fallible path; callers own the policy.

import std/[os, strutils]
when defined(posix):
  import std/posix
import nimcrypto/[rijndael, bcmode, sysrand, utils]
import ../../core/pipeops

const
  KeyLen*    = aes256.sizeKey()  ## 32 bytes
  IvLen*     = 12                ## GCM standard IV
  TagLen*    = 16                ## GCM tag = 128 bits
  EncPrefix* = "enc2:"

type
  Key = array[KeyLen, byte]

  FileKeyStore* = object
    keyPath*: string
    enabled*: bool
    label*:   string

# ── constructor ───────────────────────────────────────────────────────────────

proc newFileKeyStore*(keyPath: string; enable = true): FileKeyStore =
  FileKeyStore(
    keyPath: keyPath,
    enabled: enable,
    label:   if enable: "FileKeyStore(" & keyPath & ")" else: "FileKeyStore(disabled)",
  )

# ── key management ────────────────────────────────────────────────────────────

proc createKeyFile(keyPath: string; key: Key): Result[void, string] {.raises: [].} =
  ## Creates the key atomically with mode 0600. The umask must never get a
  ## window where the key is readable by other local users.
  when defined(posix):
    let fd = posix.open(keyPath.cstring,
                        posix.O_WRONLY or posix.O_CREAT or posix.O_EXCL,
                        posix.Mode(0o600))
    if fd < 0:
      return err("cannot create key file: " & keyPath)
    let written = posix.write(fd, unsafeAddr key[0], KeyLen)
    discard posix.close(fd)
    if written != KeyLen:
      ## A partial key file would poison every later load; remove it.
      discard posix.unlink(keyPath.cstring)
      return err("short write while creating key file: " & keyPath)
    ok()
  else:
    try:
      var keyStr = newString(KeyLen)
      copyMem(addr keyStr[0], unsafeAddr key[0], KeyLen)
      writeFile(keyPath, keyStr)
      setFilePermissions(keyPath, {fpUserRead, fpUserWrite})
      ok()
    except CatchableError as e:
      err("cannot create key file: " & e.msg)

proc loadOrCreateKey(store: FileKeyStore): Result[Key, string] {.raises: [].} =
  if fileExists(store.keyPath):
    try:
      let raw = readFile(store.keyPath)
      if raw.len != KeyLen:
        return err("Corrupt key file (expected " & $KeyLen & " bytes): " &
                   store.keyPath)
      var key: Key
      copyMem(addr key[0], unsafeAddr raw[0], KeyLen)
      ok(key)
    except CatchableError as e:
      err("cannot read key file: " & e.msg)
  else:
    try:
      createDir(store.keyPath.parentDir)
    except CatchableError as e:
      return err("cannot create key directory: " & e.msg)
    var key: Key
    if randomBytes(key) != KeyLen:
      return err("failed to generate random key bytes")
    ? createKeyFile(store.keyPath, key)
    ok(key)

# ── AES-256-GCM AEAD ──────────────────────────────────────────────────────────

proc sealGCM(key: Key; iv: array[IvLen, byte];
             plaintext: openArray[byte]): seq[byte] {.raises: [].} =
  ## Returns iv || ciphertext || tag (raw bytes).
  let ctLen = plaintext.len
  var ctx: GCM[aes256]
  ctx.init(key, iv, [])             # no AAD in this scheme

  var ct = newSeq[byte](ctLen)
  if ctLen > 0:
    ctx.encrypt(plaintext, ct)

  var tag = ctx.getTag()

  result = newSeq[byte](IvLen + ctLen + TagLen)
  copyMem(addr result[0],           unsafeAddr iv[0],  IvLen)
  if ctLen > 0:
    copyMem(addr result[IvLen],     addr ct[0],         ctLen)
  copyMem(addr result[IvLen+ctLen], addr tag[0],        TagLen)

proc openGCM(key: Key;
             wire: openArray[byte]): Result[seq[byte], string] {.raises: [].} =
  ## Decrypts wire (iv || ct || tag) and verifies the authentication tag.
  if wire.len < IvLen + TagLen:
    return err("Ciphertext too short to be valid")

  var iv: array[IvLen, byte]
  copyMem(addr iv[0], unsafeAddr wire[0], IvLen)

  let ctLen = wire.len - IvLen - TagLen

  var plaintext = newSeq[byte](ctLen)
  var ctx: GCM[aes256]
  ctx.init(key, iv, [])

  if ctLen > 0:
    ctx.decrypt(toOpenArray(wire, IvLen, IvLen + ctLen - 1), plaintext)

  # Verify authentication tag (constant-time via XOR accumulation)
  var computedTag = ctx.getTag()
  var storedTag: array[TagLen, byte]
  copyMem(addr storedTag[0], unsafeAddr wire[IvLen + ctLen], TagLen)

  var diff: byte = 0
  for i in 0 ..< TagLen:
    diff = diff or (computedTag[i] xor storedTag[i])
  if diff != 0:
    return err("AES-GCM authentication failed — data tampered")

  ok(plaintext)

# ── public API ────────────────────────────────────────────────────────────────

proc isEncrypted*(store: FileKeyStore; value: string): bool =
  value.startsWith(EncPrefix)

proc encrypt*(store: FileKeyStore;
              plaintext: string): Result[string, string] {.raises: [].} =
  if not store.enabled or plaintext.len == 0:
    return ok(plaintext)

  let key = ? store.loadOrCreateKey()

  var iv: array[IvLen, byte]
  if randomBytes(iv) != IvLen:
    return err("failed to generate IV")

  let wire = sealGCM(key, iv, plaintext.toOpenArrayByte(0, plaintext.len - 1))
  ok(EncPrefix & toHex(wire))

proc decrypt*(store: FileKeyStore;
              ciphertext: string): Result[string, string] {.raises: [].} =
  if not ciphertext.startsWith(EncPrefix):
    return ok(ciphertext)

  let hex = ciphertext[EncPrefix.len .. ^1]
  var wire: seq[byte]
  try:
    wire = utils.fromHex(hex)
  except CatchableError as e:
    return err("invalid ciphertext encoding: " & e.msg)

  let key = ? store.loadOrCreateKey()
  let raw = ? openGCM(key, wire)
  var plaintext = newString(raw.len)
  if raw.len > 0:
    copyMem(addr plaintext[0], unsafeAddr raw[0], raw.len)
  ok(plaintext)
