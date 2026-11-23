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

import ../config/environment
import std/[os, strtabs, strutils]
when defined(posix):
  import std/posix
import results
import ../config/types
import ../core/log
import ../core/pipeops
import ../core/types
import ../core/utf8
import ../core/app_meta
import ../infra/sandbox/wasm_tools
import ../infra/sandbox/shell_composer
import ../ports/fs
import ../ports/process

export process
export SandboxMode

type
  SandboxPlan* = object
    command*:        string
    workingDir*:     string
    ensureWorkDir*:  bool

  PathOwnerFn* = proc(path: string): Result[int, string] {.gcsafe, raises: [].}

const
  SandboxExecCommand* = "__sandbox_exec"
  SandboxWriteProbeFile* = ".donkey-write-probe"

func canReenterViaHelper(appPath: string): bool {.gcsafe, raises: [].} =
  let base = extractFilename(appPath).toLowerAscii()
  base == AppSlug or base == AppSlug & ".out"

proc findExeSafe(name: string): string {.gcsafe, raises: [].} =
  try:
    findExe(name)
  except CatchableError:
    ""

proc effectiveUid*(): int {.gcsafe, raises: [].} =
  when defined(posix):
    getuid().int
  else:
    -1

proc effectiveGid*(): int {.gcsafe, raises: [].} =
  when defined(posix):
    getgid().int
  else:
    -1

proc pathOwnerUid*(path: string): Result[int, string] {.gcsafe, raises: [].} =
  when defined(posix):
    var st: Stat
    if stat(path.cstring, st) != 0'i32:
      return err(osErrorMsg(osLastError()))
    ok(st.st_uid.int)
  else:
    discard path
    ok(-1)

proc collectOwnershipViolations*(fs: FsRuntimePort; root: string;
                                 expectedUid: int;
                                 ownerFn: PathOwnerFn = pathOwnerUid): seq[string]
                                 {.gcsafe, raises: [].} =
  if root.len == 0 or fs.entryKind(root) != fekDir or ownerFn == nil or expectedUid < 0:
    return
  var pending = @[root]
  while pending.len > 0:
    let current = pending.pop()
    let ownerUid = ownerFn(current).valueOr:
      result.add(current & " (owner lookup failed: " & error & ")")
      continue
    if ownerUid != expectedUid:
      result.add(current)
      continue
    let children = fs.listDir(current).valueOr:
      result.add(current & " (walk failed: " & error & ")")
      continue
    for child in children:
      case child.kind
      of fekDir:
        pending.add(child.path)
      of fekFile, fekLink, fekMissing:
        let childOwner = ownerFn(child.path).valueOr:
          result.add(child.path & " (owner lookup failed: " & error & ")")
          continue
        if childOwner != expectedUid:
          result.add(child.path)

proc validatePaddockOwnership*(fs: FsRuntimePort; cfg: DonkeyConfig;
                               devMode: bool;
                               ownerFn: PathOwnerFn = pathOwnerUid;
                               uid = effectiveUid()): Result[void, string]
                               {.gcsafe, raises: [].} =
  if devMode or uid < 0:
    return ok()
  let violations = collectOwnershipViolations(fs, cfg.paddocks, uid, ownerFn)
  if violations.len == 0:
    return ok()
  let shown = violations[0 ..< min(violations.len, 3)].join(", ")
  let suffix =
    if violations.len > 3: " (+" & $(violations.len - 3) & " more)"
    else: ""
  err("Security Error: paddock ownership mismatch under " & cfg.paddocks &
      ". Expected UID " & $uid & ". Offending paths: " & shown & suffix)

proc buildHostSandboxEnv*(paddock: string): StringTableRef {.gcsafe, raises: [].} =
  result = newStringTable(mode = modeCaseSensitive)
  let homeDir =
    if paddock.len > 0: paddock
    else: getHomeDir()
  let tmpDir = inheritedByChild("TMPDIR", "/tmp")
  let lang = inheritedByChild("LANG", "C.UTF-8")
  let user = inheritedByChild("USER", "donkey")
  result["PATH"] = inheritedByChild("PATH")
  result["HOME"] = homeDir
  result["TMPDIR"] = tmpDir
  result["TMP"] = inheritedByChild("TMP", tmpDir)
  result["TEMP"] = inheritedByChild("TEMP", tmpDir)
  result["LANG"] = lang
  result["LC_ALL"] = inheritedByChild("LC_ALL", lang)
  result["TERM"] = inheritedByChild("TERM", "dumb")
  result["USER"] = user
  result["LOGNAME"] = inheritedByChild("LOGNAME", user)

func childEnvPairs(env: StringTableRef): seq[(string, string)] =
  if env != nil:
    for k, v in env: result.add (k, v)

