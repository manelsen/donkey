## Tests for FileSystemTools adapter — ToolPort implementation for file system access.
##
## Tests cover:
##   - ToolPort concept conformance (listTools, invoke)
##   - Path traversal blocking (../, absolute escapes)
##   - Workspace restriction enforcement
##   - Each tool's input validation and output format
##   - Error handling without exceptions

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/tools/fs
import donkey/ports/tool
import donkey/core/pipeops

# ── Test fixtures ──────────────────────────────────────────────────────────────

proc cleanupTmpDir(d: string) =
  ## Cleanup helper - removes directory and all contents.
  if dirExists(d):
    for kind, path in walkDir(d, relative = false):
      if kind == pcDir:
        cleanupTmpDir(path)
      else:
        removeFile(path)
    removeDir(d)

func jsonArrayContains(arr: JsonNode; value: string): bool =
  ## Check if a JSON array contains a string value.
  assert arr.kind == JArray, "jsonArrayContains requires JArray"
  for item in arr:
    if item.kind == JString and item.getStr == value:
      return true
  false

template withTempDir*(tmpDir: untyped; body: untyped): untyped =
  ## Creates a temporary directory, runs body, cleans up.
  ## tmpDir must be an identifier that will be bound to the temp directory path.
  block:
    let d = getTempDir() / "donkey_fs_test_" & $nowMs()
    createDir(d)
    defer:
      cleanupTmpDir(d)
    mixin tmpDir
    let tmpDir = d
    body

template withWorkspace*(wsDir: untyped; body: untyped): untyped =
  ## Creates a temp dir as workspace, runs body, cleans up.
  ## wsDir must be an identifier that will be bound to the workspace directory path.
  block:
    let d = getTempDir() / "donkey_fs_ws_" & $nowMs()
    createDir(d)
    defer:
      cleanupTmpDir(d)
    mixin wsDir
    let wsDir = d
    body

# ── Concept conformance ───────────────────────────────────────────────────────

suite "ToolPort conformance":

  test "FileSystemTools satisfies ToolPort concept":
    ## Compile-time proof: FileSystemTools implements ToolPort.
    ## If this test file compiles, the concept is satisfied.
    var fs = FileSystemTools()
    let tools = fs.listTools()
    check tools.isOk
    # invoke returns Result - even errors are isOk=false, not exceptions
    let call = ToolCall(id: "test", name: "unknown_tool", input: %* {})
    let res = fs.invoke(call)
    check res.isOk  # Result type is ok, even if the tool is unknown

  test "listTools returns exactly three schemas":
    let fs = FileSystemTools()
    let result = fs.listTools()
    check result.isOk
    let tools = result.get()
    check tools.len == 3
    let names = tools.mapIt(it.name)
    check "read_file" in names
    check "write_file" in names
    check "list_dir" in names

  test "listTools schemas have required fields":
    let fs = FileSystemTools()
    let tools = fs.listTools().get()
    for tool in tools:
      check tool.name.len > 0
      check tool.description.len > 0
      check tool.inputSchema.kind == JObject
      check tool.inputSchema.hasKey("type")
      check tool.inputSchema.hasKey("properties")

  test "read_file schema properties":
    let fs = FileSystemTools()
    let tools = fs.listTools().get()
    let schema = tools.filterIt(it.name == "read_file")[0]
    check schema.inputSchema["properties"].hasKey("path")
    check jsonArrayContains(schema.inputSchema["required"], "path")

  test "write_file schema properties":
    let fs = FileSystemTools()
    let tools = fs.listTools().get()
    let schema = tools.filterIt(it.name == "write_file")[0]
    check schema.inputSchema["properties"].hasKey("path")
    check schema.inputSchema["properties"].hasKey("content")
    let required = schema.inputSchema["required"]
    check jsonArrayContains(required, "path")
    check jsonArrayContains(required, "content")

  test "list_dir schema properties":
    let fs = FileSystemTools()
    let tools = fs.listTools().get()
    let schema = tools.filterIt(it.name == "list_dir")[0]
    check schema.inputSchema["properties"].hasKey("path")
    check jsonArrayContains(schema.inputSchema["required"], "path")

