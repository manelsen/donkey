## search_tools.nim — find and grep over the filesystem port.
##
## NOTE: grep uses literal substring search (case-sensitive).
## For full regex, use bash("grep -rn 'pattern' /path") instead.
##
## One walk per tool (`findHits`, `grepHits`) feeds both the text and the
## structured result. A directory or file that cannot be read is logged and
## skipped; symlinks are never followed, so a search cannot leave the paddock.

import std/[json, os, strutils, sequtils]
import ../../core/log
import ../../core/pipeops
import ../../core/tooling/structured_tool_result
import ../../domain/calc  # globMatch
import ../../infra/sandbox/wasm_tools
import ../../ports/fs
import ./fs_tools

const
  GrepMaxFileBytes* = 32 * 1024 * 1024
    ## A file is read whole to be searched; a bigger one is skipped.

template searchLog(): Logger =
  ## Built where it is used: a global Logger holds GC memory, which made
  ## every call site need {.cast(gcsafe).}. `newLogger` is a cheap func.
  newLogger("donkey.tools.search")

# ── find ──────────────────────────────────────────────────────────────────────

type FindHit = object
  path:  string
  isDir: bool

proc walkFind(fs: FsRuntimePort; path, pattern, kind: string; max: int;
              hits: var seq[FindHit]) {.gcsafe, raises: [].} =
  ## `kind` is "file", "dir" or "" for both.
  if hits.len >= max: return
  let entries = fs.listDir(path).valueOr:
    searchLog().warn("find: cannot list " & path & ": " & error)
    return
  for entry in entries:
    let name = splitPath(entry.path).tail
    case entry.kind
    of fekFile:
      if kind != "dir" and globMatch(pattern, name):
        hits.add FindHit(path: entry.path)
        if hits.len >= max: return
    of fekDir:
      if kind != "file" and globMatch(pattern, name):
        hits.add FindHit(path: entry.path, isDir: true)
        if hits.len >= max: return
      walkFind(fs, entry.path, pattern, kind, max, hits)
    of fekLink, fekMissing:
      discard  ## skip symlinks — prevents escaping the paddock

proc performFind*(fs: FsRuntimePort; path, pattern, kind: string;
                  max: int): string {.gcsafe, raises: [].} =
  var hits: seq[FindHit] = @[]
  walkFind(fs, path, pattern, kind, max, hits)
  if hits.len == 0: return "(no matches)"
  hits.mapIt(if it.isDir: it.path & "/" else: it.path).join("\n")

proc performFindStructured*(fs: FsRuntimePort; path, pattern, kind: string; max: int;
                            paddock = ""): StructuredToolResult {.gcsafe, raises: [].} =
  if path.strip().len == 0:
    return usageErrorToolResult("path is required")
  if pattern.strip().len == 0:
    return usageErrorToolResult("pattern is required")
  if max < 1:
    return usageErrorToolResult("max must be >= 1")
  let normalizedKind = if kind.len == 0: "any" else: kind
  if normalizedKind notin ["any", "file", "dir"]:
    return usageErrorToolResult("kind must be one of: any, file, dir")
  let pathKind = fs.entryKind(path)
  if pathKind == fekMissing:
    return operationalErrorToolResult("path not found: " & path)

  var items: seq[JsonNode] = @[]
  if pathKind == fekFile:
    if normalizedKind != "dir" and globMatch(pattern, splitPath(path).tail):
      let base = if paddock.len > 0: paddock else: parentDir(path)
      items.add(%*{"path": relativeToPaddock(path, base), "kind": "file"})
  else:
    var hits: seq[FindHit] = @[]
    walkFind(fs, path, pattern, if normalizedKind == "any": "" else: normalizedKind,
             max, hits)
    let base = if paddock.len > 0: paddock else: path
    for hit in hits:
      items.add(%*{
        "path": relativeToPaddock(if hit.isDir: hit.path & "/" else: hit.path, base),
        "kind": if hit.isDir: "dir" else: "file",
      })

  successToolResult(%*{
    "path": if paddock.len > 0: relativeToPaddock(path, paddock) else: path,
    "pattern": pattern,
    "kind": normalizedKind,
    "count": items.len,
    "items": items,
  })

proc performFindWasm*(path, pattern, kind: string; max: int): string {.gcsafe, raises: [].} =
  ## Find via WASM (go-busybox) — sandboxed execution.
  let adapter = newWasmToolAdapter()
  var args: seq[string] = @[path]
  if pattern != "*":
    args.add("-name")
    args.add(pattern)
  if kind == "file":
    args.add("-type")
    args.add("f")
  elif kind == "dir":
    args.add("-type")
    args.add("d")
  let parent = path.parentDir
  let r = adapter.runApplet("find", args, if parent.len > 0: parent else: "/")
  if not r.success:
    if r.output.len == 0: return "(no matches)"
    return "Error: " & r.output
  let lines = r.output.splitLines().filterIt(it.len > 0)
  if lines.len == 0: return "(no matches)"
  if lines.len > max:
    lines[0 ..< max].join("\n") & "\n... (" & $lines.len & " results, showing " & $max & ")"
  else:
    lines.join("\n")

