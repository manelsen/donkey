## infra/sandbox/wasm — wasm3 embedded WASM sandbox for untrusted plugin execution.
##
## Uses the wasm3 interpreter compiled directly into the Donkey binary.
## No external runtime (wasmtime) required — zero subprocess overhead.
## WASI support enabled via -d:wasm3HasWasi (set in config.nims).
##
## Usage:
##   let engine = newWasmEngine()
##   let modResult = engine.loadModule(readFile("plugin.wasm"))
##   if modResult.isErr:
##     echo "load failed: " & modResult.error
##     return
##   let inst = engine.instantiate(modResult.value)
##   if inst.isErr:
##     echo "instantiate failed: " & inst.error
##     return
##   var instance = inst.value
##   let result = instance.callVoid("run").valueOr:
##     echo "call failed: " & error
##     return
##   echo "output: " & result.stdout
##
## All functions return Result[T, string] so callers decide what to do on error.

import std/[os, posix, strutils]

import wasm3

import ../../core/pipeops
import ./limits

export pipeops

# ── Types ─────────────────────────────────────────────────────────────────────

type
  WasmEngine* = object
    ## Engine configuration for wasm3-based WASM execution.
    opts*: WasmSandboxOpts

  WasmSandboxOpts* = object
    ## Sandbox options for WASM execution.
    cpuLimit*: CpuLimit     ## CPU time limit (0 = unlimited).
    memLimit*: MemLimit     ## Memory limit in bytes (0 = unlimited).
    allowedDirs*: seq[string] ## Directories the plugin can access (empty = none).

  WasmModule* = object
    ## Loaded WASM module (raw bytes) ready for instantiation.
    source*: string         ## WASM bytecode.
    name*: string           ## Module name (derived from filename or "module").

  WasmInstance* = object
    ## Instantiated WASM module with its own wasm3 runtime.
    env*: WasmEnv           ## wasm3 environment (owns the runtime).
    module*: WasmModule     ## Source module reference.
    opts*: WasmSandboxOpts  ## Sandbox options for this instance.

  WasmCallResult* = object
    ## Result of a WASM function call.
    exitCode*: int
    stdout*: string
    stderr*: string
    timedOut*: bool
    success*: bool

  WasmValidationResult* = object
    ## Result of WASM file validation.
    valid*: bool
    error*: string          ## Error message if invalid.

# ── Error constructors ───────────────────────────────────────────────────────

func wasmEngineError*(msg: string): string = "WasmEngine: " & msg
func wasmModuleError*(msg: string): string = "WasmModule: " & msg
func wasmInstanceError*(msg: string): string = "WasmInstance: " & msg
func wasmRuntimeError*(msg: string): string = "wasm3: " & msg

# ── Engine constructors ───────────────────────────────────────────────────────

func newWasmEngine*(): WasmEngine =
  WasmEngine(opts: WasmSandboxOpts(
    cpuLimit: cpuSeconds(30),
    memLimit: memBytes(128 * 1024 * 1024),
    allowedDirs: @[]
  ))

func newWasmEngine*(opts: WasmSandboxOpts): WasmEngine =
  WasmEngine(opts: opts)

# ── Sandbox option constructors ───────────────────────────────────────────────

func wasmDefaults*(): WasmSandboxOpts =
  WasmSandboxOpts(
    cpuLimit: cpuSeconds(30),
    memLimit: memBytes(128 * 1024 * 1024),
    allowedDirs: @[]
  )

func withCpuLimit*(opts: WasmSandboxOpts; limit: CpuLimit): WasmSandboxOpts =
  result = opts; result.cpuLimit = limit

func withMemLimit*(opts: WasmSandboxOpts; limit: MemLimit): WasmSandboxOpts =
  result = opts; result.memLimit = limit

func withAllowedDirs*(opts: WasmSandboxOpts; dirs: seq[string]): WasmSandboxOpts =
  result = opts; result.allowedDirs = dirs

