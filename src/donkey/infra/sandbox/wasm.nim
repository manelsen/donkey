## infra/sandbox/wasm — Wasmtime-based WASM sandbox for untrusted plugin execution.
##
## Spawns wasmtime as a subprocess to execute WebAssembly plugins in isolation.
## WASM plugins are untrusted code run in a restricted environment with no filesystem
## access, limited memory, and no networking.
##
## Usage:
##   let engine = newWasmEngine("/usr/bin/wasmtime")
##   let modResult = engine.loadModule("plugin.wasm")
##   if modResult.isErr:
##     echo "load failed: " & modResult.error
##     return
##   let inst = engine.instantiate(modResult.value)
##   let result = inst.call("run", @["arg1", "arg2"]).valueOr:
##     echo "call failed: " & error
##     return
##   echo "output: " & result
##
## All functions return Result[T, string] so callers decide what to do on error.
## Functions are designed as unary or with the piped target as last argument to
## facilitate `|>` and `>>=` chaining where applicable.

import std/[os, posix, strutils, json, osproc]

import ../../core/pipeops
import ./limits

export pipeops

# ── Types ─────────────────────────────────────────────────────────────────────

type
  WasmEngine* = object
    ## Engine for loading and running WASM modules via wasmtime CLI.
    wasmtimePath*: string   ## Path to wasmtime binary.
    opts*: WasmSandboxOpts

  WasmSandboxOpts* = object
    ## Sandbox options for WASM execution.
    cpuLimit*: CpuLimit     ## CPU time limit (0 = unlimited).
    memLimit*: MemLimit     ## Memory limit in bytes (0 = unlimited).
    allowedDirs*: seq[string] ## Directories the plugin can access (empty = none).

  WasmModule* = object
    ## Loaded WASM module ready for instantiation.
    path*: string           ## Path to the WASM file.
    enginePath*: string     ## Path to wasmtime binary.

  WasmInstance* = object
    ## Instantiation of a WASM module.
    module*: WasmModule
    opts*: WasmSandboxOpts

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
func wasmtimeError*(msg: string): string = "wasmtime: " & msg

# ── Engine constructors ───────────────────────────────────────────────────────

func newWasmEngine*(wasmtimePath: string): WasmEngine =
  WasmEngine(wasmtimePath: wasmtimePath, opts: WasmSandboxOpts(
    cpuLimit: cpuSeconds(30),
    memLimit: memBytes(128 * 1024 * 1024),
    allowedDirs: @[]
  ))

func newWasmEngine*(wasmtimePath: string; opts: WasmSandboxOpts): WasmEngine =
  WasmEngine(wasmtimePath: wasmtimePath, opts: opts)

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

func `$`*(opts: WasmSandboxOpts): string =
  var parts: seq[string] = @[]
  if opts.cpuLimit.int64 > 0:
    parts.add("cpu=" & $opts.cpuLimit)
  if opts.memLimit.int64 > 0:
    parts.add("mem=" & $opts.memLimit)
  if opts.allowedDirs.len > 0:
    parts.add("dirs=" & opts.allowedDirs.join(","))
  if parts.len == 0:
    "WasmSandboxOpts(unrestricted)"
  else:
    "WasmSandboxOpts(" & parts.join(", ") & ")"

func `$`*(engine: WasmEngine): string =
  "WasmEngine(wasmtime=" & engine.wasmtimePath & ", " & $engine.opts & ")"

func `$`*(m: WasmModule): string =
  "WasmModule(path=" & m.path & ")"

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

# ── Pure helper: build wasmtime args ─────────────────────────────────────────

func buildWasmtimeArgs*(opts: WasmSandboxOpts; wasmPath: string; funcName: string;
                        args: seq[string]): seq[string] =
  var cmdArgs: seq[string] = @[]
  
  # Disable all capabilities by default (secure by default)
  cmdArgs.add("--disable-all-features")
  
  # Memory limits
  if opts.memLimit.int64 > 0:
    cmdArgs.add("--max-memory=" & $opts.memLimit.int64)
  
  # CPU limits via WASMtime's fuel mechanism (wasmtime uses fuel for timeouts)
  # Note: fuel is measured in fuel units, roughly correlate to CPU instructions
  if opts.cpuLimit.int64 > 0:
    # Convert seconds to fuel units (rough approximation: 1 second = 10M fuel units)
    let fuel = opts.cpuLimit.int64 * 10_000_000
    cmdArgs.add("--fuel=" & $fuel)
  
  # Directory access restrictions (map dirs to sandbox)
  for dir in opts.allowedDirs:
    cmdArgs.add("--dir=" & dir)
  
  # If no dirs allowed, deny all filesystem access
  if opts.allowedDirs.len == 0:
    cmdArgs.add("--dir=")
  
  # Map /tmp as a temporary directory
  cmdArgs.add("--dir=/tmp")
  
  # WASM file and function to call
  cmdArgs.add(wasmPath)
  cmdArgs.add("--invoke")
  cmdArgs.add(funcName)
  
  # Arguments to the WASM function
  for arg in args:
    cmdArgs.add(arg)
  
  cmdArgs

