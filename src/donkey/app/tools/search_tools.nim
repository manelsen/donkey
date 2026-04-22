## search_tools.nim — find and grep over the filesystem.
##
## NOTE: grep uses literal substring search (case-sensitive).
## For full regex, use bash("grep -rn 'pattern' /path") instead.
##
## All three internal traversal procs (walkFind, grepFile, grepDir) log
## warnings on CatchableError instead of silently discarding them.

import std/[json, os, strutils, sequtils]
import ../../core/log
import ../../core/tooling/structured_tool_result
import ../../domain/calc  # globMatch
import ../../infra/sandbox/wasm_tools

let searchLog = newLogger("donkey.tools.search")

# ── find ──────────────────────────────────────────────────────────────────────

proc walkFind(path, pattern, kind: string; max: int;
              results: var seq[string]) {.gcsafe, raises: [].} =
  if results.len >= max: return
  try:
    for entry in walkDir(path):
      let name = splitPath(entry.path).tail
      case entry.kind
      of pcFile:
        if kind != "dir" and globMatch(pattern, name):
          results.add(entry.path)
          if results.len >= max: return
      of pcDir:
        if kind != "file" and globMatch(pattern, name):
          results.add(entry.path & "/")
          if results.len >= max: return
        walkFind(entry.path, pattern, kind, max, results)
      of pcLinkToFile, pcLinkToDir:
        discard  ## skip symlinks — prevents escaping the paddock
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("walkFind error at " & path & ": " & e.msg)

proc performFind*(path, pattern, kind: string; max: int): string {.gcsafe, raises: [].} =
  var results: seq[string] = @[]
  walkFind(path, pattern, kind, max, results)
  if results.len == 0: return "(no matches)"
  results.join("\n")

proc addFindItem(path: string; kind: string; max: int; items: var seq[JsonNode]) {.gcsafe, raises: [].} =
  if items.len < max:
    items.add(%*{"path": path, "kind": kind})

proc walkFindStructured(path, pattern, kind: string; max: int;
                        items: var seq[JsonNode]) {.gcsafe, raises: [].} =
  if items.len >= max: return
  try:
    for entry in walkDir(path):
      let name = splitPath(entry.path).tail
      case entry.kind
      of pcFile:
        if kind != "dir" and globMatch(pattern, name):
          addFindItem(entry.path, "file", max, items)
          if items.len >= max: return
      of pcDir:
        if kind != "file" and globMatch(pattern, name):
          addFindItem(entry.path & "/", "dir", max, items)
          if items.len >= max: return
        walkFindStructured(entry.path, pattern, kind, max, items)
      of pcLinkToFile, pcLinkToDir:
        discard
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("walkFindStructured error at " & path & ": " & e.msg)

proc performFindStructured*(path, pattern, kind: string; max: int): StructuredToolResult {.gcsafe, raises: [].} =
  if path.strip().len == 0:
    return usageErrorToolResult("path is required")
  if pattern.strip().len == 0:
    return usageErrorToolResult("pattern is required")
  if max < 1:
    return usageErrorToolResult("max must be >= 1")
  let normalizedKind = if kind.len == 0: "any" else: kind
  if normalizedKind notin ["any", "file", "dir"]:
    return usageErrorToolResult("kind must be one of: any, file, dir")
  if not dirExists(path) and not fileExists(path):
    return operationalErrorToolResult("path not found: " & path)

  var items: seq[JsonNode] = @[]
  if fileExists(path):
    let fileKind =
      if normalizedKind == "dir": ""
      else: "file"
    if fileKind.len > 0 and globMatch(pattern, splitPath(path).tail):
      addFindItem(path, fileKind, max, items)
  else:
    walkFindStructured(path, pattern, if normalizedKind == "any": "" else: normalizedKind, max, items)

  successToolResult(%*{
    "path": path,
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

proc grepFile(path, pattern: string; max: int;
              results: var seq[string]) {.gcsafe, raises: [].} =
  try:
    var lineNum = 0
    for line in lines(path):
      inc lineNum
      if line.find(pattern) >= 0:
        results.add(path & ":" & $lineNum & ":" & line)
        if results.len >= max: return
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("grepFile error on " & path & ": " & e.msg)

proc grepDir(path, pattern: string; recursive: bool;
             max: int; results: var seq[string]) {.gcsafe, raises: [].} =
  try:
    for entry in walkDir(path):
      if results.len >= max: return
      case entry.kind
      of pcFile:
        grepFile(entry.path, pattern, max, results)
      of pcDir:
        if recursive:
          grepDir(entry.path, pattern, recursive, max, results)
      of pcLinkToFile, pcLinkToDir:
        discard  ## skip symlinks — prevents escaping the paddock
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("grepDir error at " & path & ": " & e.msg)

proc performGrep*(pattern, path: string; recursive: bool;
                  max: int): string {.gcsafe, raises: [].} =
  if pattern.len == 0: return "Error: empty pattern"
  var results: seq[string] = @[]
  if fileExists(path):
    grepFile(path, pattern, max, results)
  elif dirExists(path):
    grepDir(path, pattern, recursive, max, results)
  else:
    return "Error: path not found: " & path
  if results.len == 0: return "(no matches)"
  results.join("\n")

proc grepFileStructured(path, pattern: string; max: int;
                        matches: var seq[JsonNode]) {.gcsafe, raises: [].} =
  try:
    var lineNum = 0
    for line in lines(path):
      inc lineNum
      if line.find(pattern) >= 0:
        matches.add(%*{
          "path": path,
          "line": lineNum,
          "text": line,
        })
        if matches.len >= max: return
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("grepFileStructured error on " & path & ": " & e.msg)

proc grepDirStructured(path, pattern: string; recursive: bool; max: int;
                       matches: var seq[JsonNode]) {.gcsafe, raises: [].} =
  try:
    for entry in walkDir(path):
      if matches.len >= max: return
      case entry.kind
      of pcFile:
        grepFileStructured(entry.path, pattern, max, matches)
      of pcDir:
        if recursive:
          grepDirStructured(entry.path, pattern, recursive, max, matches)
      of pcLinkToFile, pcLinkToDir:
        discard
  except CatchableError as e:
    {.cast(gcsafe).}:
      searchLog.warn("grepDirStructured error at " & path & ": " & e.msg)

proc performGrepStructured*(pattern, path: string; recursive: bool;
                            max: int): StructuredToolResult {.gcsafe, raises: [].} =
  if pattern.len == 0:
    return usageErrorToolResult("empty pattern")
  if path.strip().len == 0:
    return usageErrorToolResult("path is required")
  if max < 1:
    return usageErrorToolResult("max must be >= 1")
  if not fileExists(path) and not dirExists(path):
    return operationalErrorToolResult("path not found: " & path)

  var matches: seq[JsonNode] = @[]
  if fileExists(path):
    grepFileStructured(path, pattern, max, matches)
  else:
    grepDirStructured(path, pattern, recursive, max, matches)

  successToolResult(%*{
    "path": path,
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
