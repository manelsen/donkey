## FileKeyStore — SecretStore implementation using a local key file.
##
## Cipher:    AES-256-GCM (AEAD, RFC 5116)
## Key:       256-bit random, stored at the configured key path (created with
##            mode 0600; the vault uses {home}/.secret_key).
## Wire fmt:  enc2:<hex(iv[12] || ciphertext || tag[16])>
##
## Disabled mode (enable=false): encrypt/decrypt are identity functions.
## Used in tests and dev environments without a key file.

import std/[os, strutils]
when defined(posix):
  import std/posix
import nimcrypto/[rijndael, bcmode, sysrand, utils]

const
  KeyLen*    = aes256.sizeKey()  ## 32 bytes
  IvLen*     = 12                ## GCM standard IV
  TagLen*    = 16                ## GCM tag = 128 bits
  EncPrefix* = "enc2:"

type
  Key = array[KeyLen, byte]

  DecryptionError* = object of CatchableError

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

proc createKeyFile(keyPath: string; key: Key): bool =
  ## Creates the key atomically with mode 0600. The umask must never get a
  ## window where the key is readable by other local users.
  when defined(posix):
    let fd = posix.open(keyPath.cstring,
                        posix.O_WRONLY or posix.O_CREAT or posix.O_EXCL,
                        posix.Mode(0o600))
    if fd < 0:
      return false
    defer: discard posix.close(fd)
    posix.write(fd, unsafeAddr key[0], KeyLen) == KeyLen
  else:
    var keyStr = newString(KeyLen)
    copyMem(addr keyStr[0], unsafeAddr key[0], KeyLen)
    writeFile(keyPath, keyStr)
    setFilePermissions(keyPath, {fpUserRead, fpUserWrite})
    true

proc loadOrCreateKey(store: FileKeyStore): Key =
  if fileExists(store.keyPath):
    let raw = readFile(store.keyPath)
    if raw.len != KeyLen:
      raise newException(IOError,
        "Corrupt key file (expected " & $KeyLen & " bytes): " & store.keyPath)
    copyMem(addr result[0], unsafeAddr raw[0], KeyLen)
    when defined(posix):
      setFilePermissions(store.keyPath, {fpUserRead, fpUserWrite})
  else:
    createDir(store.keyPath.parentDir)
    if randomBytes(result) != KeyLen:
      raise newException(OSError, "Failed to generate random key bytes")
    if not createKeyFile(store.keyPath, result):
      raise newException(IOError,
        "Failed to create key file atomically: " & store.keyPath)

# ── AES-256-GCM AEAD ──────────────────────────────────────────────────────────

proc sealGCM(key: Key; iv: array[IvLen, byte];
             plaintext: openArray[byte]): seq[byte] =
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

proc openGCM(key: Key; wire: openArray[byte]): seq[byte] =
  ## Decrypts wire (iv || ct || tag). Raises DecryptionError on auth failure.
  if wire.len < IvLen + TagLen:
    raise newException(DecryptionError, "Ciphertext too short to be valid")

  var iv: array[IvLen, byte]
  copyMem(addr iv[0], unsafeAddr wire[0], IvLen)

  let ctLen = wire.len - IvLen - TagLen

  # Decrypt first, then verify tag (GCM is encrypt-then-MAC internally)
  result = newSeq[byte](ctLen)
  var ctx: GCM[aes256]
  ctx.init(key, iv, [])

  if ctLen > 0:
    ctx.decrypt(toOpenArray(wire, IvLen, IvLen + ctLen - 1), result)

  # Verify authentication tag (constant-time via XOR accumulation)
  var computedTag = ctx.getTag()
  var storedTag: array[TagLen, byte]
  copyMem(addr storedTag[0], unsafeAddr wire[IvLen + ctLen], TagLen)

  var diff: byte = 0
  for i in 0 ..< TagLen:
    diff = diff or (computedTag[i] xor storedTag[i])
  if diff != 0:
    raise newException(DecryptionError, "AES-GCM authentication failed — data tampered")

# ── public API ────────────────────────────────────────────────────────────────

proc isEncrypted*(store: FileKeyStore; value: string): bool =
  value.startsWith(EncPrefix)

proc encrypt*(store: FileKeyStore; plaintext: string): string =
  if not store.enabled or plaintext.len == 0:
    return plaintext

  let key = store.loadOrCreateKey()

  var iv: array[IvLen, byte]
  if randomBytes(iv) != IvLen:
    raise newException(OSError, "Failed to generate IV")

  let wire = sealGCM(key, iv, plaintext.toOpenArrayByte(0, plaintext.len - 1))
  EncPrefix & toHex(wire)

proc decrypt*(store: FileKeyStore; ciphertext: string): string =
  if not ciphertext.startsWith(EncPrefix):
    return ciphertext

  let hex  = ciphertext[EncPrefix.len .. ^1]
  let wire = utils.fromHex(hex)
  let key  = store.loadOrCreateKey()
  let raw  = openGCM(key, wire)
  var s = newString(raw.len)
  if raw.len > 0:
    copyMem(addr s[0], unsafeAddr raw[0], raw.len)
  s