# ── grep ──────────────────────────────────────────────────────────────────────

type GrepHit = object
  path: string
  line: int
  text: string

proc grepFile(fs: FsRuntimePort; path, pattern: string; max: int;
              hits: var seq[GrepHit]) {.gcsafe, raises: [].} =
  let size = fs.fileSize(path).valueOr:
    searchLog().warn("grep: cannot inspect " & path & ": " & error)
    return
  if size > GrepMaxFileBytes:
    searchLog().warn("grep: skipping " & path & " (" & $size & " bytes)")
    return
  let text = fs.readFile(path).valueOr:
    searchLog().warn("grep: cannot read " & path & ": " & error)
    return
  var lineNum = 0
  for line in text.splitLines():
    inc lineNum
    if line.find(pattern) >= 0:
      hits.add GrepHit(path: path, line: lineNum, text: line)
      if hits.len >= max: return

proc grepDir(fs: FsRuntimePort; path, pattern: string; recursive: bool;
             max: int; hits: var seq[GrepHit]) {.gcsafe, raises: [].} =
  let entries = fs.listDir(path).valueOr:
    searchLog().warn("grep: cannot list " & path & ": " & error)
    return
  for entry in entries:
    if hits.len >= max: return
    case entry.kind
    of fekFile:
      grepFile(fs, entry.path, pattern, max, hits)
    of fekDir:
      if recursive:
        grepDir(fs, entry.path, pattern, recursive, max, hits)
    of fekLink, fekMissing:
      discard  ## skip symlinks — prevents escaping the paddock

proc grepHits(fs: FsRuntimePort; pattern, path: string; recursive: bool;
              max: int): Result[seq[GrepHit], string] {.gcsafe, raises: [].} =
  var hits: seq[GrepHit] = @[]
  case fs.entryKind(path)
  of fekFile: grepFile(fs, path, pattern, max, hits)
  of fekDir: grepDir(fs, path, pattern, recursive, max, hits)
  else: return err("path not found: " & path)
  ok(hits)

proc performGrep*(fs: FsRuntimePort; pattern, path: string; recursive: bool;
                  max: int): string {.gcsafe, raises: [].} =
  if pattern.len == 0: return "Error: empty pattern"
  let hits = grepHits(fs, pattern, path, recursive, max).valueOr:
    return "Error: " & error
  if hits.len == 0: return "(no matches)"
  hits.mapIt(it.path & ":" & $it.line & ":" & it.text).join("\n")

proc performGrepStructured*(fs: FsRuntimePort; pattern, path: string; recursive: bool;
                            max: int; paddock = ""): StructuredToolResult {.gcsafe, raises: [].} =
  if pattern.len == 0:
    return usageErrorToolResult("empty pattern")
  if path.strip().len == 0:
    return usageErrorToolResult("path is required")
  if max < 1:
    return usageErrorToolResult("max must be >= 1")
  let pathKind = fs.entryKind(path)
  let hits = grepHits(fs, pattern, path, recursive, max).valueOr:
    return operationalErrorToolResult(error)
  let base =
    if paddock.len > 0: paddock
    elif pathKind == fekFile: parentDir(path)
    else: path
  var matches: seq[JsonNode] = @[]
  for hit in hits:
    matches.add(%*{"path": relativeToPaddock(hit.path, base), "line": hit.line,
                   "text": hit.text})

  successToolResult(%*{
    "path": if paddock.len > 0: relativeToPaddock(path, paddock) else: path,
    "pattern": pattern,
    "recursive": recursive,
    "count": matches.len,
    "matches": matches,
  })

proc performGrepWasm*(pattern, path: string; recursive: bool;
                      max: int): string {.gcsafe, raises: [].} =
  ## Grep via WASM (go-busybox) — sandboxed execution.
  if pattern.len == 0: return "Error: empty pattern"
  let adapter = newWasmToolAdapter()
  var args: seq[string] = @["-n"]
  if recursive:
    args.add("-r")
  args.add(pattern)
  args.add(path)
  let r = adapter.runApplet("grep", args, path.extractFilename.parentDir)
  if not r.success:
    if r.exitCode == 1: return "(no matches)"
    return "Error: " & r.output
  let lines = r.output.splitLines()
  if lines.len > max:
    lines[0 ..< max].join("\n") & "\n... (" & $lines.len & " matches, showing " & $max & ")"
  else:
    r.output.strip()
