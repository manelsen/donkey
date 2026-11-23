## fs_tools.nim — paddock path resolution, bash execution, and structured FS ops.
##
## resolveInPaddock / inPaddock guard file access to the agent workspace.
## performBash runs shell commands with CWD management.
## performFs* expose the structured filesystem core used by the next tool family.

import std/[algorithm, json, osproc, os, sequtils, strutils]
import ../../core/pipeops
import ../../core/tooling/structured_tool_result
import ../../domain/calc
import ../../ports/fs

export StructuredToolResult, fs

# ── Paddock path helpers ─────────────────────────────────────────────────────

proc remapWorkspaceAlias(path, paddock: string): string =
  ## Maps container-visible /workspace paths back to the host paddock path so
  ## native file tools can accept paths copied from sandbox/bash output.
  if paddock.len == 0:
    return path
  if path == "/workspace":
    return paddock
  if path.startsWith("/workspace/"):
    return paddock / path["/workspace/".len .. ^1]
  path

proc resolveInPaddock*(path, paddock: string): string =
  ## Returns an absolute path by resolving `path` relative to `paddock`,
  ## collapsing any `..` segments without following symlinks.
  let logicalPath = remapWorkspaceAlias(path, paddock)
  let base = if isAbsolute(logicalPath): logicalPath else: paddock / logicalPath
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

proc resolveGuarded(path, paddock: string): tuple[ok: bool, resolved: string, err: StructuredToolResult] =
  let resolved = resolveInPaddock(path, paddock)
  if not inPaddock(path, paddock):
    return (false, resolved, usageErrorToolResult("path outside paddock: " & path))
  (true, resolved, StructuredToolResult())

proc relativeToPaddock*(path, paddock: string): string =
  let resolved = resolveInPaddock(path, paddock)
  let padNorm = resolveInPaddock(paddock, paddock)
  if resolved == padNorm:
    return "."
  if resolved.startsWith(padNorm & "/"):
    return resolved[(padNorm.len + 1) .. ^1]
  resolved

proc successPathPayload(fs: FsRuntimePort; path, paddock: string): StructuredToolResult =
  successToolResult(%*{
    "path": relativeToPaddock(path, paddock),
    "kind": $fs.entryKind(path),
  })

proc ensureParentDir(fs: FsRuntimePort; path: string): Result[void, string] =
  let parent = parentDir(path)
  if parent.len > 0 and fs.entryKind(parent) != fekDir:
    return fs.createDir(parent)
  ok()

proc listEntries(fs: FsRuntimePort; root, paddock, pattern: string;
                 recursive, includeHidden: bool;
                 items: var seq[JsonNode]): Result[void, string] =
  for entry in ? fs.listDir(root):
    let name = entry.path.extractFilename
    if not includeHidden and name.startsWith("."):
      continue
    if pattern == "*" or globMatch(pattern, name):
      items.add(%*{
        "path": relativeToPaddock(entry.path, paddock),
        "kind": $entry.kind,
        "size": entry.size,
        "mtime": entry.mtime,
      })
    if recursive and entry.kind == fekDir:
      ? listEntries(fs, entry.path, paddock, pattern, recursive, includeHidden, items)
  ok()

proc splitLogicalLines(content: string): seq[string] =
  result = content.splitLines()
  if content.endsWith("\n") and result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)

# ── structured filesystem core ───────────────────────────────────────────────
# Every operation goes through the filesystem port, so a test can run them on
# a fake; the paddock guard is checked before the port is touched.

