## sandbox.nim — bash tool execution with optional Docker/Wasm isolation.
##
## Modes (SandboxMode from config/types):
##   smNone   — direct exec in paddock dir; no OS-level isolation
##   smDocker — ephemeral container with bind-mounted paddock
##   smWasm   — wasmtime CLI executing go-busybox shell.wasm
##
## Docker mode:
##   docker run --rm -v {paddock}:/workspace -w /workspace {image} sh -c {cmd}
##
## Wasm mode:
##   wasmtime run --dir={paddock} --dir=/tmp {busybox} {applet} {args}
##
## The binary is go-busybox (https://github.com/rcarmo/go-busybox) — a
## multi-call binary with 57 applets (cat, grep, sed, echo, ls, etc.).
## MUST be named "busybox" (no extension) so argv[0] dispatches correctly.
## Build with: scripts/setup_shell_wasm.sh
##
## Call sandboxLogLevel once at daemon startup to surface the active mode.

import std/[osproc, os, strutils]
import ../config/types
import ../core/log
import ../core/types
import ../core/app_meta

export SandboxMode

type
  SandboxPlan* = object
    command*:        string
    workingDir*:     string
    ensureWorkDir*:  bool

# ── Shell.wasm path resolution ────────────────────────────────────────────────

proc resolveShellWasmPath*(): string {.gcsafe, raises: [].} =
  ## Returns the path to shell.wasm (go-busybox).
  ## The file must be named "busybox" (no extension) so that argv[0] works
  ## with the go-busybox multi-call binary dispatcher.
  let default = getHomeDir() / ".donkey" / "busybox"
  if default.fileExists: return default
  default  # return default even if missing; caller handles the check

# ── Command builder (pure — exported for unit tests) ─────────────────────────

proc buildDockerCmd*(cmd, paddock, image: string): string {.gcsafe, raises: [].} =
  ## Returns the docker run invocation string without executing it.
  "docker run --rm " &
  "-v " & paddock & ":/workspace " &
  "-w /workspace " &
  image & " sh -c " & quoteShell(cmd)

proc buildWasmCmd*(cmd, paddock, shellPath: string): string {.gcsafe, raises: [].} =
  ## Returns the wasmtime invocation string for go-busybox applets.
  ## The binary must be named "busybox" so that argv[0] dispatches correctly.
  ## Note: go-busybox's ash shell is stubbed under WASI, so complex shell
  ## features (pipes, redirections, shell scripts) won't work. Simple applet
  ## calls (cat, grep, sed, echo, ls, etc.) work fine.
  "wasmtime run " &
  "--dir=" & paddock & " " &
  "--dir=/tmp " &
  shellPath & " " & cmd

proc buildSandboxPlan*(cmd, paddock: string;
                       mode: SandboxMode;
                       image: string): SandboxPlan {.gcsafe, raises: [].} =
  case mode
  of smNone:
    SandboxPlan(command: cmd, workingDir: paddock, ensureWorkDir: true)
  of smDocker:
    SandboxPlan(command: buildDockerCmd(cmd, paddock, image),
                workingDir: "",
                ensureWorkDir: false)
  of smWasm:
    let shellPath = resolveShellWasmPath()
    SandboxPlan(command: buildWasmCmd(cmd, paddock, shellPath),
                workingDir: "",
                ensureWorkDir: false)

proc formatSandboxResult*(output: string; code: int): string {.gcsafe, raises: [].} =
  result = output
  if result.endsWith('\n'):
    result.setLen(result.len - 1)
  if code != 0:
    if result.len > 0:
      result.add('\n')
    result.add("[exit " & $code & "]")
  if result.len == 0:
    result = "[exit " & $code & "]"

proc runSandboxPlan*(plan: SandboxPlan): string {.gcsafe, raises: [].} =
  try:
    if plan.ensureWorkDir and plan.workingDir.len > 0:
      createDir(plan.workingDir)
    let (output, code) = execCmdEx(plan.command,
                                   options = {poEvalCommand, poStdErrToStdOut},
                                   workingDir = plan.workingDir)
    formatSandboxResult(output, code)
  except CatchableError as e:
    "Error: " & e.msg

proc sandboxStatusMessage*(mode: SandboxMode; image: string): (LogLevel, string) {.gcsafe, raises: [].} =
  case mode
  of smNone:
    (lvlWarn,
     "bash sandbox: none — workingDir isolation only. " &
     "Set [sandbox] mode = \"docker\" or \"wasm\" in " & ConfigFileName & " for full isolation.")
  of smDocker:
    (lvlInfo, "bash sandbox: docker (image: " & image & ")")
  of smWasm:
    let shellPath = resolveShellWasmPath()
    if shellPath.fileExists:
      (lvlInfo, "bash sandbox: wasm (wasmtime + " & shellPath & ")")
    else:
      (lvlWarn,
       "bash sandbox: wasm mode enabled but shell.wasm not found at " & shellPath &
       ". Run scripts/setup_shell_wasm.sh to build it.")

# ── Executor ──────────────────────────────────────────────────────────────────

proc sandboxBash*(cmd, paddock: string;
                  mode:  SandboxMode;
                  image: string): string {.gcsafe, raises: [].} =
  ## Executes cmd in the appropriate sandbox for `mode`.
  ## For smNone: runs directly with paddock as CWD.
  ## For smDocker: wraps cmd in an ephemeral container with paddock bind-mounted.
  ## For smWasm: runs cmd via wasmtime + go-busybox shell.wasm.
  ## Falls back to direct exec if shell.wasm is missing.
  case mode
  of smWasm:
    let shellPath = resolveShellWasmPath()
    if not shellPath.fileExists:
      # Graceful fallback
      let plan = SandboxPlan(command: cmd, workingDir: paddock, ensureWorkDir: true)
      return runSandboxPlan(plan)
    runSandboxPlan(buildSandboxPlan(cmd, paddock, mode, image))
  of smNone, smDocker:
    runSandboxPlan(buildSandboxPlan(cmd, paddock, mode, image))

# ── Startup log ───────────────────────────────────────────────────────────────

proc sandboxLogLevel*(mode: SandboxMode; image: string; log: Logger) =
  let (level, message) = sandboxStatusMessage(mode, image)
  case level
  of lvlWarn: log.warn(message)
  of lvlInfo: log.info(message)
  of lvlDebug: log.debug(message)
  of lvlError: log.error(message)
  of lvlFatal: log.fatal(message)
