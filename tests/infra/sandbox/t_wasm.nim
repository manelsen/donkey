## Tests for infra/sandbox/wasm — wasm3 embedded WASM sandbox.
##
## Replaces the previous wasmtime CLI-based implementation with
## in-process wasm3 runtime for zero external dependencies.

import std/[os, strutils, unittest]

import ../../../src/donkey/infra/sandbox/wasm
import ../../../src/donkey/infra/sandbox/limits
import ../../../src/donkey/core/pipeops

# ── Pure tests (no wasm binary needed) ────────────────────────────────────────

suite "infra/sandbox/wasm - WasmEngine":

  test "newWasmEngine creates engine with defaults":
    let engine = newWasmEngine()
    let s = $engine
    check s.contains("WasmEngine")
    check s.contains("wasm3")

  test "newWasmEngine with custom opts":
    let opts = wasmDefaults().withCpuLimit(cpuSeconds(60)).withMemLimit(memBytes(256 * 1024 * 1024))
    let engine = newWasmEngine(opts)
    let s = $engine
    check s.contains("60s")
    check s.contains("256MB")

  test "engineWithCpuLimit returns new engine":
    let engine = newWasmEngine()
    let engine2 = engine.engineWithCpuLimit(cpuSeconds(120))
    let s = $engine2
    check s.contains("120s")

  test "engineWithMemLimit returns new engine":
    let engine = newWasmEngine()
    let engine2 = engine.engineWithMemLimit(memBytes(64 * 1024 * 1024))
    let s = $engine2
    check s.contains("64MB")

  test "engineWithAllowedDirs returns new engine":
    let engine = newWasmEngine()
    let dirs = @["/tmp", "/home"]
    let engine2 = engine.engineWithAllowedDirs(dirs)
    let s = $engine2
    check s.contains("/tmp")

  test "$engine shows wasm3 and opts":
    let engine = newWasmEngine()
    let s = $engine
    check s.contains("WasmEngine")
    check s.contains("wasm3")

suite "infra/sandbox/wasm - WasmSandboxOpts":

  test "wasmDefaults returns sensible defaults":
    let opts = wasmDefaults()
    let s = $opts
    check s.contains("cpu=")
    check s.contains("mem=")

  test "sandboxWasmDefaults has cpu and mem limits":
    let opts = sandboxWasmDefaults()
    let s = $opts
    check s.contains("cpu=")
    check s.contains("mem=")

  test "sandboxWasmInteractive has longer timeout":
    let opts = sandboxWasmInteractive()
    let s = $opts
    check s.contains("300s") or s.contains("5m")

  test "sandboxWasmQuick has short timeout":
    let opts = sandboxWasmQuick()
    let s = $opts
    check s.contains("10s")

  test "withCpuLimit returns new opts":
    let opts = wasmDefaults()
    let opts2 = opts.withCpuLimit(cpuSeconds(45))
    let s = $opts2
    check s.contains("45s")

  test "withMemLimit returns new opts":
    let opts = wasmDefaults()
    let opts2 = opts.withMemLimit(memBytes(256 * 1024 * 1024))
    let s = $opts2
    check s.contains("256MB")

  test "withAllowedDirs returns new opts":
    let opts = wasmDefaults()
    let dirs = @["/tmp"]
    let opts2 = opts.withAllowedDirs(dirs)
    let s = $opts2
    check s.contains("/tmp")

  test "$opts shows unrestricted when no limits":
    let opts = WasmSandboxOpts(cpuLimit: CpuLimit(0), memLimit: MemLimit(0), allowedDirs: @[])
    let s = $opts
    check s.contains("unrestricted")

suite "infra/sandbox/wasm - WasmCallResult":

  test "$result shows all fields":
    let res = WasmCallResult(exitCode: 0, stdout: "hello", stderr: "", timedOut: false, success: true)
    let s = $res
    check s.contains("exitCode=0")
    check s.contains("success=true")
    check s.contains("stdout.len=5")

  test "$result shows timedOut=true":
    let res = WasmCallResult(exitCode: 255, stdout: "", stderr: "fuel exhausted", timedOut: true, success: false)
    let s = $res
    check s.contains("timedOut=true")

  test "$result shows failed call":
    let res = WasmCallResult(exitCode: 1, stdout: "", stderr: "error", timedOut: false, success: false)
    let s = $res
    check s.contains("success=false")

suite "infra/sandbox/wasm - WasmValidationResult":

  test "$validResult shows valid=true":
    let res = WasmValidationResult(valid: true)
    let s = $res
    check s.contains("valid=true")

  test "$invalidResult shows error":
    let res = WasmValidationResult(valid: false, error: "invalid magic")
    let s = $res
    check s.contains("valid=false")
    check s.contains("invalid magic")

