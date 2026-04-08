## sandbox.nim — bash tool execution with optional OCI/Wasm isolation.
##
## Modes (SandboxMode from config/types):
##   smNone   — direct exec in paddock dir; no OS-level isolation
##   smOci    — ephemeral container with bind-mounted paddock
##   smWasm   — wasmtime CLI executing go-busybox shell.wasm
##
## OCI mode:
##   {runtime} run --rm -v {paddock}:/workspace -w /workspace {image} sh -c {cmd}
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
import ../infra/sandbox/wasm_tools
import ../infra/sandbox/shell_composer

export SandboxMode

type
  SandboxPlan* = object
    command*:        string
    workingDir*:     string
    ensureWorkDir*:  bool

  SandboxRunner* = proc(plan: SandboxPlan): string {.gcsafe, raises: [].}

# ── Shell.wasm path resolution ────────────────────────────────────────────────

proc resolveShellWasmPath*(): string {.gcsafe, raises: [].} =
  ## Returns the path to shell.wasm (go-busybox).
  ## The file must be named "busybox" (no extension) so that argv[0] works
  ## with the go-busybox multi-call binary dispatcher.
  let default = getHomeDir() / ".donkey" / "busybox"
  if default.fileExists: return default
  default  # return default even if missing; caller handles the check

# ── Command builder (pure — exported for unit tests) ─────────────────────────

proc buildOciCmd*(cmd, paddock, image: string; runtimeCmd = "docker"): string {.gcsafe, raises: [].} =
  ## Returns the OCI runtime invocation string without executing it.
  runtimeCmd & " run --rm " &
  "-v " & paddock & ":/workspace " &
  "-w /workspace " &
  image & " sh -c " & quoteShell(cmd)

func buildDirectPlan*(cmd, paddock: string): SandboxPlan {.gcsafe, raises: [].} =
  SandboxPlan(command: cmd, workingDir: paddock, ensureWorkDir: true)

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
                       image: string;
                       runtimeCmd = "docker"): SandboxPlan {.gcsafe, raises: [].} =
  case mode
  of smNone:
    buildDirectPlan(cmd, paddock)
  of smOci:
    SandboxPlan(command: buildOciCmd(cmd, paddock, image, runtimeCmd),
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

func shouldFallbackOci*(output: string; runtimeCmd = "docker"): bool {.gcsafe, raises: [].} =
  let normalized = output.toLowerAscii()
  let runtime = runtimeCmd.toLowerAscii()
  ("unable to find image" in normalized) or
  ("pull access denied" in normalized) or
  ("error response from daemon" in normalized) or
  ("cannot connect to the " & runtime & " daemon" in normalized) or
  ("permission denied while trying to connect to the " & runtime & " daemon socket" in normalized) or
  ("error: could not find command: " & runtime in normalized) or
  ("error: " in normalized and runtime in normalized and "no such file or directory" in normalized)

proc executeOciPlan*(cmd, paddock, image: string;
                     runtimeCmd = "docker";
                     runPlan: SandboxRunner = runSandboxPlan): string {.gcsafe, raises: [].} =
  let ociResult = runPlan(buildSandboxPlan(cmd, paddock, smOci, image, runtimeCmd))
  if not shouldFallbackOci(ociResult, runtimeCmd):
    return ociResult

  let directResult = runPlan(buildDirectPlan(cmd, paddock))
  "Warning: " & runtimeCmd & " sandbox unavailable; executed without container isolation.\n" &
    directResult

proc sandboxStatusMessage*(mode: SandboxMode; image: string; runtimeCmd = "docker"): (LogLevel, string) {.gcsafe, raises: [].} =
  case mode
  of smNone:
    (lvlWarn,
     "bash sandbox: none — workingDir isolation only. " &
     "Set [sandbox] mode = \"oci\" or \"wasm\" in " & ConfigFileName & " for full isolation.")
  of smOci:
    (lvlInfo, "bash sandbox: oci (" & runtimeCmd & ", image: " & image & ")")
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
                  image: string;
                  runtimeCmd = "docker"): string {.gcsafe, raises: [].} =
  ## Executes cmd in the appropriate sandbox for `mode`.
  ## For smNone: runs directly with paddock as CWD.
  ## For smOci: wraps cmd in an ephemeral container with paddock bind-mounted.
  ## For smWasm: runs via wasmtime + go-busybox. Pipes are composed in Nim
  ## (ShellComposer) since WASI lacks fork/exec.
  ## Falls back to direct exec if shell.wasm is missing.
  case mode
  of smWasm:
    let shellPath = resolveShellWasmPath()
    if not shellPath.fileExists:
      # Graceful fallback
      let plan = SandboxPlan(command: cmd, workingDir: paddock, ensureWorkDir: true)
      return runSandboxPlan(plan)
    # Use ShellComposer for pipes — composes applet chain in Nim
    if "|" in cmd:
      let adapter = newWasmToolAdapter(shellPath)
      return adapter.composeFormatted(cmd, paddock)
    # Single command — use wasmtime directly
    runSandboxPlan(buildSandboxPlan(cmd, paddock, mode, image, runtimeCmd))
  of smNone:
    runSandboxPlan(buildSandboxPlan(cmd, paddock, mode, image, runtimeCmd))
  of smOci:
    executeOciPlan(cmd, paddock, image, runtimeCmd)

# ── Startup log ───────────────────────────────────────────────────────────────

proc sandboxLogLevel*(mode: SandboxMode; image: string; runtimeCmd: string; log: Logger) =
  let (level, message) = sandboxStatusMessage(mode, image, runtimeCmd)
  case level
  of lvlWarn: log.warn(message)
  of lvlInfo: log.info(message)
  of lvlDebug: log.debug(message)
  of lvlError: log.error(message)
  of lvlFatal: log.fatal(message)
