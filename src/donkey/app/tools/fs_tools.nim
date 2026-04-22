## fs_tools.nim — paddock path resolution, bash execution, and structured FS ops.
##
## resolveInPaddock / inPaddock guard file access to the agent workspace.
## performBash runs shell commands with CWD management.
## performFs* expose the structured filesystem core used by the next tool family.

import std/[algorithm, json, osproc, os, sequtils, strutils, times]
import ../../core/tooling/structured_tool_result
import ../../domain/calc

export StructuredToolResult

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

proc relativeToPaddock(path, paddock: string): string =
  let resolved = resolveInPaddock(path, paddock)
  let padNorm = resolveInPaddock(paddock, paddock)
  if resolved == padNorm:
    return "."
  if resolved.startsWith(padNorm & "/"):
    return resolved[(padNorm.len + 1) .. ^1]
  resolved

proc entryKind(path: string): string =
  if dirExists(path): "dir"
  elif fileExists(path): "file"
  else: "missing"

proc fileMtime(path: string): int64 =
  try:
    getLastModificationTime(path).toUnix()
  except OSError:
    0'i64

proc fileSizeOrZero(path: string): int64 =
  try:
    if fileExists(path): getFileSize(path)
    else: 0'i64
  except OSError:
    0'i64

proc successPathPayload(path, paddock: string; extra: openArray[(string, JsonNode)] = []): StructuredToolResult =
  var payload = %*{
    "path": relativeToPaddock(path, paddock),
    "kind": entryKind(path),
  }
  for (key, value) in extra:
    payload[key] = value
  successToolResult(payload)

proc ensureParentDir(path: string) =
  let parent = parentDir(path)
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)

proc appendToFile(path, content: string) =
  if fileExists(path):
    writeFile(path, readFile(path) & content)
  else:
    writeFile(path, content)

proc copyTree(src, dst: string) =
  createDir(dst)
  for kind, entry in walkDir(src):
    let target = dst / entry.extractFilename
    case kind
    of pcDir:
      copyTree(entry, target)
    of pcFile:
      ensureParentDir(target)
      copyFile(entry, target)
    of pcLinkToFile, pcLinkToDir:
      discard

proc listEntries(root, paddock, pattern: string; recursive, includeHidden: bool;
                 items: var seq[JsonNode]) =
  for kind, entry in walkDir(root):
    let name = entry.extractFilename
    if not includeHidden and name.startsWith("."):
      continue
    let relPath = relativeToPaddock(entry, paddock)
    let kindLabel = case kind
      of pcDir: "dir"
      of pcFile: "file"
      of pcLinkToFile, pcLinkToDir: "link"
    if pattern == "*" or globMatch(pattern, name):
      items.add(%*{
        "path": relPath,
        "kind": kindLabel,
        "size": fileSizeOrZero(entry),
        "mtime": fileMtime(entry),
      })
    if recursive and kind == pcDir:
      listEntries(entry, paddock, pattern, recursive, includeHidden, items)

proc splitLogicalLines(content: string): seq[string] =
  result = content.splitLines()
  if content.endsWith("\n") and result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)

# ── structured filesystem core ───────────────────────────────────────────────

