## infra/sandbox/paddock — Process Spawn with Resource Limits.
##
## Spawns native tools in restricted child processes using fork+execve.
## Resource limits (CPU, memory, etc.) are applied via setrlimit before exec.
##
## Usage:
##   var p = newPaddock(sandboxDefaults())
##   let result = p.runSpawned("echo", @["echo", "hello"]).valueOr:
##     echo "spawn failed: " & error
##     return
##   echo "exit: " & $result.exitCode
##   echo "stdout: " & result.stdout
##
## All functions return Result[T, string] so callers decide what to do on error.
## Functions are designed as unary or with the piped target as last argument to
## facilitate `|>` and `>>=` chaining where applicable.

import std/[os, posix, strutils]

import ../../core/pipeops
import ./limits

export pipeops

# ── _exit wrapper (C function, not in Nim posix module) ───────────────────────

proc c_exit(code: cint) {.importc: "_exit", header: "<unistd.h>".}
  ## Call C _exit(2) - never calls atexit handlers, use in child after fork.

# ── Types ─────────────────────────────────────────────────────────────────────

type
  SpawnOptions* = object
    ## Options for spawning a restricted child process.
    cpuLimit*: CpuLimit     ## CPU time limit in seconds (0 = unlimited).
    memLimit*: MemLimit     ## Memory (address space) limit in bytes (0 = unlimited).
    nprocLimit*: NprocLimit  ## Max processes (0 = unlimited).
    fsizeLimit*: FsizeLimit  ## Max file size in bytes (0 = unlimited).
    nofileLimit*: NofileLimit ## Max open files (0 = unlimited).
    workingDir*: string      ## Working directory for the child (empty = inherit parent's cwd).
    envVars*: seq[tuple[key, val: string]] ## Extra environment variables (empty = inherit all).
    stdinData*: string       ## Data to write to child's stdin (empty = no stdin pipe).

  SpawnResult* = object
    ## Result of a spawned process.
    exitCode*: int          ## Process exit code (0-255, or -1 if signal killed).
    stdout*: string         ## Captured stdout.
    stderr*: string         ## Captured stderr.
    timedOut*: bool         ## True if process was killed due to CPU limit.

  Paddock* = object
    ## Process spawner with resource limits.
    ## Create with `newPaddock`.
    opts: SpawnOptions

# ── Convenience constructors ───────────────────────────────────────────────────

func paddockDefaults*(): SpawnOptions =
  ## Default spawn options (unlimited resources, inherit working dir).
  SpawnOptions(
    cpuLimit: CpuLimit(0),
    memLimit: MemLimit(0),
    nprocLimit: NprocLimit(0),
    fsizeLimit: FsizeLimit(0),
    nofileLimit: NofileLimit(0),
    workingDir: "",
    envVars: @[],
    stdinData: ""
  )

func withCpuLimit*(opts: SpawnOptions; limit: CpuLimit): SpawnOptions =
  result = opts; result.cpuLimit = limit

func withMemLimit*(opts: SpawnOptions; limit: MemLimit): SpawnOptions =
  result = opts; result.memLimit = limit

func withNprocLimit*(opts: SpawnOptions; limit: NprocLimit): SpawnOptions =
  result = opts; result.nprocLimit = limit

func withFsizeLimit*(opts: SpawnOptions; limit: FsizeLimit): SpawnOptions =
  result = opts; result.fsizeLimit = limit

func withNofileLimit*(opts: SpawnOptions; limit: NofileLimit): SpawnOptions =
  result = opts; result.nofileLimit = limit

func withWorkingDir*(opts: SpawnOptions; dir: string): SpawnOptions =
  result = opts; result.workingDir = dir

func withEnvVar*(opts: SpawnOptions; key, val: string): SpawnOptions =
  result = opts; result.envVars = opts.envVars & @[(key, val)]

func withStdin*(opts: SpawnOptions; data: string): SpawnOptions =
  result = opts; result.stdinData = data

func newPaddock*(): Paddock =
  Paddock(opts: paddockDefaults())

func newPaddock*(opts: SpawnOptions): Paddock =
  Paddock(opts: opts)

# ── Formatting ─────────────────────────────────────────────────────────────────

