## Stress: secret vault concurrency, atomicity and large values.

import std/[atomics, os, strutils, unittest]
import results
import donkey/adapters/secrets/vault
import donkey/core/pipeops

let stressDir = getTempDir() / ("donkey_stress_vault_" & $getCurrentProcessId())

type
  SetArg = object
    home:       string
    name:       string
    value: string
    index: int

  RemoveArg = object
    home:  string
    name:  string
    index: int

var
  gSetOk:    array[32, bool]
  gRemoveOk: array[32, bool]
  gBlockedOk:      Atomic[bool]
  gSaveCompleted:  Atomic[bool]
  gSaveWait:       Channel[bool]
  gSaveRelease:    Channel[bool]
  gBlockedWriter:  Thread[SetArg]
  gReaderOk:       bool
  gReaderNames:    seq[string]

proc setWorker(arg: SetArg) {.thread.} =
  {.cast(gcsafe).}:
    gSetOk[arg.index] =
      newSecretVault(arg.home).setSecret(arg.name, arg.value).isOk

proc blockedSetWorker(arg: SetArg) {.thread.} =
  {.cast(gcsafe).}:
    let vault = newSecretVault(arg.home)
    vault.onAfterTempWrite = proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          gSaveWait.send(true)
          discard gSaveRelease.recv()
    gBlockedOk.store(vault.setSecret(arg.name, arg.value).isOk)
    gSaveCompleted.store(true)

proc waitSave(): bool =
  var waited = 0
  while waited < 5000:
    let (hasSignal, value) = gSaveWait.tryRecv()
    if hasSignal:
      return value
    if gSaveCompleted.load():
      return false
    sleep(1)
    waited += 1
  false

proc removeWorker(arg: RemoveArg) {.thread.} =
  {.cast(gcsafe).}:
    gRemoveOk[arg.index] =
      newSecretVault(arg.home).removeSecret(arg.name).isOk

suite "secret vault stress":

  test "concurrent writers keep every entry and decrypt every value":
    let home = stressDir / "writers"
    removeDir(home)
    defer: removeDir(home)

    var threads: array[12, Thread[SetArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], setWorker,
                   SetArg(home: home, name: "DONKEY_STRESS_V" & $i,
                          value: "value-" & $i, index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])

    for i in 0 ..< threads.len:
      check gSetOk[i]

    let vault = newSecretVault(home)
    let names = vault.listSecretNames()
    check names.isOk
    check names.get().len == threads.len

    var previous: array[12, string]
    for i in 0 ..< threads.len:
      let envName = "DONKEY_STRESS_V" & $i
      previous[i] = getEnv(envName)
      putEnv(envName, "")
    let applied = vault.applyToEnv()
    check applied.isOk
    for i in 0 ..< threads.len:
      let envName = "DONKEY_STRESS_V" & $i
      check getEnv(envName) == "value-" & $i
      putEnv(envName, previous[i])

    let raw = readFile(home / VaultDirName / VaultFileName)
    check raw.contains("enc2:")
    for i in 0 ..< threads.len:
      check "value-" & $i notin raw

  test "mixed set and remove operations serialize correctly":
    let home = stressDir / "mixed"
    removeDir(home)
    defer: removeDir(home)

    let vault = newSecretVault(home)
    for i in 0 ..< 6:
      check vault.setSecret("DONKEY_STRESS_M" & $i, "old-" & $i).isOk

    var removers: array[6, Thread[RemoveArg]]
    var setters: array[6, Thread[SetArg]]
    for i in 0 ..< 6:
      createThread(removers[i], removeWorker,
                   RemoveArg(home: home, name: "DONKEY_STRESS_M" & $i,
                             index: i))
      createThread(setters[i], setWorker,
                   SetArg(home: home, name: "DONKEY_STRESS_N" & $i,
                          value: "new-" & $i, index: i + 6))
    for i in 0 ..< 6:
      joinThread(removers[i])
      joinThread(setters[i])
      check gRemoveOk[i]
      check gSetOk[i + 6]

    let names = newSecretVault(home).listSecretNames()
    check names.isOk
    check names.get().len == 6
    for name in names.get():
      check name.startsWith("DONKEY_STRESS_N")

  test "large values roundtrip without truncation":
    let home = stressDir / "large"
    removeDir(home)
    defer: removeDir(home)

    let value = repeat("x", 32 * 1024)
    let vault = newSecretVault(home)
    check vault.setSecret("DONKEY_STRESS_BIG", value).isOk

    let previous = getEnv("DONKEY_STRESS_BIG")
    putEnv("DONKEY_STRESS_BIG", "")
    defer: putEnv("DONKEY_STRESS_BIG", previous)
    check vault.applyToEnv().isOk
    check getEnv("DONKEY_STRESS_BIG").len == value.len
    check getEnv("DONKEY_STRESS_BIG") == value

  test "reader sees a stable vault while a write is being saved":
    let home = stressDir / "locked"
    removeDir(home)
    defer: removeDir(home)
    let vault = newSecretVault(home)
    check vault.setSecret("KEEP", "old").isOk

    gBlockedOk.store(false)
    gSaveCompleted.store(false)
    gReaderOk = false
    gReaderNames = @[]
    gSaveWait.open(1)
    gSaveRelease.open(1)

    createThread(gBlockedWriter, blockedSetWorker,
                 SetArg(home: home, name: "NEW", value: "new", index: 0))
    let hooked = waitSave()
    check hooked
    if hooked:
      check not gSaveCompleted.load()

      ## The writer holds the lock and has not written yet; this reader runs
      ## on a different thread and must see the previous complete vault.
      let names = vault.listSecretNames()
      gReaderOk = names.isOk
      if names.isOk:
        gReaderNames = names.get()
      check gReaderNames == @["KEEP"]

    gSaveRelease.send(true)
    joinThread(gBlockedWriter)
    gSaveWait.close()
    gSaveRelease.close()
    check gBlockedOk.load()
    check gSaveCompleted.load()
    check gReaderOk
    check vault.listSecretNames().get().len == 2