func sandboxWasmDefaults*(): WasmSandboxOpts =
  wasmDefaults()
    .withCpuLimit(cpuSeconds(30))
    .withMemLimit(memBytes(128 * 1024 * 1024))

func sandboxWasmInteractive*(): WasmSandboxOpts =
  wasmDefaults()
    .withCpuLimit(cpuSeconds(300))
    .withMemLimit(memBytes(512 * 1024 * 1024))

func sandboxWasmQuick*(): WasmSandboxOpts =
  wasmDefaults()
    .withCpuLimit(cpuSeconds(10))
    .withMemLimit(memBytes(64 * 1024 * 1024))

# ── Formatting ─────────────────────────────────────────────────────────────────

func formatMem*(bytes: int64): string =
  if bytes <= 0: "unlimited"
  elif bytes >= 1024 * 1024 * 1024: $(bytes div (1024 * 1024 * 1024)) & "GB"
  elif bytes >= 1024 * 1024: $(bytes div (1024 * 1024)) & "MB"
  elif bytes >= 1024: $(bytes div 1024) & "KB"
  else: $bytes & "B"

func `$`*(opts: WasmSandboxOpts): string =
  var parts: seq[string] = @[]
  if opts.cpuLimit.int64 > 0:
    parts.add("cpu=" & $opts.cpuLimit)
  if opts.memLimit.int64 > 0:
    parts.add("mem=" & formatMem(opts.memLimit.int64))
  if opts.allowedDirs.len > 0:
    parts.add("dirs=" & opts.allowedDirs.join(","))
  if parts.len == 0:
    "WasmSandboxOpts(unrestricted)"
  else:
    "WasmSandboxOpts(" & parts.join(", ") & ")"

func `$`*(engine: WasmEngine): string =
  "WasmEngine(wasm3, " & $engine.opts & ")"

func `$`*(m: WasmModule): string =
  "WasmModule(name=" & m.name & ", size=" & $m.source.len & ")"

func `$`*(inst: WasmInstance): string =
  "WasmInstance(" & $inst.module & ")"

func `$`*(res: WasmCallResult): string =
  "WasmCallResult(exitCode=" & $res.exitCode &
    ", timedOut=" & (if res.timedOut: "true" else: "false") &
    ", success=" & (if res.success: "true" else: "false") &
    ", stdout.len=" & $res.stdout.len &
    ", stderr.len=" & $res.stderr.len & ")"

func `$`*(res: WasmValidationResult): string =
  if res.valid:
    "WasmValidationResult(valid=true)"
  else:
    "WasmValidationResult(valid=false, error=" & res.error & ")"

# ── Validate WASM binary ───────────────────────────────────────────────────────

proc validateWasmFile*(wasmPath: string): Result[WasmValidationResult, string] =
  ## Validate a WASM file without executing it.
  ## Checks file existence and WASM magic bytes.

  if not wasmPath.fileExists:
    return ok(WasmValidationResult(valid: false, error: "File not found: " & wasmPath))

  if wasmPath.dirExists:
    return ok(WasmValidationResult(valid: false, error: "Path is a directory, not a file: " & wasmPath))

  # Check magic bytes: 0x00 0x61 0x73 0x6d ("\0asm")
  let file = open(wasmPath, fmRead)
  defer: close(file)
  var header: array[8, char]
  let bytesRead = file.readChars(header.toOpenArray(0, 7))
  if bytesRead < 4:
    return ok(WasmValidationResult(valid: false, error: "File too small to be a valid WASM binary"))

  if header[0] == '\0' and header[1] == 'a' and header[2] == 's' and header[3] == 'm':
    return ok(WasmValidationResult(valid: true))
  else:
    return ok(WasmValidationResult(valid: false, error: "Invalid WASM magic bytes"))