suite "infra/sandbox/wasm - validateWasmFile":

  test "validateWasmFile returns error for non-existent file":
    let res = validateWasmFile("/nonexistent/path/to/file.wasm")
    check res.isOk
    check res.value.valid == false
    check res.value.error.contains("not found")

  test "validateWasmFile returns error for directory":
    let tmpDir = getTempDir()
    let res = validateWasmFile(tmpDir)
    check res.isOk
    check res.value.valid == false
    check res.value.error.len > 0

  test "validateWasmFile checks magic bytes for invalid file":
    let tmpPath = getTempDir() / "invalid.wasm"
    writeFile(tmpPath, "not a wasm file")
    defer: removeFile(tmpPath)

    let res = validateWasmFile(tmpPath)
    check res.isOk
    check res.value.valid == false
    check res.value.error.len > 0

suite "infra/sandbox/wasm - loadModule":

  test "loadModule returns error for non-existent file":
    let engine = newWasmEngine()
    let res = engine.loadModule("/nonexistent/test.wasm")
    check res.isErr
    check res.error.len > 0

  test "loadModule returns error for invalid wasm":
    let tmpPath = getTempDir() / "bad_load.wasm"
    writeFile(tmpPath, "not wasm")
    defer: removeFile(tmpPath)

    let engine = newWasmEngine()
    let res = engine.loadModule(tmpPath)
    check res.isErr

suite "infra/sandbox/wasm - error messages":

  test "wasmEngineError formats correctly":
    let msg = wasmEngineError("binary not found")
    check msg.contains("WasmEngine")
    check msg.contains("binary not found")

  test "wasmModuleError formats correctly":
    let msg = wasmModuleError("invalid file")
    check msg.contains("WasmModule")
    check msg.contains("invalid file")

  test "wasmInstanceError formats correctly":
    let msg = wasmInstanceError("not instantiated")
    check msg.contains("WasmInstance")
    check msg.contains("not instantiated")

suite "infra/sandbox/wasm - engineWithOpts":

  test "engineWithOpts replaces opts":
    let engine = newWasmEngine()
    let newOpts = sandboxWasmInteractive()
    let engine2 = engine.engineWithOpts(newOpts)
    let s = $engine2
    check s.contains("300s") or s.contains("5m")

# ── Integration tests (require wasm3 runtime) ────────────────────────────────

const fixturesDir = currentSourcePath().parentDir.parentDir.parentDir / "fixtures"

suite "infra/sandbox/wasm - wasm3 integration":

  test "loadModuleFromBytes succeeds for valid wasm bytes":
    let wasmData = readFile(fixturesDir / "fib32.wasm")
    let engine = newWasmEngine()
    let res = engine.loadModuleFromBytes(wasmData, "fib32")
    check res.isOk
    check res.value.source.len > 0

  test "loadModule succeeds for wasm file":
    let engine = newWasmEngine()
    let res = engine.loadModule(fixturesDir / "fib32.wasm")
    check res.isOk
    check res.value.name == "fib32"

  test "instantiate succeeds for loaded module":
    let wasmData = readFile(fixturesDir / "fib32.wasm")
    let engine = newWasmEngine()
    let modRes = engine.loadModuleFromBytes(wasmData, "fib32")
    check modRes.isOk
    let instRes = engine.instantiate(modRes.value)
    check instRes.isOk

  test "callVoid returns error for function with wrong signature":
    let wasmData = readFile(fixturesDir / "fib32.wasm")
    let engine = newWasmEngine()
    let modRes = engine.loadModuleFromBytes(wasmData, "fib32")
    check modRes.isOk
    var instRes = engine.instantiate(modRes.value)
    check instRes.isOk
    var inst = instRes.value
    # fib requires i32 arg, calling as void should fail
    let callRes = inst.callVoid("fib")
    check callRes.isErr
    check callRes.error.contains("argument count mismatch")

  test "callVoid returns error for unknown function":
    let wasmData = readFile(fixturesDir / "fib32.wasm")
    let engine = newWasmEngine()
    let modRes = engine.loadModuleFromBytes(wasmData, "fib32")
    var instRes = engine.instantiate(modRes.value)
    var inst = instRes.value
    let callRes = inst.callVoid("nonexistent")
    check callRes.isErr

  test "loadAndCall returns error for wrong signature":
    let engine = newWasmEngine()
    let callRes = engine.loadAndCall(fixturesDir / "fib32.wasm", "fib")
    check callRes.isErr
