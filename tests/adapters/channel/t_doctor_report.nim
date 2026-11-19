import std/[os, strutils, unittest]
import results
import donkey/adapters/channel/common_runtime
import donkey/adapters/memory/md_file
import donkey/domain/message
import donkey/ports/provider

const TestRoot = "/tmp/donkey_doctor_report_tests"

proc runTests*() =
  suite "doctor report provider selection":

    setup:
      removeDir(TestRoot)
      createDir(TestRoot)

    teardown:
      removeDir(TestRoot)

    test "uses the user's preferences, not the instance default":
      let memory = MdFileAdapter(paddocksDir: TestRoot)
      let uid = UserId("doctor-user")
      memory.savePreferences(uid,
        "provider = \"minimax\"\nmodel = \"MiniMax-M3.1-Flash\"\n")

      type Capture = ref object
        value: string
      let captured = Capture()
      let builder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
        {.cast(gcsafe).}:
          captured.value = preferencesMd
        result = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
          ok(CompletionResponse(text: "pong"))

      let report = buildDoctorReport(memory, builder, uid, 2, 0, 1)
      check "minimax" in captured.value
      check "MiniMax-M3.1-Flash" in captured.value
      check "Provider: OK" in report
      check "minimax / MiniMax-M3.1-Flash" in report

    test "shows the active provider failure":
      let memory = MdFileAdapter(paddocksDir: TestRoot)
      let uid = UserId("doctor-fail")
      memory.savePreferences(uid,
        "provider = \"openrouter\"\nmodel = \"baidu/ernie-5.5-flash-preview:free\"\n")

      let builder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
        result = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
          err("400 invalid image_url for file_id")

      let report = buildDoctorReport(memory, builder, uid, 2, 0, 1)
      check "Provider:" in report
      check "invalid image_url" in report

when isMainModule:
  runTests()