proc validateWasmBytes*(data: openArray[char]): Result[WasmValidationResult, string] =
  ## Validate WASM bytecode in memory.
  if data.len < 4:
    return ok(WasmValidationResult(valid: false, error: "Data too small to be a valid WASM binary"))

  if data[0] == '\0' and data[1] == 'a' and data[2] == 's' and data[3] == 'm':
    ok(WasmValidationResult(valid: true))
  else:
    ok(WasmValidationResult(valid: false, error: "Invalid WASM magic bytes"))

# ── Load WASM module ───────────────────────────────────────────────────────────

proc loadModule*(engine: WasmEngine; wasmPath: string): Result[WasmModule, string] =
  ## Load a WASM module from file. Does not instantiate it.
  let validRes = validateWasmFile(wasmPath)
  if validRes.isErr:
    return err(wasmModuleError("validation failed: " & validRes.error))
  if not validRes.value.valid:
    return err(wasmModuleError("invalid WASM: " & validRes.value.error))

  let name = wasmPath.extractFilename.changeFileExt("")
  try:
    let source = readFile(wasmPath)
    ok(WasmModule(source: source, name: name))
  except CatchableError as e:
    err(wasmModuleError("failed to read file: " & e.msg))

proc loadModuleFromBytes*(engine: WasmEngine; data: sink string;
                          name: string = "module"): Result[WasmModule, string] =
  ## Load a WASM module from raw bytes. Does not instantiate it.
  let validRes = validateWasmBytes(data)
  if validRes.isErr:
    return err(wasmModuleError("validation failed: " & validRes.error))
  if not validRes.value.valid:
    return err(wasmModuleError("invalid WASM: " & validRes.value.error))

  ok(WasmModule(source: data, name: name))

# ── Instantiate WASM module ──────────────────────────────────────────────────

proc instantiate*(engine: WasmEngine; m: WasmModule): Result[WasmInstance, string] =
  ## Create an instance of a loaded module.
  ## Each instance gets its own wasm3 runtime (isolated execution).
  try:
    let stackSize = if engine.opts.memLimit.int64 > 0:
      min(engine.opts.memLimit.int64, int64(high(uint32))).uint32
    else:
      high(uint16)

    let env = loadWasmEnv(m.source, stackSize = stackSize)
    ok(WasmInstance(env: env, module: m, opts: engine.opts))
  except WasmError as e:
    err(wasmInstanceError("failed to instantiate: " & e.msg))
  except CatchableError as e:
    err(wasmInstanceError("failed to instantiate: " & e.msg))

# ── Output capture helpers ────────────────────────────────────────────────────

