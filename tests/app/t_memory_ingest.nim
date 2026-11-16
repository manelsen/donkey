import std/[json, os, strutils, unittest]
when defined(posix):
  import std/posix
import chronos
import chronos/asyncsync
import results
import donkey/app/native_tools
import donkey/app/session_state
import donkey/core/log
import donkey/core/types
import donkey/domain/message
import donkey/ports/memory

const TestRoot = "/tmp/donkey_memory_ingest_tests"
let ingestLog = newLogger("test.memory.ingest", lvlError)

type Capture = ref object
  chunks: seq[string]

proc runIngest(ctx: NativeCtx; input: string): Future[NativeToolResult] {.async.} =
  let call = ToolCallRequest(id: "m1", name: "memory_ingest", inputJson: input)
  result = await executeNativeTool(call, ctx, SessionState(), @[])

suite "memory_ingest tool":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "ingests a workspace file in chunks":
    writeFile(TestRoot / "notes.md",
      repeat("primeira parte com bastante texto. ", 20) & "\n\n" &
      repeat("segunda parte com mais texto. ", 20) & "\n\n" &
      repeat("terceira parte final. ", 20) & "\n")
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}:
          captured.chunks.add(text)
    )
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      paddockDir: TestRoot,
      memory: mem,
      log: ingestLog,
    )
    let res = waitFor runIngest(ctx, """{"path":"notes.md","chunk_chars":500}""")
    check res.handled
    check res.resultKind == trkOutput
    let parsed = parseJson(res.text)
    check parsed["ok"].getBool()
    check parsed["chunks"].getInt() >= 2
    let joined = captured.chunks.join("\n")
    check "primeira parte" in joined
    check "terceira parte" in joined

  test "accepts inline text":
    let captured = Capture()
    let mem = MemoryRuntimePort(
      appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
        {.cast(gcsafe).}:
          captured.chunks.add(text)
    )
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      paddockDir: TestRoot,
      memory: mem,
      log: ingestLog,
    )
    let res = waitFor runIngest(ctx, """{"text":"uma nota curta","chunk_chars":1000}""")
    check res.handled
    check res.resultKind == trkOutput
    check captured.chunks == @["uma nota curta"]

  test "rejects path traversal":
    let mem = MemoryRuntimePort()
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      paddockDir: TestRoot,
      memory: mem,
      log: ingestLog,
    )
    let res = waitFor runIngest(ctx, """{"path":"../etc/passwd"}""")
    check res.handled
    check res.resultKind == trkOperationalError
    check "outside paddock" in res.text or "path" in res.text

  test "rejects binary files":
    writeFile(TestRoot / "bin.dat", "abc\0def")
    let mem = MemoryRuntimePort()
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      paddockDir: TestRoot,
      memory: mem,
      log: ingestLog,
    )
    let res = waitFor runIngest(ctx, """{"path":"bin.dat"}""")
    check res.handled
    check res.resultKind == trkOperationalError
    check "binary" in res.text

  test "requires exactly one of path or text":
    let mem = MemoryRuntimePort()
    var ctx = NativeCtx(
      uid: UserId("u1"),
      channel: ckTelegram,
      paddockDir: TestRoot,
      memory: mem,
      log: ingestLog,
    )
    let both = waitFor runIngest(ctx, """{"path":"x","text":"y"}""")
    check both.resultKind == trkOperationalError
    let neither = waitFor runIngest(ctx, """{}""")
    check neither.resultKind == trkOperationalError

  when defined(posix):
    test "rejects a symlink that escapes the paddock":
      let outsideDir = TestRoot & "_outside"
      createDir(outsideDir)
      let outside = outsideDir / "secret.txt"
      writeFile(outside, "secret")
      defer: removeDir(outsideDir)
      createSymlink(outside, TestRoot / "link.txt")
      let mem = MemoryRuntimePort()
      var ctx = NativeCtx(
        uid: UserId("u1"),
        channel: ckTelegram,
        paddockDir: TestRoot,
        memory: mem,
        log: ingestLog,
      )
      let res = waitFor runIngest(ctx, """{"path":"link.txt"}""")
      check res.handled
      check res.resultKind == trkOperationalError
      check "symlink" in res.text or "outside paddock" in res.text

    test "rejects a dangling symlink":
      let outside = TestRoot & "_missing_outside.txt"
      removeFile(outside)
      createSymlink(outside, TestRoot / "dangling.txt")
      let mem = MemoryRuntimePort()
      var ctx = NativeCtx(
        uid: UserId("u1"),
        channel: ckTelegram,
        paddockDir: TestRoot,
        memory: mem,
        log: ingestLog,
      )
      let res = waitFor runIngest(ctx, """{"path":"dangling.txt"}""")
      check res.handled
      check res.resultKind == trkOperationalError
      check "symlink" in res.text or "resolve" in res.text

    test "unreadable file returns an operational error":
      if getuid() == 0:
        check true
      else:
        let path = TestRoot / "secret.txt"
        writeFile(path, "secret")
        setFilePermissions(path, {})
        let mem = MemoryRuntimePort()
        var ctx = NativeCtx(
          uid: UserId("u1"),
          channel: ckTelegram,
          paddockDir: TestRoot,
          memory: mem,
          log: ingestLog,
        )
        let res = waitFor runIngest(ctx, """{"path":"secret.txt"}""")
        check res.handled
        check res.resultKind == trkOperationalError
        check "read" in res.text or "inspect" in res.text