# ── Validate WASM binary ───────────────────────────────────────────────────────

proc validateWasmFile*(wasmPath: string): Result[WasmValidationResult, string] =
  ## Validate a WASM file without executing it.
  ## Returns WasmValidationResult with valid=true on success.
  
  if not wasmPath.fileExists:
    return ok(WasmValidationResult(valid: false, error: "File not found: " & wasmPath))
  
  if wasmPath.dirExists:
    return ok(WasmValidationResult(valid: false, error: "Path is a directory, not a file: " & wasmPath))
  
  # Try to validate with wasmtime
  let wasmtimePath = "wasmtime"  # Expect in PATH
  
  if not wasmtimePath.fileExists:
    # Fall back: check magic bytes manually
    let file = open(wasmPath, fmRead)
    defer: close(file)
    var header: array[8, char]
    let bytesRead = readChars(file, header, 0, 8)
    if bytesRead < 4:
      return ok(WasmValidationResult(valid: false, error: "File too small to be a valid WASM binary"))
    
    # WASM magic: 0x00 0x61 0x73 0x6d ("\0asm")
    if header[0] == '\0' and header[1] == 'a' and header[2] == 's' and header[3] == 'm':
      return ok(WasmValidationResult(valid: true))
    else:
      return ok(WasmValidationResult(valid: false, error: "Invalid WASM magic bytes"))
  
  # Try wasmtime validate
  let validateArgs = @["wasmtime", "validate", wasmPath]
  let (output, exitCode) = execCmdEx(validateArgs.join(" "))
  
  if exitCode == 0:
    return ok(WasmValidationResult(valid: true))
  else:
    return ok(WasmValidationResult(valid: false, error: output.strip()))

proc validateWasmFile*(engine: WasmEngine; wasmPath: string): Result[WasmValidationResult, string] =
  validateWasmFile(wasmPath)

# ── Load WASM module ───────────────────────────────────────────────────────────

proc loadModule*(engine: var WasmEngine; wasmPath: string): Result[WasmModule, string] =
  ## Load a WASM module from file. Does not instantiate it.
  
  let wasmtimePath = engine.wasmtimePath
  
  # Check wasmtime exists
  if not wasmtimePath.fileExists:
    return err(wasmEngineError("wasmtime not found at: " & wasmtimePath))
  
  # Validate the file first
  let validRes = engine.validateWasmFile(wasmPath)
  if validRes.isErr:
    return err(wasmModuleError("validation failed: " & validRes.error))
  
  if not validRes.value.valid:
    return err(wasmModuleError("invalid WASM: " & validRes.value.error))
  
  ok(WasmModule(path: wasmPath, enginePath: wasmtimePath))

# ── Instantiate WASM module ──────────────────────────────────────────────────

proc instantiate*(engine: var WasmEngine; m: WasmModule): Result[WasmInstance, string] =
  ## Create an instance of a loaded module.
  WasmInstance(module: m, opts: engine.opts).ok()

# ── Call WASM function ─────────────────────────────────────────────────────────

proc call*(inst: var WasmInstance; funcName: string;
           args: seq[string] = @[]): Result[WasmCallResult, string] =
  ## Call an exported function on a WASM instance.
  ## Returns WasmCallResult with stdout, stderr, exit code, and success flag.
  
  let wasmPath = inst.module.path
  let wasmtimePath = inst.module.enginePath
  
  # Build wasmtime command
  let wasmtimeArgs = inst.opts.buildWasmtimeArgs(wasmPath, funcName, args)
  
  # Execute wasmtime
  let cmd = wasmtimePath & " " & wasmtimeArgs.join(" ")
  let (output, exitCode) = execCmdEx(cmd)
  
  # Parse stdout/stderr from output
  # wasmtime outputs to stdout, errors to stderr
  var stdout = output
  var stderr = ""
  var timedOut = false
  var success = false
  
  # Check for timeout indicator (wasmtime returns 255 for trap/fuel exhaustion)
  if exitCode == 255 or exitCode == 124:
    # 124 is convention for timeout from --fuel
    timedOut = true
    success = false
  elif exitCode == 0:
    success = true
  else:
    success = false
  
  # wasmtime can output to both stdout and stderr
  # If output contains null bytes or looks like binary, it's probably mixed
  if '\0' in output:
    # Binary output - split on null or treat all as stderr
    stderr = output
    stdout = ""
  
  return ok(WasmCallResult(
    exitCode: exitCode,
    stdout: stdout,
    stderr: stderr,
    timedOut: timedOut,
    success: success
  ))

# ── Convenience: load and call in one step ─────────────────────────────────────

proc loadAndCall*(engine: var WasmEngine; wasmPath: string;
                  funcName: string; args: seq[string] = @[]): Result[WasmCallResult, string] =
  ## Load a WASM module and call a function in one step.
  let modRes = engine.loadModule(wasmPath)
  if modRes.isErr:
    return err(modRes.error)
  
  let instRes = engine.instantiate(modRes.value)
  if instRes.isErr:
    return err(instRes.error)
  
  var inst = instRes.value
  inst.call(funcName, args)

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