proc captureAndCall(inst: var WasmInstance; funcName: string): Result[WasmCallResult, string] =
  ## Call a wasm function with stdout/stderr capture via pipe redirection.
  ## This works because wasm3's WASI implementation writes to real OS file descriptors.

  # Create pipes for stdout and stderr capture
  var stdoutPipe: array[2, cint]
  var stderrPipe: array[2, cint]

  if pipe(stdoutPipe) != 0:
    return err(wasmRuntimeError("failed to create stdout pipe"))
  if pipe(stderrPipe) != 0:
    discard close(stdoutPipe[0])
    discard close(stdoutPipe[1])
    return err(wasmRuntimeError("failed to create stderr pipe"))

  # Save original file descriptors
  let origStdout = dup(STDOUT_FILENO)
  let origStderr = dup(STDERR_FILENO)

  if origStdout < 0 or origStderr < 0:
    discard close(stdoutPipe[0]); discard close(stdoutPipe[1])
    discard close(stderrPipe[0]); discard close(stderrPipe[1])
    return err(wasmRuntimeError("failed to save original file descriptors"))

  # Redirect stdout/stderr to pipes
  discard dup2(stdoutPipe[1], STDOUT_FILENO)
  discard dup2(stderrPipe[1], STDERR_FILENO)

  # Close write ends (they're now duplicated to STDOUT/STDERR)
  discard close(stdoutPipe[1])
  discard close(stderrPipe[1])

  # Call the wasm function
  var callError: string
  var timedOut = false
  try:
    let fnc = inst.env.findFunction(funcName)
    fnc.call(void)
  except WasmError as e:
    callError = e.msg
  except CatchableError as e:
    callError = e.msg

  # Flush stdout/stderr before restoring
  flushFile(stdout)
  flushFile(stderr)

  # Restore original file descriptors
  discard dup2(origStdout, STDOUT_FILENO)
  discard dup2(origStderr, STDERR_FILENO)
  discard close(origStdout)
  discard close(origStderr)

  # Read captured output
  var stdoutBuf = newString(4096)
  var stderrBuf = newString(4096)
  var stdoutOut = ""
  var stderrOut = ""

  while true:
    let n = read(stdoutPipe[0], stdoutBuf[0].addr, stdoutBuf.len)
    if n <= 0: break
    stdoutOut.add(stdoutBuf[0 ..< n])

  while true:
    let n = read(stderrPipe[0], stderrBuf[0].addr, stderrBuf.len)
    if n <= 0: break
    stderrOut.add(stderrBuf[0 ..< n])

  discard close(stdoutPipe[0])
  discard close(stderrPipe[0])

  if callError.len > 0:
    if stderrOut.len > 0:
      stderrOut.add("\n")
    stderrOut.add(callError)
    return err(wasmRuntimeError(callError))

  ok(WasmCallResult(
    exitCode: 0,
    stdout: stdoutOut,
    stderr: stderrOut,
    timedOut: timedOut,
    success: true
  ))

# ── Call WASM function ─────────────────────────────────────────────────────────

proc callVoid*(inst: var WasmInstance; funcName: string): Result[WasmCallResult, string] =
  ## Call an exported void function on a WASM instance.
  ## Captures stdout/stderr from WASI fd_write.
  inst.captureAndCall(funcName)

proc call*(inst: var WasmInstance; funcName: string;
           args: seq[string] = @[]): Result[WasmCallResult, string] =
  ## Call an exported function on a WASM instance.
  ## For now, calls as void (no args). Use callVoid directly for void functions.
  ## Plugins should return results via stdout or memory, not return values.
  inst.captureAndCall(funcName)

# ── Convenience: load and call in one step ─────────────────────────────────────

proc loadAndCall*(engine: WasmEngine; wasmPath: string;
                  funcName: string): Result[WasmCallResult, string] =
  ## Load a WASM module and call a function in one step.
  let modRes = engine.loadModule(wasmPath)
  if modRes.isErr:
    return err(modRes.error)

  let instRes = engine.instantiate(modRes.value)
  if instRes.isErr:
    return err(instRes.error)

  var inst = instRes.value
  inst.callVoid(funcName)

proc loadBytesAndCall*(engine: WasmEngine; data: sink string;
                       funcName: string;
                       name: string = "module"): Result[WasmCallResult, string] =
  ## Load WASM bytes and call a function in one step.
  let modRes = engine.loadModuleFromBytes(data, name)
  if modRes.isErr:
    return err(modRes.error)

  let instRes = engine.instantiate(modRes.value)
  if instRes.isErr:
    return err(instRes.error)

  var inst = instRes.value
  inst.callVoid(funcName)

# ── Pure helpers ───────────────────────────────────────────────────────────────

func engineWithOpts*(engine: WasmEngine; opts: WasmSandboxOpts): WasmEngine =
  result = engine
  result.opts = opts

func engineWithCpuLimit*(engine: WasmEngine; limit: CpuLimit): WasmEngine =
  result = engine
  result.opts = result.opts.withCpuLimit(limit)

func engineWithMemLimit*(engine: WasmEngine; limit: MemLimit): WasmEngine =
  result = engine
  result.opts = result.opts.withMemLimit(limit)

func engineWithAllowedDirs*(engine: WasmEngine; dirs: seq[string]): WasmEngine =
  result = engine
  result.opts = result.opts.withAllowedDirs(dirs)
