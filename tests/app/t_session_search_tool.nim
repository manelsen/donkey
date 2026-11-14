## Integration test for the native session_search tool.

import std/[json, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/adapters/memory/md_file
import donkey/app/native_tools
import donkey/app/session_state
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message

let toolBase = getTempDir() / ("donkey_session_tool_" & $getCurrentProcessId())
let toolLog = newLogger("test.session.search", lvlError)

suite "native session_search tool":

  test "searches only the current user's sessions":
    removeDir(toolBase)
    createDir(toolBase)
    defer: removeDir(toolBase)
    let adapter = MdFileAdapter(paddocksDir: toolBase)
    let uid = UserId("user-a")
    let paddock = adapter.paddockDir(uid)
    createDir(paddock / "sessions")
    writeFile(paddock / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "We chose blue-green for production deploy"}) & "\n")
    let memory = adapter.toRuntimePort()
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: uid,
      channel: ckCli,
      outbox: outbox,
      memory: memory,
      log: toolLog,
      paddockDir: paddock,
    )
    let call = ToolCallRequest(
      id: "search-1",
      name: "session_search",
      inputJson: """{"query":"production deploy","limit":5}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check not res.text.startsWith("Error")
    check "s1" in res.text
    check "blue-green" in res.text
    check "production" in res.text

  test "empty query is a usage error":
    let adapter = MdFileAdapter(paddocksDir: toolBase)
    let uid = UserId("user-a")
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: uid,
      channel: ckCli,
      outbox: outbox,
      memory: adapter.toRuntimePort(),
      log: toolLog,
      paddockDir: adapter.paddockDir(uid),
    )
    let call = ToolCallRequest(
      id: "search-2",
      name: "session_search",
      inputJson: """{"query":""}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.text.contains("'query' is required")

  test "backend without session search fails closed":
    let outbox = newAsyncQueue[OutboundMessage](4)
    var ctx = NativeCtx(
      uid: UserId("user-a"),
      channel: ckCli,
      outbox: outbox,
      log: toolLog,
      paddockDir: "/tmp",
    )
    let call = ToolCallRequest(
      id: "search-3",
      name: "session_search",
      inputJson: """{"query":"anything"}""",
    )
    let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
    check res.handled
    check res.text.contains("unavailable")

  test "dispatcher forwards the correct user identity":
    removeDir(toolBase)
    createDir(toolBase)
    defer: removeDir(toolBase)
    let adapter = MdFileAdapter(paddocksDir: toolBase)
    let a = UserId("user-a")
    let b = UserId("user-b")
    for (uid, marker) in [(a, "alpha-secret"), (b, "beta-secret")]:
      let dir = adapter.paddockDir(uid) / "sessions"
      createDir(dir)
      writeFile(dir / "s1.jsonl",
        $(%*{"role": "user", "text": "shared term " & marker}) & "\n")
    let memory = adapter.toRuntimePort()
    let outbox = newAsyncQueue[OutboundMessage](4)
    for (uid, expected, forbidden) in [
      (a, "alpha-secret", "beta-secret"),
      (b, "beta-secret", "alpha-secret"),
    ]:
      var ctx = NativeCtx(
        uid: uid,
        channel: ckCli,
        outbox: outbox,
        memory: memory,
        log: toolLog,
        paddockDir: adapter.paddockDir(uid),
      )
      let call = ToolCallRequest(
        id: "search-" & $uid,
        name: "session_search",
        inputJson: """{"query":"shared term"}""",
      )
      let res = waitFor executeNativeTool(call, ctx, SessionState(), @[])
      check res.handled
      check expected in res.text
      check forbidden notin res.text