func `$`*(opts: SpawnOptions): string =
  var parts: seq[string] = @[]
  if opts.cpuLimit.int64 > 0:
    parts.add("cpu=" & $opts.cpuLimit)
  if opts.memLimit.int64 > 0:
    parts.add("mem=" & $opts.memLimit)
  if opts.nprocLimit.int64 > 0:
    parts.add("nproc=" & $opts.nprocLimit)
  if opts.fsizeLimit.int64 > 0:
    parts.add("fsize=" & $opts.fsizeLimit)
  if opts.nofileLimit.int64 > 0:
    parts.add("nofile=" & $opts.nofileLimit)
  if opts.workingDir.len > 0:
    parts.add("cwd=" & opts.workingDir)
  if parts.len == 0:
    "SpawnOptions(unlimited)"
  else:
    "SpawnOptions(" & parts.join(", ") & ")"

func `$`*(res: SpawnResult): string =
  "SpawnResult(exitCode=" & $res.exitCode &
    ", timedOut=" & (if res.timedOut: "true" else: "false") &
    ", stdout.len=" & $res.stdout.len &
    ", stderr.len=" & $res.stderr.len & ")"

# ── Internal: apply limits in child ──────────────────────────────────────────

proc applyLimitsChild*(opts: SpawnOptions): LimitResult =
  ## Apply resource limits in the child process. Returns err on first failure.
  if opts.cpuLimit.int64 > 0:
    let r = setrlimitCpu(opts.cpuLimit)
    if r.isErr: return err("cpu: " & r.error)
  if opts.memLimit.int64 > 0:
    let r = setrlimitMem(opts.memLimit)
    if r.isErr: return err("mem: " & r.error)
  if opts.nprocLimit.int64 > 0:
    let r = setrlimitNproc(opts.nprocLimit)
    if r.isErr: return err("nproc: " & r.error)
  if opts.fsizeLimit.int64 > 0:
    let r = setrlimitFsize(opts.fsizeLimit)
    if r.isErr: return err("fsize: " & r.error)
  if opts.nofileLimit.int64 > 0:
    let r = setrlimitNofile(opts.nofileLimit)
    if r.isErr: return err("nofile: " & r.error)
  ok()

# ── Internal: setup child environment ──────────────────────────────────────────

proc setupChildEnv*(opts: SpawnOptions) =
  ## Setup environment variables in child if any are specified.
  for (key, val) in opts.envVars:
    putEnv(key, val)

# ── Run spawned: fork + exec + wait ───────────────────────────────────────────

