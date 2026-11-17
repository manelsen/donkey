import std/unittest
import donkey/app/onboarding_runtime
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/memory/provenance_pure
import donkey/ports/memory

type Capture = ref object
  plain:   seq[string]
  tagged:  seq[string]
  origins: seq[MemoryOrigin]

suite "safeAppendMemory with origin":

  test "uses the origin-aware hook when the backend has one":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}: captured.plain.add(text),
      appendMemoryFrom: proc(userId: UserId; text: string;
                             origin: MemoryOrigin):
                             Result[void, string] {.gcsafe.} =
        {.cast(gcsafe).}:
          captured.tagged.add(text)
          captured.origins.add(origin)
        ok(),
    )
    safeAppendMemory(mem, UserId("u1"), "fato", turnOrigin("s1"))
    check captured.plain.len == 0
    check captured.tagged == @["fato"]
    check captured.origins == @[turnOrigin("s1")]

  test "falls back to plain append when the backend has no hook":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}: captured.plain.add(text),
    )
    safeAppendMemory(mem, UserId("u1"), "fato", turnOrigin("s1"))
    check captured.plain == @["fato"]

  test "origin stays optional":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}: captured.plain.add(text),
    )
    safeAppendMemory(mem, UserId("u1"), "fato")
    check captured.plain == @["fato"]
