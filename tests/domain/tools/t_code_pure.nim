## Tests for pure execute_code policy and argv construction.

import std/[options, strutils, unittest]
import results
import donkey/domain/tools/code_pure

suite "execute_code pure policy":

  test "parses supported languages and aliases":
    check parseCodeLanguage("python").get() == clPython
    check parseCodeLanguage("python3").get() == clPython
    check parseCodeLanguage("js").get() == clJavaScript
    check parseCodeLanguage("bash").get() == clShell
    check parseCodeLanguage("wasi").get() == clWasm
    check parseCodeLanguage("ruby").isNone

  test "clamps timeout, output and source limits":
    check clampCodeTimeoutSec(0) == CodeDefaultTimeoutSec
    check clampCodeTimeoutSec(-1) == CodeDefaultTimeoutSec
    check clampCodeTimeoutSec(1) == CodeMinTimeoutSec
    check clampCodeTimeoutSec(999) == CodeMaxTimeoutSec
    check clampCodeMaxOutputBytes(0) == CodeDefaultMaxOutputBytes
    check clampCodeMaxOutputBytes(1) == CodeMinMaxOutputBytes
    check clampCodeMaxOutputBytes(999_999_999) == CodeMaxMaxOutputBytes
    check clampCodeMaxSourceBytes(0) == CodeDefaultMaxSourceBytes
    check clampCodeMaxSourceBytes(1) == CodeMinMaxSourceBytes
    check clampCodeMaxSourceBytes(999_999_999) == CodeMaxMaxSourceBytes

  test "parses env-style limits without raising":
    check parseCodeTimeoutSec("") == CodeDefaultTimeoutSec
    check parseCodeTimeoutSec("bogus") == CodeDefaultTimeoutSec
    check parseCodeTimeoutSec("-5") == CodeDefaultTimeoutSec
    check parseCodeTimeoutSec("15") == 15
    check parseCodeMaxOutputBytes("4096") == 4096
    check parseCodeMaxSourceBytes("4096") == 4096

  test "validates source size and wasm shape":
    check validateCodeSource(clPython, "", 1024).isErr
    check validateCodeSource(clPython, "print(1)", 1024).isOk
    check validateCodeSource(clPython, "a\0b", 1024).isErr
    check validateCodeSource(clPython, repeat("x", 2048), 1024).isErr
    check validateCodeSource(clWasm, "", 1024).isOk
    check validateCodeSource(clWasm, "ignored", 1024).isErr

  test "rejects unsafe workspace mounts":
    check codeWorkspaceMountAllowed("/home/u/paddock")
    check not codeWorkspaceMountAllowed("")
    check not codeWorkspaceMountAllowed("/home/u/pad:dock")
    check not codeWorkspaceMountAllowed("/home/u/pad\0dock")

  test "OCI argv carries every isolation flag":
    let argv = buildOciCodeArgv(
      "docker", "python:3.12-alpine", "/home/u/paddock", 1000, 1000,
      clPython, "print('hello')", "donkey-code-1-2-3")
    check argv.len > 20
    for flag in ["run", "--rm", "--name", "donkey-code-1-2-3",
                 "--network=none", "--read-only", "--cap-drop=ALL",
                 "--security-opt", "no-new-privileges", "--pids-limit=128",
                 "--memory=512m", "--memory-swap=512m", "--cpus=1",
                 "--ulimit", "nofile=256:256", "--init", "--stop-timeout=1",
                 "--workdir", "/workspace", "-v",
                 "/home/u/paddock:/workspace:rw,z", "--user", "1000:1000",
                 "python:3.12-alpine", "python3", "-I", "-B", "-c",
                 "print('hello')"]:
      check flag in argv
    check "--privileged" notin argv
    check "--network=host" notin argv

  test "code is a separate argv entry, never a host shell string":
    let code = "print('x'); import os; os.system('rm -rf /')"
    let argv = buildOciCodeArgv(
      "docker", "python:3.12-alpine", "/tmp/p", -1, -1,
      clPython, code, "name")
    check argv[^1] == code
    check argv[^2] == "-c"
    check "--user" notin argv

  test "language argv mapping":
    check interpreterArgv(clPython, "x") == @["python3", "-I", "-B", "-c", "x"]
    check interpreterArgv(clJavaScript, "x") == @["node", "--no-warnings", "-e", "x"]
    check interpreterArgv(clShell, "x") == @["sh", "-c", "x"]
    check interpreterArgv(clWasm, "x").len == 0

  test "default images match the runtime":
    check defaultCodeImage(clPython) == CodeDefaultImage
    check defaultCodeImage(clShell) == CodeDefaultImage
    check defaultCodeImage(clJavaScript) == CodeDefaultJsImage
    check defaultCodeImage(clWasm).len == 0

  test "WASI argv grants only the workspace and scratch":
    let argv = buildWasmCodeArgv(
      "/usr/bin/wasmtime", "/home/u/paddock", "/home/u/paddock/x.wasm",
      "/tmp/donkey-code-scratch-1")
    check argv == @[
      "/usr/bin/wasmtime", "run",
      "--dir=/home/u/paddock",
      "--dir=/tmp/donkey-code-scratch-1::/tmp",
      "--", "/home/u/paddock/x.wasm",
    ]
    check "--tcplisten" notin argv
    check "--udp" notin argv

  test "output cap is byte-exact and marks truncation":
    let exactText = repeat("a", CodeMinMaxOutputBytes)
    let exact = capExecutionOutput(exactText, CodeMinMaxOutputBytes)
    check exact.text == exactText
    check not exact.truncated
    let over = capExecutionOutput(exactText & "b", CodeMinMaxOutputBytes)
    check over.text.startsWith(exactText)
    check "[output truncated]" in over.text
    check over.truncated

  test "result formatting preserves exit and timeout markers":
    check formatCodeResult("hello\n", 0, false, false) == "hello"
    check formatCodeResult("bad\n", 7, false, false) == "bad\n[exit 7]"
    check formatCodeResult("slow\n", 124, true, false) == "slow\n[timeout]"
    check formatCodeResult("", 0, false, false) == "[exit 0]"

  test "container names are argv-safe":
    let name = buildContainerName(123, 456, 7)
    check name == "donkey-code-123-456-7"
    for c in name:
      check c.isAlphaNumeric or c == '-'

  test "OCI infrastructure errors are distinguishable from code exits":
    check ociInfrastructureFailure("Cannot connect to the Docker daemon at ...")
    check ociInfrastructureFailure("pull access denied for nope")
    check not ociInfrastructureFailure("Traceback: KeyError")
