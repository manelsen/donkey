## Stress: secret vault concurrency, atomicity and large values.

import std/[atomics, os, strutils, unittest]
import results
import donkey/adapters/secrets/vault
import donkey/core/pipeops

const StressDir = "/tmp/donkey_stress_vault"

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
  gSetOk:    array[32, bool]
  gRemoveOk: array[32, bool]
  gReadErrors: Atomic[int]

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
    for _ in 0 ..< 200:
      let names = newSecretVault(home).listSecretNames()
      if names.isErr:
        discard gReadErrors.fetchAdd(1)

suite "secret vault stress":

  test "concurrent writers keep every entry and a valid vault":
    let home = StressDir / "writers"
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
    let home = StressDir / "readers"
    removeDir(home)
    defer: removeDir(home)

    gReadErrors.store(0)
    var reader: Thread[string]
    createThread(reader, readerWorker, home)

    var threads: array[12, Thread[SetArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], setWorker,
                   SetArg(home: home, name: "DONKEY_STRESS_R" & $i,
                          value: "reader-" & $i, index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])
    joinThread(reader)

    check gReadErrors.load() == 0
    check newSecretVault(home).listSecretNames().get().len == threads.len

  test "mixed set and remove operations serialize correctly":
    let home = StressDir / "mixed"
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
    let home = StressDir / "large"
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