proc runSpawned*(p: var Paddock; cmd: string; args: seq[string]): Result[SpawnResult, string] =
  ## Spawn a child process with resource limits, wait for it, and return result.
  ## The command is looked up via PATH environment variable.
  ##
  ## Returns SpawnResult with stdout, stderr, and exit code.
  ## On failure to spawn, returns err with description.
  
  let opts = p.opts
  
  # Create pipes for stdout and stderr
  var stdoutPipe: array[2, cint]
  var stderrPipe: array[2, cint]
  var stdinPipe: array[2, cint]
  
  if pipe(stdoutPipe) < 0:
    return err("pipe(stdout) failed")
  if pipe(stderrPipe) < 0:
    discard close(stdoutPipe[0])
    discard close(stdoutPipe[1])
    return err("pipe(stderr) failed")
  if opts.stdinData.len > 0:
    if pipe(stdinPipe) < 0:
      discard close(stdoutPipe[0])
      discard close(stdoutPipe[1])
      discard close(stderrPipe[0])
      discard close(stderrPipe[1])
      return err("pipe(stdin) failed")
  
  # Fork
  let pid = fork()
  if pid < 0:
    discard close(stdoutPipe[0])
    discard close(stdoutPipe[1])
    discard close(stderrPipe[0])
    discard close(stderrPipe[1])
    if opts.stdinData.len > 0:
      discard close(stdinPipe[0])
      discard close(stdinPipe[1])
    return err("fork failed")
  
  if pid == 0:
    # Child process
    
    # Close read ends
    discard close(stdoutPipe[0])
    discard close(stderrPipe[0])
    if opts.stdinData.len > 0:
      discard close(stdinPipe[1])
    
    # Dup write ends to stdout/stderr
    if dup2(stdoutPipe[1], 1) < 0:
      discard close(stdoutPipe[1])
      discard close(stderrPipe[1])
      if opts.stdinData.len > 0: discard close(stdinPipe[0])
      c_exit(127)
    if dup2(stderrPipe[1], 2) < 0:
      discard close(stderrPipe[1])
      if opts.stdinData.len > 0: discard close(stdinPipe[0])
      c_exit(127)
    
    # Redirect stdin if we have data
    if opts.stdinData.len > 0:
      if dup2(stdinPipe[0], 0) < 0:
        discard close(stdinPipe[0])
        c_exit(127)
    
    # Change working directory if specified
    if opts.workingDir.len > 0:
      discard chdir(opts.workingDir.cstring)
    
    # Apply resource limits
    let limitRes = applyLimitsChild(opts)
    if limitRes.isErr:
      # Can't easily report error, just exit
      c_exit(125)
    
    # Setup extra env vars
    setupChildEnv(opts)
    
    # Setup args for execvp (searches PATH)
    var cArgs: cstringArray = allocCStringArray(args)
    
    # execvp searches PATH for the command
    discard execvp(cmd, cArgs)
    
    # If we get here, exec failed - shouldn't happen
    discard close(1)
    discard close(2)
    if opts.stdinData.len > 0:
      discard close(0)
    deallocCStringArray(cArgs)
    c_exit(127)  # exec failed
    
  else:
    # Parent process
    
    # Close write ends
    discard close(stdoutPipe[1])
    discard close(stderrPipe[1])
    
    # Write stdin data if any
    if opts.stdinData.len > 0:
      discard close(stdinPipe[0])
      let stdinWritten = write(stdinPipe[1], opts.stdinData.cstring, opts.stdinData.len)
      if stdinWritten < 0:
        discard close(stdinPipe[1])
      else:
        discard close(stdinPipe[1])
    
    # Read stdout
    var stdoutBuf = newString(0)
    var stderrBuf = newString(0)
    var buf: array[4096, char]
    
    # Read stdout in loop
    while true:
      let n = read(stdoutPipe[0], buf.addr, buf.len)
      if n <= 0:
        break
      let chunk = newString(n)
      copyMem(chunk.cstring, buf.addr, n)
      stdoutBuf.add(chunk)
    
    # Read stderr
    while true:
      let n = read(stderrPipe[0], buf.addr, buf.len)
      if n <= 0:
        break
      let chunk = newString(n)
      copyMem(chunk.cstring, buf.addr, n)
      stderrBuf.add(chunk)
    
    discard close(stdoutPipe[0])
    discard close(stderrPipe[0])
    
    # Wait for child
    var status: cint
    let waited = waitpid(pid, status, 0)
    if waited < 0:
      return err("waitpid failed")
    
    # Check if CPU limit was hit (SIGXCPU = 24) or general signal kill
    var timedOut = false
    var exitCode = 127
    
    if waited == pid:
      if WIFEXITED(status):
        exitCode = WEXITSTATUS(status)
      elif WIFSIGNALED(status):
        let sig = WTERMSIG(status)
        if sig == SIGXCPU:
          timedOut = true
          exitCode = 124  # Convention for CPU limit exceeded
        else:
          # Killed by signal
          exitCode = 128 + sig.int
      elif WIFSTOPPED(status):
        # Shouldn't happen but handle it
        exitCode = 126
    
    return ok(SpawnResult(
      exitCode: exitCode,
      stdout: stdoutBuf,
      stderr: stderrBuf,
      timedOut: timedOut
    ))

# ── Convenience: spawn with just cmd string ────────────────────────────────────

proc runSpawned*(p: var Paddock; cmdLine: string): Result[SpawnResult, string] =
  ## Parse a command line string and run via runSpawned.
  ## Simple shell-like parsing: splits on whitespace.
  let parts = cmdLine.strip().splitWhitespace()
  if parts.len == 0:
    return err("empty command")
  let cmd = parts[0]
  let args = parts
  p.runSpawned(cmd, args)

# ── Pure helpers for common cases ───────────────────────────────────────────────

func sandboxDefaults*(): SpawnOptions =
  ## Default sandboxed options: limited CPU (60s) and memory (512MB).
  paddockDefaults()
    .withCpuLimit(cpuSeconds(60))
    .withMemLimit(memBytes(512 * 1024 * 1024))

func sandboxInteractive*(): SpawnOptions =
  ## Options for interactive commands: more time, no memory limit.
  paddockDefaults()
    .withCpuLimit(cpuSeconds(300))
    .withNprocLimit(nprocCount(4))

func sandboxQuick*(): SpawnOptions =
  ## Quick sandbox: 10s CPU, 64MB memory.
  paddockDefaults()
    .withCpuLimit(cpuSeconds(10))
    .withMemLimit(memBytes(64 * 1024 * 1024))
