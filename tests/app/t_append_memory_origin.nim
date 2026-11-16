import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/app/onboarding_runtime
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
                             origin: MemoryOrigin): Result[void, string]
                             {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          captured.tagged.add(text)
          captured.origins.add(origin)
        ok(),
    )
    check safeAppendMemory(mem, UserId("u1"), "fato", turnOrigin("s1")).isOk
    check captured.plain.len == 0
    check captured.tagged == @["fato"]
    check captured.origins == @[turnOrigin("s1")]

  test "falls back to plain append when the backend has no hook":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}: captured.plain.add(text),
    )
    check safeAppendMemory(mem, UserId("u1"), "fato", turnOrigin("s1")).isOk
    check captured.plain == @["fato"]

  test "origin stays optional":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}: captured.plain.add(text),
    )
    check safeAppendMemory(mem, UserId("u1"), "fato").isOk
    check captured.plain == @["fato"]

  test "a failed append is reported to the caller":
    let failing = MemoryRuntimePort(
      appendMemoryFrom: proc(userId: UserId; text: string;
                             origin: MemoryOrigin): Result[void, string]
                             {.gcsafe, raises: [].} =
        err("graph unavailable"),
    )
    let res = safeAppendMemory(failing, UserId("u1"), "fato", turnOrigin("s1"))
    check res.isErr
    check res.error == "graph unavailable"

  test "an exception in a plain backend is reported, not swallowed":
    let raising = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        raise newException(IOError, "disk full"),
    )
    let res = safeAppendMemory(raising, UserId("u1"), "fato")
    check res.isErr
    check "disk full" in res.error
