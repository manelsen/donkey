## Tests for the bounded process runner used by execute_code.

import std/[os, strutils, times, unittest]
import results
import donkey/domain/tools/code_pure
import donkey/infra/sandbox/code_runner

when defined(linux):
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

    test "missing container runtime fails closed without spawning":
      let res = runOciCode("/nonexistent/docker", "alpine", "/tmp", 1, 1,
                           clShell, "echo hi", 1, 1024)
      check res.isErr
      check "not found" in res.error