proc performFsList*(fs: FsRuntimePort; path, paddock: string; recursive = false;
                    pattern = "*"; includeHidden = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    if fs.entryKind(guard.resolved) != fekDir:
      return operationalErrorToolResult("directory not found: " & path)
    var items: seq[JsonNode] = @[]
    let listed = listEntries(fs, guard.resolved, paddock, pattern, recursive,
                             includeHidden, items)
    if listed.isErr:
      return operationalErrorToolResult(listed.error)
    items.sort(proc(a, b: JsonNode): int = cmp(a["path"].getStr(), b["path"].getStr()))
    successToolResult(%*{
      "base_path": relativeToPaddock(guard.resolved, paddock),
      "items": items,
    })
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc performFsRead*(fs: FsRuntimePort; path, paddock: string;
                    format = "text"): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    if fs.entryKind(guard.resolved) != fekFile:
      return operationalErrorToolResult("file not found: " & path)
    let relPath = relativeToPaddock(guard.resolved, paddock)
    if format == "bytes_meta":
      let size = fs.fileSize(guard.resolved).valueOr:
        return operationalErrorToolResult(error)
      return successToolResult(%*{"path": relPath, "format": format, "size": size})
    if format notin ["text", "lines", "json"]:
      return usageErrorToolResult("unsupported fs_read format: " & format)
    let text = fs.readFile(guard.resolved).valueOr:
      return operationalErrorToolResult(error)
    case format
    of "text":
      successToolResult(%*{"path": relPath, "format": format, "text": text})
    of "lines":
      successToolResult(%*{"path": relPath, "format": format,
                           "lines": splitLogicalLines(text)})
    else:
      successToolResult(%*{"path": relPath, "format": format,
                           "value": parseJson(text)})
  except JsonParsingError as e:
    operationalErrorToolResult("invalid json: " & e.msg)
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc contentToString*(content: JsonNode; format: string): tuple[ok: bool, text: string, err: StructuredToolResult] =
  case format
  of "text":
    if content.kind != JString:
      return (false, "", usageErrorToolResult("text format requires string content"))
    (true, content.getStr(), StructuredToolResult())
  of "lines":
    if content.kind != JArray or content.getElems().anyIt(it.kind != JString):
      return (false, "", usageErrorToolResult("lines format requires an array of strings"))
    (true, content.getElems().mapIt(it.getStr()).join("\n") & "\n", StructuredToolResult())
  of "json":
    (true, $content, StructuredToolResult())
  else:
    (false, "", usageErrorToolResult("unsupported fs_write format: " & format))

proc performFsWrite*(fs: FsRuntimePort; path, paddock, mode: string; content: JsonNode;
                     format = "text"): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err

    let rendered = contentToString(content, format)
    if not rendered.ok:
      return rendered.err

    if mode notin ["create", "replace", "append"]:
      return usageErrorToolResult("unsupported fs_write mode: " & mode)
    if mode == "create" and fs.entryKind(guard.resolved) != fekMissing:
      return operationalErrorToolResult("path already exists: " & path)
    var written = ensureParentDir(fs, guard.resolved)
    if written.isOk:
      written =
        if mode == "append": fs.appendFile(guard.resolved, rendered.text)
        else: fs.writeFile(guard.resolved, rendered.text)
    if written.isErr:
      return operationalErrorToolResult(written.error)

    successToolResult(%*{
      "path": relativeToPaddock(guard.resolved, paddock),
      "kind": $fs.entryKind(guard.resolved),
      "mode": mode,
      "format": format,
      "bytes_written": rendered.text.len,
    })
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc performFsMkdir*(fs: FsRuntimePort; path, paddock: string;
                     parents = false): StructuredToolResult {.gcsafe, raises: [].} =
  ## `parents` is accepted for the schema; the directory is always created
  ## with its parents, as it was.
  discard parents
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    fs.createDir(guard.resolved).isOkOr:
      return operationalErrorToolResult(error)
    successPathPayload(fs, guard.resolved, paddock)
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc performFsCopy*(fs: FsRuntimePort; src, dst, paddock: string;
                    recursive = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let srcGuard = resolveGuarded(src, paddock)
    if not srcGuard.ok:
      return srcGuard.err
    let dstGuard = resolveGuarded(dst, paddock)
    if not dstGuard.ok:
      return dstGuard.err
    case fs.entryKind(srcGuard.resolved)
    of fekFile:
      if fs.isSymlink(dstGuard.resolved):
        return operationalErrorToolResult(
          "destination is a symlink: " & dstGuard.resolved)
      let copied = ensureParentDir(fs, dstGuard.resolved) and
                   fs.copyFile(srcGuard.resolved, dstGuard.resolved)
      if copied.isErr:
        return operationalErrorToolResult(copied.error)
    of fekDir:
      if not recursive:
        return usageErrorToolResult("copying a directory requires recursive=true")
      fs.copyTree(srcGuard.resolved, dstGuard.resolved).isOkOr:
        return operationalErrorToolResult(error)
    else:
      return operationalErrorToolResult("source not found: " & src)
    successToolResult(%*{
      "src": relativeToPaddock(srcGuard.resolved, paddock),
      "dst": relativeToPaddock(dstGuard.resolved, paddock),
      "kind": $fs.entryKind(dstGuard.resolved),
    })
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc performFsMove*(fs: FsRuntimePort; src, dst, paddock: string): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let srcGuard = resolveGuarded(src, paddock)
    if not srcGuard.ok:
      return srcGuard.err
    let dstGuard = resolveGuarded(dst, paddock)
    if not dstGuard.ok:
      return dstGuard.err
    if fs.entryKind(srcGuard.resolved) == fekMissing:
      return operationalErrorToolResult("source not found: " & src)
    let moved = ensureParentDir(fs, dstGuard.resolved) and
                fs.move(srcGuard.resolved, dstGuard.resolved)
    if moved.isErr:
      return operationalErrorToolResult(moved.error)
    successToolResult(%*{
      "src": relativeToPaddock(srcGuard.resolved, paddock),
      "dst": relativeToPaddock(dstGuard.resolved, paddock),
      "kind": $fs.entryKind(dstGuard.resolved),
    })
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

proc performFsRemove*(fs: FsRuntimePort; path, paddock: string;
                      recursive = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    let relPath = relativeToPaddock(guard.resolved, paddock)
    let kind = fs.entryKind(guard.resolved)
    case kind
    of fekFile:
      discard
    of fekDir:
      if not recursive:
        return usageErrorToolResult("removing a directory requires recursive=true")
    else:
      return operationalErrorToolResult("path not found: " & path)
    fs.remove(guard.resolved, recursive).isOkOr:
      return operationalErrorToolResult(error)
    successToolResult(%*{
      "path": relPath,
      "kind": $kind,
      "removed": true,
    })
  except CatchableError as e:
    operationalErrorToolResult(e.msg)

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