# ── read_file tests ───────────────────────────────────────────────────────────

suite "read_file":

  test "reads existing file content":
    withTempDir(tmpDir):
      let filePath = tmpDir / "hello.txt"
      writeFile(filePath, "Hello, World!")
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-1", name: "read_file", input: %* {"path": filePath})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-1"
      check tr.isError == false
      check tr.output == "Hello, World!"

  test "returns error for missing file":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-2", name: "read_file", input: %* {"path": tmpDir / "nonexistent.txt"})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("error")

  test "returns error for missing path field":
    var fs = FileSystemTools()
    let call = ToolCall(id: "call-3", name: "read_file", input: %* {})
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("missing required field")

  test "returns error for empty path":
    var fs = FileSystemTools()
    let call = ToolCall(id: "call-4", name: "read_file", input: %* {"path": ""})
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true

  test "blocks path traversal attempt":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      # Path contains .. which should be blocked by isPathTraversalAttempt
      let call = ToolCall(id: "call-5", name: "read_file", input: %* {"path": ".." / ".." / ".." / "etc" / "passwd"})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      # The path contains ../ which is detected by isPathTraversalAttempt
      check tr.output.contains("traversal")

  test "blocks simple ../ escape":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-6", name: "read_file", input: %* {"path": ".."})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("traversal")

  test "relative path within current dir works":
    withTempDir(tmpDir):
      let curDir = getCurrentDir()
      setCurrentDir(tmpDir)
      try:
        let filePath = "test_file.txt"
        writeFile(filePath, "relative content")
        var fs = FileSystemTools()
        let call = ToolCall(id: "call-7", name: "read_file", input: %* {"path": filePath})
        let result = fs.invoke(call)
        check result.isOk
        let tr = result.get()
        check tr.isError == false
        check tr.output == "relative content"
      finally:
        setCurrentDir(curDir)

# ── write_file tests ──────────────────────────────────────────────────────────

