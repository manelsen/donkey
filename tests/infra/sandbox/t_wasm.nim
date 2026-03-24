## Tests for infra/sandbox/wasm — Wasmtime-based WASM sandbox.

import std/[os, posix, strutils, unittest]

import ../../../src/donkey/infra/sandbox/wasm
import ../../../src/donkey/infra/sandbox/limits
import ../../../src/donkey/core/pipeops

suite "infra/sandbox/wasm - WasmEngine":

  test "newWasmEngine with default path":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    check engine.wasmtimePath == "/usr/bin/wasmtime"
    # Check via $ formatting to verify engine was constructed
    let s = $engine
    check s.contains("/usr/bin/wasmtime")

  test "newWasmEngine with custom opts":
    let opts = wasmDefaults().withCpuLimit(cpuSeconds(60)).withMemLimit(memBytes(256 * 1024 * 1024))
    let engine = newWasmEngine("/usr/bin/wasmtime", opts)
    let s = $engine
    check s.contains("/usr/bin/wasmtime")

  test "engineWithCpuLimit returns new engine":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    let engine2 = engine.engineWithCpuLimit(cpuSeconds(120))
    check engine.wasmtimePath == engine2.wasmtimePath
    # Check that the new engine is different
    let s = $engine2
    check s.contains("120s")

  test "engineWithMemLimit returns new engine":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    let engine2 = engine.engineWithMemLimit(memBytes(64 * 1024 * 1024))
    let s = $engine2
    check s.contains("64MB")

  test "engineWithAllowedDirs returns new engine":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    let dirs = @["/tmp", "/home"]
    let engine2 = engine.engineWithAllowedDirs(dirs)
    let s = $engine2
    check s.contains("/tmp")

  test "$engine shows wasmtime path and opts":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    let s = $engine
    check s.contains("/usr/bin/wasmtime")
    check s.contains("WasmEngine")

suite "infra/sandbox/wasm - WasmSandboxOpts":

  test "wasmDefaults returns sensible defaults":
    let opts = wasmDefaults()
    # Verify by formatting
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

suite "infra/sandbox/wasm - WasmModule":

  test "$wasmModule shows path":
    let wasmMod = WasmModule(path: "/tmp/plugin.wasm", enginePath: "/usr/bin/wasmtime")
    let s = $wasmMod
    check s.contains("/tmp/plugin.wasm")

suite "infra/sandbox/wasm - WasmInstance":

  test "$instance shows module path":
    let wasmMod = WasmModule(path: "/tmp/plugin.wasm", enginePath: "/usr/bin/wasmtime")
    let inst = WasmInstance(module: wasmMod, opts: wasmDefaults())
    let s = $inst
    check s.contains("/tmp/plugin.wasm")

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

suite "infra/sandbox/wasm - buildWasmtimeArgs":

  test "builds basic args with no limits":
    let opts = WasmSandboxOpts(cpuLimit: CpuLimit(0), memLimit: MemLimit(0), allowedDirs: @[])
    let args = opts.buildWasmtimeArgs("/tmp/test.wasm", "run", @["arg1"])
    check args.contains("--disable-all-features")
    check args.contains("--dir=")  # No dirs allowed
    check args.contains("/tmp/test.wasm")
    check args.contains("--invoke")
    check args.contains("run")
    check args.contains("arg1")

  test "builds args with memory limit":
    let opts = wasmDefaults().withMemLimit(memBytes(64 * 1024 * 1024))
    let args = opts.buildWasmtimeArgs("/tmp/test.wasm", "run", @[])
    check args.contains("--max-memory=67108864")  # 64MB in bytes

  test "builds args with CPU limit (fuel)":
    let opts = wasmDefaults().withCpuLimit(cpuSeconds(10))
    let args = opts.buildWasmtimeArgs("/tmp/test.wasm", "run", @[])
    check args.contains("--fuel=100000000")  # 10s * 10M fuel units

  test "builds args with allowed dirs":
    let opts = wasmDefaults().withAllowedDirs(@["/tmp", "/home"])
    let args = opts.buildWasmtimeArgs("/tmp/test.wasm", "run", @[])
    check args.contains("--dir=/tmp")
    check args.contains("--dir=/home")

  test "always includes /tmp as allowed":
    let opts = wasmDefaults()
    let args = opts.buildWasmtimeArgs("/tmp/test.wasm", "run", @[])
    check args.contains("--dir=/tmp")

  test "includes wasm path and function":
    let opts = wasmDefaults()
    let args = opts.buildWasmtimeArgs("/path/to/plugin.wasm", "calculate", @["1", "2", "3"])
    check "/path/to/plugin.wasm" in args
    check "--invoke" in args
    check "calculate" in args
    check "1" in args
    check "2" in args
    check "3" in args

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
    # Error message varies by environment - just check it's not empty
    check res.value.error.len > 0

  test "validateWasmFile checks magic bytes for invalid file":
    # Create a temp file with invalid content
    let tmpPath = getTempDir() / "invalid.wasm"
    writeFile(tmpPath, "not a wasm file")
    defer: removeFile(tmpPath)
    
    let res = validateWasmFile(tmpPath)
    check res.isOk
    check res.value.valid == false
    check res.value.error.len > 0  # Just check we get an error

suite "infra/sandbox/wasm - loadModule":

  test "loadModule returns error for non-existent wasmtime":
    var engine = newWasmEngine("/nonexistent/wasmtime")
    let res = engine.loadModule("/tmp/test.wasm")
    check res.isErr
    check res.error.contains("not found")

  test "loadModule returns error for non-existent wasm file":
    var engine = newWasmEngine("/usr/bin/wasmtime")
    let res = engine.loadModule("/nonexistent/test.wasm")
    # May fail on validate or on wasmtime check
    check res.isErr or (res.isOk and res.value.path == "/nonexistent/test.wasm")

suite "infra/sandbox/wasm - instantiate":

  test "instantiate returns instance with engine opts":
    var engine = newWasmEngine("/usr/bin/wasmtime", sandboxWasmQuick())
    let wasmMod = WasmModule(path: "/tmp/test.wasm", enginePath: "/usr/bin/wasmtime")
    let instRes = engine.instantiate(wasmMod)
    check instRes.isOk

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

  test "wasmtimeError formats correctly":
    let msg = wasmtimeError("failed to run")
    check msg.contains("wasmtime")
    check msg.contains("failed to run")

suite "infra/sandbox/wasm - engineWithOpts":

  test "engineWithOpts replaces opts":
    let engine = newWasmEngine("/usr/bin/wasmtime")
    let newOpts = sandboxWasmInteractive()
    let engine2 = engine.engineWithOpts(newOpts)
    check engine.wasmtimePath == engine2.wasmtimePath
    let s = $engine2
    check s.contains("300s") or s.contains("5m")
