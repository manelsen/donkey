## Tests for execute_code input validation and fail-closed policy.

import std/[json, os, strutils, unittest]
import results
import donkey/app/tools/code_tools
import donkey/app/sandbox
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/tools/code_pure

let codeLog = newLogger("test.code", lvlError)

proc freshPaddock(name: string): string =
  result = getTempDir() / ("donkey_code_test_" & name & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

suite "execute_code config":

  test "none sandbox is refused":
    check codeConfigFromEnv(smNone, "docker").isErr

  test "oci and wasm modes map to code sandboxes":
    check codeConfigFromEnv(smOci, "docker").get().sandbox == cskOci
    check codeConfigFromEnv(smWasm, "wasmtime").get().sandbox == cskWasm

  test "environment limits are clamped":
    putEnv("DONKEY_CODE_TIMEOUT_SEC", "999")
    putEnv("DONKEY_CODE_MAX_OUTPUT_BYTES", "1")
    putEnv("DONKEY_CODE_MAX_SOURCE_BYTES", "99999999")
    defer:
      delEnv("DONKEY_CODE_TIMEOUT_SEC")
      delEnv("DONKEY_CODE_MAX_OUTPUT_BYTES")
      delEnv("DONKEY_CODE_MAX_SOURCE_BYTES")
    let cfg = codeConfigFromEnv(smOci, "docker").get()
    check cfg.timeoutSec == CodeMaxTimeoutSec
    check cfg.maxOutputBytes == CodeMinMaxOutputBytes
    check cfg.maxSourceBytes == CodeMaxMaxSourceBytes

  test "custom code image is used verbatim":
    putEnv("DONKEY_CODE_IMAGE", "python:3.12-slim")
    defer: delEnv("DONKEY_CODE_IMAGE")
    check codeConfigFromEnv(smOci, "docker").get().image ==
      "python:3.12-slim"

suite "execute_code input validation":

  test "requires a known language":
    let dir = freshPaddock("lang")
    defer: removeDir(dir)
    check parseCodeRequest(%*{"language": "ruby", "code": "x"}, dir).isErr
    check parseCodeRequest(%*{"code": "x"}, dir).isErr
    check parseCodeRequest(%*{"language": 42, "code": "x"}, dir).isErr
    check parseCodeRequest(%*{"language": "python", "code": 42}, dir).isErr
    check parseCodeRequest(%*{"language": "wasm", "wasm_path": 42}, dir).isErr

  test "requires source for text languages":
    let dir = freshPaddock("source")
    defer: removeDir(dir)
    check parseCodeRequest(%*{"language": "python"}, dir).isErr
    check parseCodeRequest(%*{"language": "python", "code": ""}, dir).isErr
    check parseCodeRequest(%*{"language": "python", "code": "print(1)"}, dir).isOk

  test "enforces the source cap":
    let dir = freshPaddock("cap")
    defer: removeDir(dir)
    let tooBig = repeat("x", CodeMinMaxSourceBytes + 1)
    check parseCodeRequest(%*{"language": "python", "code": tooBig},
                           dir, CodeMinMaxSourceBytes).isErr

  test "wasm requires a path inside the paddock":
    let dir = freshPaddock("wasm")
    defer: removeDir(dir)
    check parseCodeRequest(%*{"language": "wasm"}, dir).isErr
    check parseCodeRequest(%*{"language": "wasm", "wasm_path": "/etc/passwd"},
                           dir).isErr
    check parseCodeRequest(%*{"language": "wasm",
                              "wasm_path": "../outside.wasm"}, dir).isErr

  test "wasm symlink escape is rejected":
    let dir = freshPaddock("symlink")
    defer: removeDir(dir)
    let outside = dir & "_outside.wasm"
    defer: removeFile(outside)
    writeFile(outside, "not really wasm")
    createSymlink(outside, dir / "escape.wasm")
    let res = parseCodeRequest(%*{"language": "wasm",
                                  "wasm_path": "escape.wasm"}, dir)
    check res.isErr
    check "outside paddock" in res.error

  test "wasm rejects directories and oversized modules":
    let dir = freshPaddock("wasmfile")
    defer: removeDir(dir)
    createDir(dir / "module.wasm")
    check parseCodeRequest(%*{"language": "wasm",
                              "wasm_path": "module.wasm"}, dir).isErr

  test "timeout is clamped on input":
    let dir = freshPaddock("timeout")
    defer: removeDir(dir)
    let req = parseCodeRequest(%*{"language": "shell", "code": "echo hi",
                                  "timeout_sec": 9999}, dir).get()
    check req.timeoutSec == CodeMaxTimeoutSec
    let small = parseCodeRequest(%*{"language": "shell", "code": "echo hi",
                                    "timeout_sec": 0}, dir).get()
    check small.timeoutSec == CodeDefaultTimeoutSec

  test "mode and language mismatch fails without spawning":
    let dir = freshPaddock("mismatch")
    defer: removeDir(dir)
    let req = parseCodeRequest(%*{"language": "shell", "code": "echo hi"},
                               dir).get()
    let cfg = CodeRuntimeConfig(sandbox: cskWasm, runtimeCmd: "wasmtime",
                                timeoutSec: 1, maxOutputBytes: 1024)
    let res = runCodeRequest(req, cfg, dir, UserId("u"), ckCli, codeLog)
    check res.isErr
    check "wasm" in res.error