proc performFsList*(path, paddock: string; recursive = false;
                    pattern = "*"; includeHidden = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    if not dirExists(guard.resolved):
      return operationalErrorToolResult("directory not found: " & path)
    var items: seq[JsonNode] = @[]
    listEntries(guard.resolved, paddock, pattern, recursive, includeHidden, items)
    items.sort(proc(a, b: JsonNode): int = cmp(a["path"].getStr(), b["path"].getStr()))
    successToolResult(%*{
      "base_path": relativeToPaddock(guard.resolved, paddock),
      "items": items,
    })
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc performFsRead*(path, paddock: string; format = "text"): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    if not fileExists(guard.resolved):
      return operationalErrorToolResult("file not found: " & path)

    case format
    of "text":
      successToolResult(%*{
        "path": relativeToPaddock(guard.resolved, paddock),
        "format": format,
        "text": readFile(guard.resolved),
      })
    of "lines":
      successToolResult(%*{
        "path": relativeToPaddock(guard.resolved, paddock),
        "format": format,
        "lines": splitLogicalLines(readFile(guard.resolved)),
      })
    of "json":
      successToolResult(%*{
        "path": relativeToPaddock(guard.resolved, paddock),
        "format": format,
        "value": parseJson(readFile(guard.resolved)),
      })
    of "bytes_meta":
      successToolResult(%*{
        "path": relativeToPaddock(guard.resolved, paddock),
        "format": format,
        "size": getFileSize(guard.resolved),
      })
    else:
      usageErrorToolResult("unsupported fs_read format: " & format)
  except JsonParsingError as e:
    operationalErrorToolResult("invalid json: " & e.msg)
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc contentToString(content: JsonNode; format: string): tuple[ok: bool, text: string, err: StructuredToolResult] =
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

proc performFsWrite*(path, paddock, mode: string; content: JsonNode;
                     format = "text"): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err

    let rendered = contentToString(content, format)
    if not rendered.ok:
      return rendered.err

    case mode
    of "create":
      if fileExists(guard.resolved) or dirExists(guard.resolved):
        return operationalErrorToolResult("path already exists: " & path)
      ensureParentDir(guard.resolved)
      writeFile(guard.resolved, rendered.text)
    of "replace":
      ensureParentDir(guard.resolved)
      writeFile(guard.resolved, rendered.text)
    of "append":
      ensureParentDir(guard.resolved)
      appendToFile(guard.resolved, rendered.text)
    else:
      return usageErrorToolResult("unsupported fs_write mode: " & mode)

    successToolResult(%*{
      "path": relativeToPaddock(guard.resolved, paddock),
      "kind": entryKind(guard.resolved),
      "mode": mode,
      "format": format,
      "bytes_written": rendered.text.len,
    })
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc performFsMkdir*(path, paddock: string; parents = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    if parents:
      createDir(guard.resolved)
    else:
      createDir(guard.resolved)
    successPathPayload(guard.resolved, paddock)
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc performFsCopy*(src, dst, paddock: string; recursive = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let srcGuard = resolveGuarded(src, paddock)
    if not srcGuard.ok:
      return srcGuard.err
    let dstGuard = resolveGuarded(dst, paddock)
    if not dstGuard.ok:
      return dstGuard.err
    if fileExists(srcGuard.resolved):
      ensureParentDir(dstGuard.resolved)
      copyFile(srcGuard.resolved, dstGuard.resolved)
    elif dirExists(srcGuard.resolved):
      if not recursive:
        return usageErrorToolResult("copying a directory requires recursive=true")
      copyTree(srcGuard.resolved, dstGuard.resolved)
    else:
      return operationalErrorToolResult("source not found: " & src)
    successToolResult(%*{
      "src": relativeToPaddock(srcGuard.resolved, paddock),
      "dst": relativeToPaddock(dstGuard.resolved, paddock),
      "kind": entryKind(dstGuard.resolved),
    })
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc performFsMove*(src, dst, paddock: string): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let srcGuard = resolveGuarded(src, paddock)
    if not srcGuard.ok:
      return srcGuard.err
    let dstGuard = resolveGuarded(dst, paddock)
    if not dstGuard.ok:
      return dstGuard.err
    if not (fileExists(srcGuard.resolved) or dirExists(srcGuard.resolved)):
      return operationalErrorToolResult("source not found: " & src)
    ensureParentDir(dstGuard.resolved)
    if dirExists(srcGuard.resolved):
      moveDir(srcGuard.resolved, dstGuard.resolved)
    else:
      moveFile(srcGuard.resolved, dstGuard.resolved)
    successToolResult(%*{
      "src": relativeToPaddock(srcGuard.resolved, paddock),
      "dst": relativeToPaddock(dstGuard.resolved, paddock),
      "kind": entryKind(dstGuard.resolved),
    })
  except Exception as e:
    operationalErrorToolResult(e.msg)

proc performFsRemove*(path, paddock: string; recursive = false): StructuredToolResult {.gcsafe, raises: [].} =
  try:
    let guard = resolveGuarded(path, paddock)
    if not guard.ok:
      return guard.err
    let relPath = relativeToPaddock(guard.resolved, paddock)
    let kind = entryKind(guard.resolved)
    case kind
    of "file":
      removeFile(guard.resolved)
    of "dir":
      if not recursive:
        return usageErrorToolResult("removing a directory requires recursive=true")
      removeDir(guard.resolved)
    else:
      return operationalErrorToolResult("path not found: " & path)
    successToolResult(%*{
      "path": relPath,
      "kind": kind,
      "removed": true,
    })
  except Exception as e:
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
