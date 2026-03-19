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

export SandboxMode

# ── Command builder (pure — exported for unit tests) ─────────────────────────

proc buildDockerCmd*(cmd, paddock, image: string): string {.gcsafe, raises: [].} =
  ## Returns the docker run invocation string without executing it.
  "docker run --rm " &
  "-v " & paddock & ":/workspace " &
  "-w /workspace " &
  image & " sh -c " & quoteShell(cmd)

# ── Executor ──────────────────────────────────────────────────────────────────

proc sandboxBash*(cmd, paddock: string;
                  mode:  SandboxMode;
                  image: string): string {.gcsafe, raises: [].} =
  ## Executes cmd in the appropriate sandbox for `mode`.
  ## For smNone: runs directly with paddock as CWD.
  ## For smDocker: wraps cmd in an ephemeral container with paddock bind-mounted.
  try:
    let (fullCmd, workDir) =
      case mode
      of smNone:
        createDir(paddock)
        (cmd, paddock)
      of smDocker:
        (buildDockerCmd(cmd, paddock, image), "")

    let (output, code) = execCmdEx(fullCmd,
                                   options = {poEvalCommand, poStdErrToStdOut},
                                   workingDir = workDir)
    result = output
    if result.endsWith('\n'): result.setLen(result.len - 1)
    if code != 0:
      if result.len > 0: result.add('\n')
      result.add("[exit " & $code & "]")
    if result.len == 0:
      result = "[exit " & $code & "]"
  except CatchableError as e:
    result = "Error: " & e.msg

# ── Startup log ───────────────────────────────────────────────────────────────

proc sandboxLogLevel*(mode: SandboxMode; image: string; log: Logger) =
  case mode
  of smNone:
    log.warn("bash sandbox: none — workingDir isolation only. " &
             "Set [sandbox] mode = \"docker\" in donkey.toml for full isolation.")
  of smDocker:
    log.info("bash sandbox: docker (image: " & image & ")")