func planSpec(plan: SandboxPlan; env: StringTableRef): ProcessSpec =
  ## A nil `env` inherits the daemon's environment (the OCI runtime needs it);
  ## otherwise it is the child's whole environment.
  ProcessSpec(command: plan.command, workingDir: plan.workingDir,
              createWorkingDir: plan.ensureWorkDir,
              env: childEnvPairs(env), replaceEnv: env != nil)

# ── Shell.wasm path resolution ────────────────────────────────────────────────

proc resolveShellWasmPath*(): string {.gcsafe, raises: [].} =
  ## Returns the path to shell.wasm (go-busybox).
  ## The file must be named "busybox" (no extension) so that argv[0] works
  ## with the go-busybox multi-call binary dispatcher.
  ## Whether it exists is for the caller to check.
  getHomeDir() / ".donkey" / "busybox"

# ── Command builder (pure — exported for unit tests) ─────────────────────────

proc buildOciCmd*(cmd, paddock, image: string;
                  runtimeCmd = "docker";
                  allowNetwork = false;
                  readOnlyRootfs = true): string {.gcsafe, raises: [].} =
  ## Returns the OCI runtime invocation string without executing it.
  let uid = effectiveUid()
  let gid = effectiveGid()
  let userArg =
    if uid >= 0 and gid >= 0: "--user " & $uid & ":" & $gid & " "
    else: ""
  runtimeCmd & " run --rm " &
  (if allowNetwork: "" else: "--network=none ") &
  (if readOnlyRootfs: "--read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m " else: "") &
  userArg &
  "--cap-drop=ALL --security-opt no-new-privileges " &
  "-v " & quoteShell(paddock & ":/workspace:rw,z") & " " &
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
                       runtimeCmd = "docker";
                       allowNetwork = false;
                       readOnlyRootfs = true): SandboxPlan {.gcsafe, raises: [].} =
  case mode
  of smNone:
    buildDirectPlan(cmd, paddock)
  of smOci:
    SandboxPlan(command: buildOciCmd(cmd, paddock, image, runtimeCmd, allowNetwork, readOnlyRootfs),
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

proc runSandboxPlan*(process: ProcessRuntimePort; plan: SandboxPlan;
                     env: StringTableRef = nil): string {.gcsafe, raises: [].} =
  let ran = process.run(planSpec(plan, env)).valueOr:
    return "Error: " & error
  formatSandboxResult(ran.output, ran.exitCode)

func buildSandboxWriteProbeCmd*(): string {.gcsafe, raises: [].} =
  "touch " & SandboxWriteProbeFile & " && rm -f " & SandboxWriteProbeFile

func isDockerPermissionError*(output: string; runtimeCmd = "docker"): bool {.gcsafe, raises: [].} =
  let normalized = output.toLowerAscii()
  let runtime = runtimeCmd.toLowerAscii()
  ("permission denied" in normalized) and
    ((runtime & ".sock" in normalized) or
     ("daemon socket" in normalized) or
     (runtime & " api" in normalized) or
     ("docker api" in normalized))

func dockerPermissionHint*(runtimeCmd = "docker"): string {.gcsafe, raises: [].} =
  let runtime = runtimeCmd.toLowerAscii()
  let group = if runtime.contains("podman"): "podman" else: "docker"
  result = "Error: " & runtimeCmd & " socket access denied. " &
    "Add the service user to the '" & group & "' group and restart the user service:\n" &
    "  sudo usermod -aG " & group & " $USER\n" &
    "  systemctl --user restart donkey\n" &
    "If the group is still missing, reboot or restart user@<uid>.service."
  if runtime.contains("podman"):
    result &= "\nFor rootless Podman, also export CONTAINER_HOST to the user socket."

proc probeSandboxWorkspaceWritable*(process: ProcessRuntimePort;
                                    mode: SandboxMode;
                                    paddock: string;
                                    image: string;
                                    runtimeCmd = "docker";
                                    allowNetwork = false;
                                    readOnlyRootfs = true): Result[void, string]
                                    {.gcsafe, raises: [].} =
  let plan = buildSandboxPlan(
    buildSandboxWriteProbeCmd(), paddock, mode, image, runtimeCmd,
    allowNetwork, readOnlyRootfs)
  let env =
    if mode == smOci: nil
    else: buildHostSandboxEnv(paddock)
  let ran = process.run(planSpec(plan, env)).valueOr:
    return err("Error: " & error)
  if ran.exitCode == 0:
    return ok()
  let formatted = formatSandboxResult(ran.output, ran.exitCode)
  if isDockerPermissionError(formatted, runtimeCmd):
    return err(dockerPermissionHint(runtimeCmd))
  err(formatted)

proc runSandboxWorker*(process: ProcessRuntimePort; paddock, cmd: string): int
                      {.gcsafe, raises: [].} =
  ## The `__sandbox_exec` helper: runs the command and passes its output and
  ## exit code through.
  let ran = process.run(planSpec(buildDirectPlan(cmd, paddock),
                                 buildHostSandboxEnv(paddock))).valueOr:
    return 1
  try: stdout.write(ran.output)
  except CatchableError: discard
  ran.exitCode

proc runSandboxHelper*(process: ProcessRuntimePort; cmd, paddock: string): string
                      {.gcsafe, raises: [].} =
  ## Re-enters this binary as `__sandbox_exec`, so the command runs with the
  ## filtered host environment in a process of its own.
  let appPath = try: getAppFilename() except CatchableError: ""
  if not canReenterViaHelper(appPath):
    return runSandboxPlan(process, buildDirectPlan(cmd, paddock),
                          buildHostSandboxEnv(paddock))
  let ran = process.run(ProcessSpec(
    argv: @[appPath, SandboxExecCommand, paddock, cmd],
    workingDir: paddock, createWorkingDir: true,
    env: childEnvPairs(buildHostSandboxEnv(paddock)), replaceEnv: true)).valueOr:
    return "Error: " & error
  formatSandboxResult(ran.output, ran.exitCode)

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

proc executeOciPlan*(process: ProcessRuntimePort; cmd, paddock, image: string;
                     runtimeCmd = "docker";
                     allowHostFallback = true;
                     allowNetwork = false;
                     readOnlyRootfs = true): string {.gcsafe, raises: [].} =
  let ociResult = runSandboxPlan(process, buildSandboxPlan(cmd, paddock, smOci, image, runtimeCmd, allowNetwork, readOnlyRootfs))
  if isDockerPermissionError(ociResult, runtimeCmd):
    return dockerPermissionHint(runtimeCmd)
  if not shouldFallbackOci(ociResult, runtimeCmd):
    return ociResult
  if not allowHostFallback:
    return "Error: " & runtimeCmd & " sandbox unavailable; host fallback is disabled by configuration."

  let directResult = runSandboxHelper(process, cmd, paddock)
  "Warning: " & runtimeCmd & " sandbox unavailable; executed without container isolation.\n" &
    directResult

proc sandboxStatusMessage*(mode: SandboxMode; image: string; runtimeCmd = "docker";
                           shellPresent = false): (LogLevel, string) {.gcsafe, raises: [].} =
  ## `shellPresent`: whether shell.wasm exists, for the wasm mode.
  case mode
  of smNone:
    (lvlWarn,
     "bash sandbox: none — workingDir isolation only. " &
     "Set [sandbox] mode = \"oci\" or \"wasm\" in " & ConfigFileName & " for full isolation.")
  of smOci:
    (lvlInfo, "bash sandbox: oci (" & runtimeCmd & ", image: " & image & ")")
  of smWasm:
    let shellPath = resolveShellWasmPath()
    if shellPresent:
      (lvlInfo, "bash sandbox: wasm (wasmtime + " & shellPath & ")")
    else:
      (lvlWarn,
       "bash sandbox: wasm mode enabled but shell.wasm not found at " & shellPath &
       ". Run scripts/setup_shell_wasm.sh to build it.")

proc validateSandboxPolicy*(cfg: DonkeyConfig;
                            devMode: bool): Result[void, string] {.gcsafe, raises: [].} =
  if cfg.invalidSandboxMode.len > 0:
    return err("Security Error: sandbox mode '" & cfg.invalidSandboxMode &
               "' is invalid. Use 'oci', 'wasm', or 'none'")
  if not devMode and cfg.sandboxMode == smNone:
    return err("Security Error: Sandbox mode 'none' is only allowed in --dev-mode")
  if not devMode and cfg.sandboxAllowHostFallback:
    return err("Security Error: sandbox.allow_host_fallback=true is only allowed in --dev-mode")
  if not devMode and cfg.sandboxMode == smOci and cfg.sandboxAllowNetwork:
    return err("Security Error: sandbox.allow_network=true is only allowed in --dev-mode")
  if not devMode and cfg.sandboxMode == smOci and not cfg.sandboxReadOnlyRootfs:
    return err("Security Error: sandbox.read_only_rootfs=false is only allowed in --dev-mode")
  ok()

proc probeRuntimeInfo(process: ProcessRuntimePort; runtimePath: string;
                      timeoutMs: int): tuple[output: string, code: int]
                     {.gcsafe, raises: [].} =
  let ran = process.run(argvSpec(@[runtimePath, "info"], timeoutMs = timeoutMs)).valueOr:
    return ("Error: " & error, -1)
  (ran.output, ran.exitCode)

proc sandboxAvailabilityResult*(process: ProcessRuntimePort; fs: FsRuntimePort;
                                cfg: DonkeyConfig;
                                timeoutMs = 3000): Result[string, string]
                                {.gcsafe, raises: [].} =
  if cfg.invalidSandboxMode.len > 0:
    return err("sandbox mode '" & cfg.invalidSandboxMode & "' is invalid; use 'oci', 'wasm', or 'none'")
  case cfg.sandboxMode
  of smNone:
    ok("mode=none")
  of smOci:
    let runtimePath = findExeSafe(cfg.sandboxRuntimeCmd)
    if runtimePath.len == 0:
      err("OCI runtime '" & cfg.sandboxRuntimeCmd & "' not found in PATH")
    else:
      let (output, code) = probeRuntimeInfo(process, runtimePath, timeoutMs)
      if code == 0:
        ok("runtime=" & cfg.sandboxRuntimeCmd)
      elif isDockerPermissionError(output, cfg.sandboxRuntimeCmd):
        err(dockerPermissionHint(cfg.sandboxRuntimeCmd))
      else:
        let detail =
          if output.strip.len > 0: clipUtf8(output.strip, 200)
          else: "probe failed or timed out"
        err("OCI runtime '" & cfg.sandboxRuntimeCmd &
            "' is installed but not reachable: " & detail)
  of smWasm:
    let wasmtimePath = findExeSafe("wasmtime")
    if wasmtimePath.len == 0:
      return err("wasmtime not found in PATH")
    let shellPath = resolveShellWasmPath()
    if fs.entryKind(shellPath) != fekFile:
      return err("shell.wasm not found at " & shellPath)
    ok("wasmtime=" & wasmtimePath & ", shell=" & shellPath)

# ── Executor ──────────────────────────────────────────────────────────────────

proc sandboxBash*(process: ProcessRuntimePort; fs: FsRuntimePort;
                  cmd, paddock: string;
                  mode:  SandboxMode;
                  image: string;
                  runtimeCmd = "docker";
                  allowHostFallback = false;
                  allowNetwork = false;
                  readOnlyRootfs = true): string {.gcsafe, raises: [].} =
  ## Executes cmd in the appropriate sandbox for `mode`.
  ## For smNone: runs directly with paddock as CWD.
  ## For smOci: wraps cmd in an ephemeral container with paddock bind-mounted.
  ## For smWasm: runs via wasmtime + go-busybox. Pipes are composed in Nim
  ## (ShellComposer) since WASI lacks fork/exec.
  ## Falls back to direct exec if shell.wasm is missing.
  case mode
  of smWasm:
    let shellPath = resolveShellWasmPath()
    if fs.entryKind(shellPath) != fekFile:
      if not allowHostFallback:
        return "Error: wasm sandbox unavailable; host fallback is disabled by configuration."
      return runSandboxHelper(process, cmd, paddock)
    # Use ShellComposer for pipes — composes applet chain in Nim
    if "|" in cmd:
      let adapter = newWasmToolAdapter(shellPath)
      return adapter.composeFormatted(cmd, paddock)
    # Single command — use wasmtime directly
    runSandboxPlan(process,
                   buildSandboxPlan(cmd, paddock, mode, image, runtimeCmd, allowNetwork, readOnlyRootfs),
                   buildHostSandboxEnv(paddock))
  of smNone:
    runSandboxHelper(process, cmd, paddock)
  of smOci:
    executeOciPlan(process, cmd, paddock, image, runtimeCmd, allowHostFallback, allowNetwork, readOnlyRootfs)

# ── Startup log ───────────────────────────────────────────────────────────────

proc sandboxLogLevel*(fs: FsRuntimePort; mode: SandboxMode; image: string;
                      runtimeCmd: string; log: Logger) =
  let (level, message) = sandboxStatusMessage(
    mode, image, runtimeCmd, fs.entryKind(resolveShellWasmPath()) == fekFile)
  case level
  of lvlWarn: log.warn(message)
  of lvlInfo: log.info(message)
  of lvlDebug: log.debug(message)
  of lvlError: log.error(message)
  of lvlFatal: log.fatal(message)

proc logSandboxWorkspaceProbe*(process: ProcessRuntimePort; mode: SandboxMode;
                               paddock: string;
                               image: string;
                               runtimeCmd: string;
                               allowNetwork: bool;
                               readOnlyRootfs: bool;
                               log: Logger) =
  let probe = probeSandboxWorkspaceWritable(
    process, mode, paddock, image, runtimeCmd, allowNetwork, readOnlyRootfs)
  if probe.isOk:
    log.info("bash sandbox workspace: writable")
  else:
    log.warn("bash sandbox workspace: write probe failed: " & probe.error)
