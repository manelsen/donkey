## Tests for the bounded process runner used by execute_code.

import std/[os, strutils, times, unittest]
when defined(linux):
  import std/posix
import chronos
import donkey/core/pipeops
import donkey/domain/tools/code_pure
import donkey/infra/sandbox/code_runner

when defined(linux):
  proc tick(counter: ptr int) {.async.} =
    for _ in 0 ..< 5:
      await sleepAsync(100)
      inc counter[]

  proc cancelAfter(fut: Future[Result[CodeRunResult, string]];
                   ms: int) {.async.} =
    await sleepAsync(ms)
    await fut.cancelAndWait()

  suite "execute_code bounded runner":

    test "captures output and exit code":
      let res = runBoundedProcess(@["sh", "-c", "printf hello"], 5, 1024).get()
      check res.output == "hello"
      check res.exitCode == 0
      check not res.timedOut
      check not res.truncated

    test "preserves non-zero exit codes":
      let res = runBoundedProcess(@["sh", "-c", "printf bad; exit 7"], 5, 1024).get()
      check res.output.strip() == "bad"
      check res.exitCode == 7
      check not res.timedOut

    test "caps an output bomb and terminates the child":
      let started = epochTime()
      let res = runBoundedProcess(@["sh", "-c", "yes x"], 10, 1024).get()
      let elapsed = epochTime() - started
      check res.truncated
      check res.output.len <= 1024 + len("\n[output truncated]")
      check elapsed < 5.0

    test "enforces the wall-clock timeout":
      let started = epochTime()
      let res = runBoundedProcess(@["sh", "-c", "sleep 30"], 1, 1024).get()
      let elapsed = epochTime() - started
      check res.timedOut
      check res.exitCode in {124, 137}
      check elapsed < 5.0

    test "empty argv fails closed":
      check runBoundedProcess(@[], 1, 1024).isErr

    test "WASI with linear memory fits the address-space cap":
      if findExe("wasmtime").len == 0:
        echo "wasmtime not installed; skipping WASI memory smoke"
      else:
        let workspace = getTempDir() / ("donkey-wasm-mem-" & $getCurrentProcessId())
        removeDir(workspace)
        createDir(workspace)
        defer: removeDir(workspace)
        writeFile(workspace / "mem.wat", """
(module
  (memory (export "memory") 1)
  (func (export "_start")
    (i32.store (i32.const 0) (i32.const 42))))
""")
        let res = runWasmCode(workspace, workspace / "mem.wat", 5, 1024)
        check res.isOk
        check res.get().exitCode == 0

    test "fileSha256 hashes the executed artifact":
      let path = getTempDir() / ("donkey-sha-" & $getCurrentProcessId())
      writeFile(path, "hello")
      defer: removeFile(path)
      check fileSha256(path).get() ==
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    test "async runner keeps the Chronos loop responsive":
      var counter = 0
      let started = epochTime()
      let runFut = runBoundedProcessAsync(@["sh", "-c", "sleep 1"], 5, 1024)
      let tickFut = tick(addr counter)
      waitFor tickFut
      let tickElapsed = epochTime() - started
      check counter >= 3
      check tickElapsed < 0.9
      check not finished(runFut)
      let run = waitFor runFut
      check run.isOk

    test "cancellation kills the child and propagates":
      let started = epochTime()
      let fut = runBoundedProcessAsync(@["sh", "-c", "sleep 30"], 60, 1024)
      waitFor cancelAfter(fut, 200)
      check cancelled(fut)
      check epochTime() - started < 5.0

    test "cancellation after EOF still propagates":
      let started = epochTime()
      let fut = runBoundedProcessAsync(
        @["sh", "-c", "exec 1>&- 2>&-; sleep 30"], 60, 1024)
      waitFor cancelAfter(fut, 500)
      check cancelled(fut)
      check epochTime() - started < 5.0

    test "cancellation kills descendants in the timeout group":
      let pidFile = getTempDir() / ("donkey-child-" & $getCurrentProcessId())
      removeFile(pidFile)
      defer: removeFile(pidFile)
      let code = "echo $$ > " & quoteShell(pidFile) & "; exec sleep 30"
      let fut = runBoundedProcessAsync(@["sh", "-c", code], 60, 1024)
      var found = false
      for _ in 0 ..< 40:
        if fileExists(pidFile):
          found = true
          break
        sleep(25)
      check found
      let childPid = parseInt(readFile(pidFile).strip())
      waitFor cancelAfter(fut, 200)
      check cancelled(fut)
      var alive = true
      for _ in 0 ..< 40:
        if posix.kill(Pid(childPid), 0.cint) != 0:
          alive = false
          break
        sleep(25)
      check not alive

    test "missing container runtime fails closed without spawning":
      let res = runOciCode("/nonexistent/docker", "alpine", "/tmp", 1, 1,
                           clShell, "echo hi", 1, 1024)
      check res.isErr
      check "not found" in res.error
