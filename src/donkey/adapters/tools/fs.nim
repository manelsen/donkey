## FileSystemTools — ToolPort adapter for local file system operations.
##
## Provides safe file system access constrained to an optional workspace directory.
## All paths are validated via path_guard before any I/O operation.
##
## Tools:
##   - read_file  — read file contents as string
##   - write_file — write content to file (overwrites existing)
##   - list_dir   — list directory entries as JSON array

import std/[json, os]
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/path_guard

type
  FileSystemTools* = object
    workspace*: string  ## Optional root directory to restrict all operations.
                        ## Empty string means no restriction (uses OS cwd).

# ── Tool Schemas ───────────────────────────────────────────────────────────────

proc readFileSchema*(): ToolSchema =
  ToolSchema(
    name: "read_file",
    description: "Read the complete contents of a text file. " &
                 "Returns the raw file content as a string.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Relative or absolute path to the file to read."
        }
      },
      "required": ["path"]
    }
  )

proc writeFileSchema*(): ToolSchema =
  ToolSchema(
    name: "write_file",
    description: "Write content to a file, replacing any existing content. " &
                 "Creates parent directories if they do not exist.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Relative or absolute path to the file to write."
        },
        "content": {
          "type": "string",
          "description": "The text content to write to the file."
        }
      },
      "required": ["path", "content"]
    }
  )

proc listDirSchema*(): ToolSchema =
  ToolSchema(
    name: "list_dir",
    description: "List all entries (files and subdirectories) in a directory. " &
                 "Returns a JSON array of objects with name and type fields.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Relative or absolute path to the directory to list."
        }
      },
      "required": ["path"]
    }
  )

# ── ToolPort Conformance ───────────────────────────────────────────────────────

proc listTools*(fs: FileSystemTools): Result[seq[ToolSchema], string] =
  ok(@[readFileSchema(), writeFileSchema(), listDirSchema()])

# ── Internal Helpers ──────────────────────────────────────────────────────────

proc safePath*(fs: FileSystemTools; rawPath: string): Result[string, string] =
  ## Validates and normalizes a path through path_guard.
  ## For relative paths, prepends workspace before validation.
  ## Returns the normalized path on success, or an error string on failure.
  let pathToValidate = if fs.workspace.len > 0 and rawPath.len > 0 and rawPath[0] != '/':
    fs.workspace / rawPath
  else:
    rawPath
  let validation = validatePathAccess(pathToValidate, fs.workspace)
  if validation.ok:
    ok(validation.normalized)
  else:
    err(pathAccessErrorMsg(pathToValidate, fs.workspace))

proc readFileContent(path: string): Result[string, string] =
  ## Reads file content, returning error string on failure.
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("read_file failed: " & e.msg)

proc writeFileContent(path, content: string): Result[void, string] =
  ## Writes content to file, creating parent dirs. Returns error string on failure.
  try:
    let parent = parentDir(path)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    writeFile(path, content)
    ok()
  except CatchableError as e:
    err("write_file failed: " & e.msg)

proc listDirEntries(path: string): Result[JsonNode, string] =
  ## Lists directory entries as JSON array of {name, type} objects.
  try:
    var entries: seq[JsonNode]
    for kind, entryPath in walkDir(path):
      let name = entryPath.extractFilename
      let entryType = if kind == pcDir: "directory" else: "file"
      entries.add(%* {
        "name": name,
        "type": entryType
      })
    ok(%entries)
  except CatchableError as e:
    err("list_dir failed: " & e.msg)

# ── invoke — ToolPort method ──────────────────────────────────────────────────

proc invoke*(fs: var FileSystemTools; call: ToolCall): Result[ToolResult, string] =
  ## Routes tool call by name and executes the appropriate handler.
  ## All file operations return ToolResult with isError=false on success, or
  ## ToolResult with isError=true on normal tool errors (file not found, etc).
  ## Only truly exceptional cases (programming errors) propagate as Err.

  case call.name
  of "read_file":
    let path = call.input.getOrDefault("path")
    if path.isNil or path.kind != JString or path.getStr("").len == 0:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"missing required field: path\"}",
        isError: true
      ))
    let rawPath = path.getStr("")
    let vp = fs.safePath(rawPath)
    if vp.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & vp.error & "\"}", isError: true))
    let content = readFileContent(vp.get())
    if content.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & content.error & "\"}", isError: true))
    ok(ToolResult(callId: call.id, output: content.get(), isError: false))

  of "write_file":
    let pathNode = call.input.getOrDefault("path")
    let contentNode = call.input.getOrDefault("content")
    if pathNode.isNil or pathNode.kind != JString or pathNode.getStr("").len == 0:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"missing required field: path\"}",
        isError: true
      ))
    if contentNode.isNil:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"missing required field: content\"}",
        isError: true
      ))
    let rawPath = pathNode.getStr("")
    let vp = fs.safePath(rawPath)
    if vp.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & vp.error & "\"}", isError: true))
    let writeResult = writeFileContent(vp.get(), contentNode.getStr(""))
    if writeResult.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & writeResult.error & "\"}", isError: true))
    ok(ToolResult(callId: call.id, output: "{\"success\": true}", isError: false))

  of "list_dir":
    let path = call.input.getOrDefault("path")
    if path.isNil or path.kind != JString or path.getStr("").len == 0:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"missing required field: path\"}",
        isError: true
      ))
    let rawPath = path.getStr("")
    let vp = fs.safePath(rawPath)
    if vp.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & vp.error & "\"}", isError: true))
    let normalizedPath = vp.get()
    if not dirExists(normalizedPath):
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"list_dir failed: path is not a directory or does not exist\"}",
        isError: true
      ))
    let entries = listDirEntries(normalizedPath)
    if entries.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & entries.error & "\"}", isError: true))
    ok(ToolResult(callId: call.id, output: $entries.get(), isError: false))

  else:
    ok(ToolResult(
      callId: call.id,
      output: "{\"error\": \"unknown tool: '" & call.name & "'\"}",
      isError: true
    ))
