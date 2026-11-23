## The process adapter on real processes: output, exit codes, environment,
## working directory and the timeout.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/adapters/process/process_adapter

proc runTests*() =
  let process = newProcessAdapter()
  suite "process adapter":
    test "a shell command gives its output and exit code":
      let r = process.run(shellSpec("echo out; echo err >&2; exit 3")).get
      check "out" in r.output
      check "err" in r.output
      check r.exitCode == 3

    test "argv runs without a shell":
      let r = process.run(argvSpec(@["printf", "%s", "a;b"])).get
      check r.output == "a;b"
      check r.exitCode == 0

    test "the working directory is used and can be created":
      let dir = getTempDir() / "donkey_process_wd" / "nested"
      removeDir(getTempDir() / "donkey_process_wd")
      let r = process.run(ProcessSpec(command: "pwd", workingDir: dir,
                                      createWorkingDir: true)).get
      check r.output.strip == dir

    test "a replaced environment holds only what was given":
      let r = process.run(ProcessSpec(
        argv: @["/usr/bin/env"], env: @[("ONLY", "this")], replaceEnv: true)).get
      check r.output.strip == "ONLY=this"

    test "a process past its timeout is killed and the run is an error":
      let r = process.run(argvSpec(@["sleep", "5"], timeoutMs = 100))
      check r.isErr
      check "timed out" in r.error

    test "a process within its timeout gives its output":
      let r = process.run(argvSpec(@["echo", "quick"], timeoutMs = 5000)).get
      check r.output.strip == "quick"

    test "a program that does not exist is an error, not an exception":
      check process.run(argvSpec(@["/nonexistent/donkey-binary"])).isErr

    test "a passthrough run gives the exit code and no output":
      let r = process.run(ProcessSpec(command: "exit 4", passthrough: true)).get
      check r.exitCode == 4
      check r.output == ""

    test "an empty port fails closed":
      check ProcessRuntimePort().orUnavailable.run(shellSpec("true")).isErr

when isMainModule:
  runTests()
