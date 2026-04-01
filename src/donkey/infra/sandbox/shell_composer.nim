## infra/sandbox/shell_composer — pipe composition via WASM applets.
##
## Since WASI lacks fork/exec, real pipes don't work inside WASM.
## This module composes pipes by chaining WASM applet calls in Nim:
## the stdout of one applet is written to a temp file, which is passed
## as the input file argument to the next applet.
##
## Usage:
##   let adapter = newWasmToolAdapter()
##   let result = adapter.compose("cat data.txt | grep foo | sort | head -n 10", "/workspace")
##
## Supported: cat, grep, sed, head, tail, sort, wc, uniq, cut, tr, diff, echo, ls, find
## Limitations: no redirections (>, >>), no here-strings, no subshells ($()), no && ||

import std/[os, strutils, tempfiles]
import ./wasm_tools

# ── Types ─────────────────────────────────────────────────────────────────────

type
  PipeSegment* = object
    ## A single command in a pipe chain.
    applet*: string
    args*:   seq[string]

func `$`*(seg: PipeSegment): string =
  seg.applet & " " & seg.args.join(" ")

# ── Parser ────────────────────────────────────────────────────────────────────

proc splitArgs(cmd: string): seq[string] =
  ## Split a command string into tokens, respecting double quotes.
  var tokens: seq[string] = @[]
  var current = ""
  var inQuote = false
  var i = 0
  while i < cmd.len:
    let c = cmd[i]
    if c == '"' and not inQuote:
      inQuote = true
    elif c == '"' and inQuote:
      inQuote = false
    elif c == ' ' and not inQuote:
      if current.len > 0:
        tokens.add(current)
        current = ""
    else:
      current.add(c)
    inc i
  if current.len > 0:
    tokens.add(current)
  tokens

proc parsePipeExpr*(expr: string): seq[PipeSegment] =
  ## Parse a pipe expression like "cat file.txt | grep foo | sort".
  let trimmed = expr.strip()
  if trimmed.len == 0:
    return @[]
  let stages = trimmed.split("|")
  for stage in stages:
    let tokens = splitArgs(stage.strip())
    if tokens.len > 0:
      result.add(PipeSegment(applet: tokens[0], args: tokens[1 .. ^1]))

# ── Stdin detection ───────────────────────────────────────────────────────────

proc hasFileArg(args: seq[string]): bool =
  ## Check if the args contain a file path argument.
  ## Heuristic: an arg that doesn't start with '-' and contains a path separator
  ## or a dot (for extensions like .txt).
  for a in args:
    if a.len > 0 and a[0] != '-':
      if '/' in a or '.' in a:
        return true
  false

proc needsStdin*(applet: string; args: seq[string]): bool =
  ## Returns true if the applet needs stdin (no file argument provided).
  ## Applets like grep, sort, head, tail, wc, uniq, cat read from stdin
  ## when no file argument is given.
  case applet
  of "cat", "grep", "sed", "head", "tail", "sort", "wc", "uniq", "cut", "tr",
     "diff", "awk":
    not hasFileArg(args)
  of "echo", "printf", "ls", "find", "mkdir", "cp", "mv", "rm", "pwd":
    false  # these don't read from stdin
  else:
    # Conservative: assume it needs stdin if no file arg
    not hasFileArg(args)

# ── Pipe composition ──────────────────────────────────────────────────────────

proc compose*(adapter: WasmToolAdapter;
              expr: string;
              paddock: string): AppletResult {.gcsafe, raises: [].} =
  ## Compose a pipe expression and execute it via WASM applets.
  ## Each stage's stdout becomes the next stage's input (via temp file).
  let segments = parsePipeExpr(expr)
  if segments.len == 0:
    return AppletResult(exitCode: 0, output: "", success: true)

  # Single command — no pipe needed
  if segments.len == 1:
    return adapter.runApplet(segments[0].applet, segments[0].args, paddock)

  var currentOutput = ""
  var tmpPath: string
  try:
    var tmpFile: File
    (tmpFile, tmpPath) = createTempFile("donkey_pipe_", ".txt")
    tmpFile.close()
  except CatchableError as e:
    return AppletResult(exitCode: -1, output: "Error: " & e.msg, success: false)

  defer:
    try:
      if tmpPath.fileExists:
        removeFile(tmpPath)
    except CatchableError:
      discard

  for i, seg in segments:
    var args = seg.args

    # If this segment needs stdin and it's not the first stage,
    # inject the temp file as input
    if i > 0 and needsStdin(seg.applet, seg.args):
      args.add(tmpPath)

    let r = adapter.runApplet(seg.applet, args, paddock)

    if not r.success and r.exitCode != 0:
      # grep returns exitCode 1 for no match — that's OK in a pipe
      if seg.applet == "grep" and r.exitCode == 1 and r.output.len == 0:
        currentOutput = ""
      else:
        return r

    currentOutput = r.output

    # Write output to temp file for next stage
    if i < segments.len - 1:
      try:
        writeFile(tmpPath, currentOutput)
      except CatchableError:
        discard

  # Strip trailing newline from final output
  result = AppletResult(exitCode: 0, output: currentOutput, success: true)
  if result.output.endsWith('\n'):
    result.output.setLen(result.output.len - 1)

proc composeFormatted*(adapter: WasmToolAdapter;
                       expr: string;
                       paddock: string): string {.gcsafe, raises: [].} =
  ## Compose a pipe expression and return formatted output string.
  let r = adapter.compose(expr, paddock)
  formatAppletResult(r.output, r.exitCode)
