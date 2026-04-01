## infra/sandbox/wasm_tools — WasmToolAdapter for go-busybox applets.
##
## Wraps wasmtime execution of individual go-busybox applets as sandboxed
## tool calls. Each applet (grep, find, sed, cat, etc.) runs as an isolated
## WASM process with bounded filesystem access.
##
## Usage:
##   let adapter = newWasmToolAdapter()
##   let result = adapter.runApplet("grep", @["-n", "pattern", "file.txt"], "/workspace")
##   if result.success:
##     echo result.output

import std/[osproc, os, strutils]

# ── Types ─────────────────────────────────────────────────────────────────────

type
  WasmToolAdapter* = object
    ## Adapter for running go-busybox applets via wasmtime.
    busyboxPath*: string

  AppletResult* = object
    ## Result of a go-busybox applet execution.
    exitCode*: int
    output*: string
    success*: bool

func `$`*(r: AppletResult): string =
  "AppletResult(exitCode=" & $r.exitCode &
    ", success=" & (if r.success: "true" else: "false") &
    ", output.len=" & $r.output.len & ")"

# ── Known applets ─────────────────────────────────────────────────────────────

const
  ## Applets available in go-busybox under WASI.
  ## Excludes stubbed applets: ash, sh, top, ps, kill, nice, nohup, etc.
  KnownApplets* = [
    # Text processing
    "cat", "grep", "sed", "awk", "head", "tail", "wc",
    "sort", "uniq", "cut", "tr", "diff", "echo", "printf",
    # Filesystem
    "find", "ls", "cp", "mv", "mkdir", "rm", "rmdir", "pwd",
    # Archive
    "gzip", "gunzip", "tar",
    # Data
    "wget", "nc", "dig",
    # System
    "sleep", "nproc", "whoami", "logname", "uptime", "free",
  ]

# ── Constructors ──────────────────────────────────────────────────────────────

proc newWasmToolAdapter*(): WasmToolAdapter =
  WasmToolAdapter(busyboxPath: getHomeDir() / ".donkey" / "busybox")

proc newWasmToolAdapter*(busyboxPath: string): WasmToolAdapter =
  WasmToolAdapter(busyboxPath: busyboxPath)

# ── Applet validation ────────────────────────────────────────────────────────

proc isValidAppletName*(name: string): bool =
  ## Returns true if name is a known, non-stubbed applet.
  name in KnownApplets

proc availableApplets*(): seq[string] =
  ## Returns the list of available (non-stubbed) applet names.
  @KnownApplets

# ── Command building (pure) ──────────────────────────────────────────────────

proc buildAppletArgs*(args: seq[string]): string {.gcsafe, raises: [].} =
  ## Joins applet arguments with spaces.
  args.join(" ")

proc buildAppletCmd*(busyboxPath, applet: string;
                     args: seq[string];
                     paddock: string): string {.gcsafe, raises: [].} =
  ## Builds the wasmtime invocation string for a go-busybox applet.
  ## The busybox binary must be named "busybox" so that argv[0] dispatches correctly.
  ## Args are shell-quoted to prevent glob expansion with poEvalCommand.
  var parts = @[
    "wasmtime", "run",
    "--dir=" & paddock,
    "--dir=/tmp",
    busyboxPath,
    applet,
  ]
  for a in args:
    parts.add(quoteShell(a))
  parts.join(" ")

proc formatAppletResult*(output: string; code: int): string {.gcsafe, raises: [].} =
  ## Formats applet output, trimming trailing newlines and appending exit code on failure.
  result = output
  if result.endsWith('\n'):
    result.setLen(result.len - 1)
  if code != 0:
    if result.len > 0:
      result.add('\n')
    result.add("[exit " & $code & "]")

# ── Execution ─────────────────────────────────────────────────────────────────

proc runApplet*(adapter: WasmToolAdapter;
                applet: string;
                args: seq[string];
                paddock: string): AppletResult {.gcsafe, raises: [].} =
  ## Execute a go-busybox applet via wasmtime.
  ## Returns AppletResult with output, exit code, and success flag.
  if not adapter.busyboxPath.fileExists:
    return AppletResult(exitCode: -1,
      output: "busybox not found at " & adapter.busyboxPath &
              ". Run scripts/setup_shell_wasm.sh to build it.",
      success: false)

  if not isValidAppletName(applet):
    return AppletResult(exitCode: -1,
      output: "Unknown applet: " & applet &
              ". Available: " & availableApplets().join(", "),
      success: false)

  let cmd = buildAppletCmd(adapter.busyboxPath, applet, args, paddock)
  try:
    let (output, code) = execCmdEx(cmd,
      options = {poEvalCommand, poStdErrToStdOut},
      workingDir = paddock)
    AppletResult(exitCode: code, output: output, success: code == 0)
  except CatchableError as e:
    AppletResult(exitCode: -1, output: "Error: " & e.msg, success: false)

proc runAppletFormatted*(adapter: WasmToolAdapter;
                         applet: string;
                         args: seq[string];
                         paddock: string): string {.gcsafe, raises: [].} =
  ## Execute an applet and return formatted output string.
  let r = adapter.runApplet(applet, args, paddock)
  formatAppletResult(r.output, r.exitCode)