suite "write_file":

  test "writes content to new file":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(
        id: "call-w1",
        name: "write_file",
        input: %* {"path": tmpDir / "new_file.txt", "content": "file content here"}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check tr.output.contains("success")
      # Verify file was written
      check fileExists(tmpDir / "new_file.txt")
      check readFile(tmpDir / "new_file.txt") == "file content here"

  test "overwrites existing file":
    withTempDir(tmpDir):
      let filePath = tmpDir / "existing.txt"
      writeFile(filePath, "original")
      var fs = FileSystemTools()
      let call = ToolCall(
        id: "call-w2",
        name: "write_file",
        input: %* {"path": filePath, "content": "updated"}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check readFile(filePath) == "updated"

  test "creates parent directories":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let nested = tmpDir / "a" / "b" / "c" / "deep.txt"
      let call = ToolCall(
        id: "call-w3",
        name: "write_file",
        input: %* {"path": nested, "content": "nested"}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check fileExists(nested)

  test "returns error for missing path":
    var fs = FileSystemTools()
    let call = ToolCall(
      id: "call-w4",
      name: "write_file",
      input: %* {"content": "no path"}
    )
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("missing required field")

  test "returns error for missing content":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(
        id: "call-w5",
        name: "write_file",
        input: %* {"path": tmpDir / "test.txt"}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("missing required field")

  test "blocks path traversal":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      # Path contains .. which should be blocked by isPathTraversalAttempt
      let call = ToolCall(
        id: "call-w6",
        name: "write_file",
        input: %* {"path": ".." / ".." / ".." / "tmp" / "evil.txt", "content": "evil"}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("traversal")

  test "writes empty content":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(
        id: "call-w7",
        name: "write_file",
        input: %* {"path": tmpDir / "empty.txt", "content": ""}
      )
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check fileExists(tmpDir / "empty.txt")
      check readFile(tmpDir / "empty.txt") == ""

# ── list_dir tests ────────────────────────────────────────────────────────────

suite "list_dir":

  test "lists directory entries":
    withTempDir(tmpDir):
      createDir(tmpDir / "subdir")
      writeFile(tmpDir / "file1.txt", "")
      writeFile(tmpDir / "file2.md", "")
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-l1", name: "list_dir", input: %* {"path": tmpDir})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      let entries = parseJson(tr.output)
      check entries.kind == JArray
      let names = entries.mapIt(it["name"].getStr)
      check "subdir" in names
      check "file1.txt" in names
      check "file2.md" in names
      let subdirEntry = entries.filterIt(it["name"].getStr == "subdir")[0]
      check subdirEntry["type"].getStr == "directory"
      let fileEntry = entries.filterIt(it["name"].getStr == "file1.txt")[0]
      check fileEntry["type"].getStr == "file"

  test "returns empty array for empty directory":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-l2", name: "list_dir", input: %* {"path": tmpDir})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      let entries = parseJson(tr.output)
      check entries.kind == JArray
      check entries.len == 0

  test "returns error for missing path":
    var fs = FileSystemTools()
    let call = ToolCall(id: "call-l3", name: "list_dir", input: %* {})
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("missing required field")

  test "returns error for non-directory path":
    withTempDir(tmpDir):
      let filePath = tmpDir / "regular_file.txt"
      writeFile(filePath, "content")
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-l4", name: "list_dir", input: %* {"path": filePath})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("list_dir failed")

  test "blocks path traversal":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      # Path contains .. which should be blocked by isPathTraversalAttempt
      let call = ToolCall(id: "call-l5", name: "list_dir", input: %* {"path": ".." / ".." / ".." / "etc"})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("traversal")

  test "returns error for nonexistent directory":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(id: "call-l6", name: "list_dir", input: %* {"path": tmpDir / "does_not_exist"})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true

# ── workspace restriction tests ───────────────────────────────────────────────

suite "workspace restriction":

  test "read_file restricted to workspace":
    withWorkspace(wsDir):
      # Create a file inside workspace
      let insidePath = wsDir / "inside.txt"
      writeFile(insidePath, "inside workspace")
      # Create a file outside workspace
      let outsideDir = getTempDir() / "donkey_fs_outside_" & $nowMs()
      createDir(outsideDir)
      let outsidePath = outsideDir / "outside.txt"
      writeFile(outsidePath, "outside workspace")
      defer:
        if dirExists(outsideDir):
          cleanupTmpDir(outsideDir)

      var fs = FileSystemTools(workspace: wsDir)
      
      # Inside workspace should work
      let callIn = ToolCall(id: "call-rs1", name: "read_file", input: %* {"path": "inside.txt"})
      let resultIn = fs.invoke(callIn)
      check resultIn.isOk
      check resultIn.get().isError == false

      # Outside workspace should be blocked
      let callOut = ToolCall(id: "call-rs2", name: "read_file", input: %* {"path": outsidePath})
      let resultOut = fs.invoke(callOut)
      check resultOut.isOk
      let trOut = resultOut.get()
      check trOut.isError == true
      check trOut.output.contains("outside")

  test "write_file restricted to workspace":
    withWorkspace(wsDir):
      var fs = FileSystemTools(workspace: wsDir)
      
      # Writing inside workspace should work
      let callIn = ToolCall(
        id: "call-ws1",
        name: "write_file",
        input: %* {"path": "allowed.txt", "content": "allowed"}
      )
      let resultIn = fs.invoke(callIn)
      check resultIn.isOk
      check resultIn.get().isError == false
      check fileExists(wsDir / "allowed.txt")

      # Writing outside workspace should be blocked
      let outsideDir = getTempDir() / "donkey_fs_outside_w_" & $nowMs()
      createDir(outsideDir)
      let outsidePath = outsideDir / "blocked.txt"
      defer:
        if dirExists(outsideDir):
          cleanupTmpDir(outsideDir)

      let callOut = ToolCall(
        id: "call-ws2",
        name: "write_file",
        input: %* {"path": outsidePath, "content": "blocked"}
      )
      let resultOut = fs.invoke(callOut)
      check resultOut.isOk
      let trOut = resultOut.get()
      check trOut.isError == true
      check trOut.output.contains("outside")

  test "list_dir restricted to workspace":
    withWorkspace(wsDir):
      createDir(wsDir / "allowed_subdir")
      var fs = FileSystemTools(workspace: wsDir)
      
      # Listing inside workspace should work
      let callIn = ToolCall(id: "call-ls1", name: "list_dir", input: %* {"path": "allowed_subdir"})
      let resultIn = fs.invoke(callIn)
      check resultIn.isOk
      check resultIn.get().isError == false

      # Listing outside workspace should be blocked
      let callOut = ToolCall(id: "call-ls2", name: "list_dir", input: %* {"path": "/tmp"})
      let resultOut = fs.invoke(callOut)
      check resultOut.isOk
      let trOut = resultOut.get()
      check trOut.isError == true

  test "workspace with relative path":
    withWorkspace(wsDir):
      let innerDir = wsDir / "inner"
      createDir(innerDir)
      writeFile(innerDir / "file.txt", "content")
      
      # Use relative path within workspace
      var fs = FileSystemTools(workspace: wsDir)
      let call = ToolCall(id: "call-rel", name: "read_file", input: %* {"path": "inner/file.txt"})
      let result = fs.invoke(call)
      check result.isOk
      check result.get().isError == false
      check result.get().output == "content"

  test "workspace with .. in relative path escapes":
    withWorkspace(wsDir):
      var fs = FileSystemTools(workspace: wsDir)
      let call = ToolCall(id: "call-escape", name: "read_file", input: %* {"path": "inner/../../etc/passwd"})
      let result = fs.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == true
      check tr.output.contains("outside")  # path escapes workspace after normalization

# ── unknown tool tests ─────────────────────────────────────────────────────────

suite "unknown tool":

  test "invoke returns error for unknown tool":
    var fs = FileSystemTools()
    let call = ToolCall(id: "call-unk", name: "nonexistent_tool", input: %* {})
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("unknown tool")
    check tr.output.contains("nonexistent_tool")

  test "invoke returns error for empty tool name":
    var fs = FileSystemTools()
    let call = ToolCall(id: "call-empty", name: "", input: %* {})
    let result = fs.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("unknown tool")

# ── call id preservation ───────────────────────────────────────────────────────

suite "call id preservation":

  test "read_file preserves call id":
    withTempDir(tmpDir):
      writeFile(tmpDir / "test.txt", "content")
      var fs = FileSystemTools()
      let call = ToolCall(id: "my-call-id-12345", name: "read_file", input: %* {"path": tmpDir / "test.txt"})
      let result = fs.invoke(call)
      check result.get().callId == "my-call-id-12345"

  test "write_file preserves call id":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(
        id: "write-call-id-67890",
        name: "write_file",
        input: %* {"path": tmpDir / "out.txt", "content": "data"}
      )
      let result = fs.invoke(call)
      check result.get().callId == "write-call-id-67890"

  test "list_dir preserves call id":
    withTempDir(tmpDir):
      var fs = FileSystemTools()
      let call = ToolCall(id: "list-call-id-abc", name: "list_dir", input: %* {"path": tmpDir})
      let result = fs.invoke(call)
      check result.get().callId == "list-call-id-abc"

  test "error result preserves call id":
    var fs = FileSystemTools()
    let call = ToolCall(id: "error-call-id", name: "read_file", input: %* {"path": ""})
    let result = fs.invoke(call)
    check result.get().callId == "error-call-id"
