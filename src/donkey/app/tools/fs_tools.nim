## fs_tools.nim — paddock path resolution and bash execution.
##
## resolveInPaddock / inPaddock guard file access to the agent workspace.
## performBash runs shell commands with CWD management.

import std/[osproc, os, strutils]

# ── Paddock path helpers ─────────────────────────────────────────────────────

proc resolveInPaddock*(path, paddock: string): string =
  ## Returns an absolute path by resolving `path` relative to `paddock`,
  ## collapsing any `..` segments without following symlinks.
  let base = if isAbsolute(path): path else: paddock / path
  var parts: seq[string] = @[]
  for seg in base.split('/'):
    case seg
    of "", ".": discard
    of "..":
      if parts.len > 0: parts.setLen(parts.len - 1)
    else: parts.add(seg)
  "/" & parts.join("/")

proc inPaddock*(path, paddock: string): bool =
  ## True iff the resolved path is inside paddock (no symlink resolution).
  let norm    = resolveInPaddock(path, paddock)
  let padNorm = resolveInPaddock(paddock, paddock)
  norm == padNorm or norm.startsWith(padNorm & "/")

# ── bash ──────────────────────────────────────────────────────────────────────

proc performBash*(cmd: string; workingDir = ""): string {.gcsafe, raises: [].} =
  try:
    if workingDir.len > 0:
      createDir(workingDir)
    let (output, code) = execCmdEx(cmd,
                                   options = {poEvalCommand, poStdErrToStdOut},
                                   workingDir = workingDir)
    result = output
    if result.endsWith('\n'): result.setLen(result.len - 1)
    if code != 0:
      if result.len > 0: result.add('\n')
      result.add("[exit " & $code & "]")
    if result.len == 0:
      result = "[exit " & $code & "]"
  except CatchableError as e:
    result = "Error: " & e.msg
