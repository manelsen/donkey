## sandbox.nim — bash tool execution with optional Docker isolation.
##
## Modes (SandboxMode from config/types):
##   smNone   — direct exec in paddock dir; no OS-level isolation
##   smDocker — ephemeral container with bind-mounted paddock
##
## Docker mode:
##   docker run --rm -v {paddock}:/workspace -w /workspace {image} sh -c {cmd}
##
##   The paddock is bind-mounted (not a named volume) so files persist on the
##   host between sessions regardless of container lifecycle.
##   Network access is left enabled so the agent can run git, npm, curl, etc.
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

# ── Command builder (pure — exported for unit tests) ─────────────────────────

proc buildDockerCmd*(cmd, paddock, image: string): string {.gcsafe, raises: [].} =
  ## Returns the docker run invocation string without executing it.
  "docker run --rm " &
  "-v " & paddock & ":/workspace " &
  "-w /workspace " &
  image & " sh -c " & quoteShell(cmd)

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
     "Set [sandbox] mode = \"docker\" in " & ConfigFileName & " for full isolation.")
  of smDocker:
    (lvlInfo, "bash sandbox: docker (image: " & image & ")")

# ── Executor ──────────────────────────────────────────────────────────────────

proc sandboxBash*(cmd, paddock: string;
                  mode:  SandboxMode;
                  image: string): string {.gcsafe, raises: [].} =
  ## Executes cmd in the appropriate sandbox for `mode`.
  ## For smNone: runs directly with paddock as CWD.
  ## For smDocker: wraps cmd in an ephemeral container with paddock bind-mounted.
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
