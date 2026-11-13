## Stress: secret vault concurrency, atomicity and large values.

import std/[atomics, os, strutils, unittest]
import results
import donkey/adapters/secrets/vault
import donkey/core/pipeops

let stressDir = getTempDir() / ("donkey_stress_vault_" & $getCurrentProcessId())

type
  SetArg = object
    home:  string
    name:  string
    value: string
    index: int

  RemoveArg = object
    home:  string
    name:  string
    index: int

var
  gSetOk:      array[32, bool]
  gRemoveOk:   array[32, bool]
  gReadErrors: Atomic[int]
  gReadOk:     Atomic[int]
  gReaderReady: Atomic[int]
  gWritersDone: Atomic[bool]

proc setWorker(arg: SetArg) {.thread.} =
  {.cast(gcsafe).}:
    gSetOk[arg.index] =
      newSecretVault(arg.home).setSecret(arg.name, arg.value).isOk

proc removeWorker(arg: RemoveArg) {.thread.} =
  {.cast(gcsafe).}:
    gRemoveOk[arg.index] =
      newSecretVault(arg.home).removeSecret(arg.name).isOk

proc readerWorker(home: string) {.thread.} =
  {.cast(gcsafe).}:
    let first = newSecretVault(home).listSecretNames()
    if first.isErr:
      discard gReadErrors.fetchAdd(1)
    else:
      discard gReadOk.fetchAdd(1)
    discard gReaderReady.fetchAdd(1)
    while not gWritersDone.load():
      let names = newSecretVault(home).listSecretNames()
      if names.isErr:
        discard gReadErrors.fetchAdd(1)
      sleep(1)

suite "secret vault stress":

  test "concurrent writers keep every entry and a valid vault":
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
    let names = newSecretVault(home).listSecretNames()
    check names.isOk
    check names.get().len == threads.len

    let raw = readFile(home / VaultDirName / VaultFileName)
    check raw.contains("enc2:")
    check "value-0" notin raw

  test "readers never see a truncated vault during writes":
    let home = stressDir / "readers"
    removeDir(home)
    defer: removeDir(home)

    gReadErrors.store(0)
    gReadOk.store(0)
    gReaderReady.store(0)
    gWritersDone.store(false)
    var reader: Thread[string]
    createThread(reader, readerWorker, home)
    while gReaderReady.load() == 0:
      sleep(1)

    var threads: array[12, Thread[SetArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], setWorker,
                   SetArg(home: home, name: "DONKEY_STRESS_R" & $i,
                          value: "reader-" & $i, index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])
    gWritersDone.store(true)
    joinThread(reader)

    check gReadErrors.load() == 0
    check gReadOk.load() > 0
    check newSecretVault(home).listSecretNames().get().len == threads.len

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
