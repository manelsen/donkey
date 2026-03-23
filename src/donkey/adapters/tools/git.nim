## Git Introspection Tools
## Native git status, log, diff

import std/[json, os, strutils, osproc]
import ../../core/pipeops
import ../../ports/tool

type
  GitTools* = object
    workspace*: string  ## Root directory for git operations

# =============================================================================
# Tool Schemas
# =============================================================================

proc gitStatusSchema*(): ToolSchema =
  ToolSchema(
    name: "git_status",
    description: "Returns current branch, staged/unstaged changes, and working tree status.",
    inputSchema: %* {
      "type": "object",
      "properties": {},
      "required": []
    }
  )

proc gitLogSchema*(): ToolSchema =
  ToolSchema(
    name: "git_log",
    description: "Returns recent commit history. Accepts optional limit (default 10) and path filter.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "limit": { "type": "integer", "description": "Maximum number of commits to return (default: 10)" },
        "path": { "type": "string", "description": "Optional path to filter commits for a specific file" }
      },
      "required": []
    }
  )

proc gitDiffSchema*(): ToolSchema =
  ToolSchema(
    name: "git_diff",
    description: "Returns unstaged changes. Accepts optional path to diff specific file/directory.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "path": { "type": "string", "description": "Optional path to diff specific file or directory" }
      },
      "required": []
    }
  )

# =============================================================================
# Internal Helpers (Result-based)
# =============================================================================

proc runGitStatus*(gt: GitTools; cwd: string): Result[string, string] =
  ## Run git status --short to get branch and change info
  let gitDir = if gt.workspace.len > 0: gt.workspace else: cwd
  let (output, exitCode) = execCmdEx("git status --short -b", workingDir=gitDir)
  if exitCode == 0:
    if output.strip().len > 0:
      ok(output.strip())
    else:
      ok("(empty - no git repository or no changes)")
  else:
    err("git status failed with exit code " & $exitCode & ": " & output)

proc runGitLog*(gt: GitTools; cwd: string; limit: int = 10; path: string = ""): Result[string, string] =
  ## Run git log with format and optional path filter
  let gitDir = if gt.workspace.len > 0: gt.workspace else: cwd
  var cmd = "git log --format='%H %h %an %ad %s' --date=iso -n " & $limit
  if path.len > 0:
    cmd &= " -- " & path
  let (output, exitCode) = execCmdEx(cmd, workingDir=gitDir)
  if exitCode == 0:
    if output.strip().len > 0:
      ok(output.strip())
    else:
      ok("(no commits)")
  elif output.contains("does not have any commits"):
    # Empty repo is not an error condition
    ok("(no commits)")
  else:
    err("git log failed with exit code " & $exitCode & ": " & output)

proc runGitDiff*(gt: GitTools; cwd: string; path: string = ""): Result[string, string] =
  ## Run git diff for unstaged changes, optionally filtered by path
  let gitDir = if gt.workspace.len > 0: gt.workspace else: cwd
  var cmd = "git diff --no-color"
  if path.len > 0:
    cmd &= " -- " & path
  else:
    cmd &= " --"
  let (output, exitCode) = execCmdEx(cmd, workingDir=gitDir)
  if exitCode == 0:
    if output.strip().len > 0:
      ok(output.strip())
    else:
      ok("(no unstaged changes)")
  else:
    err("git diff failed with exit code " & $exitCode & ": " & output)

# =============================================================================
# ToolPort Conformance
# =============================================================================

proc listTools*(gt: GitTools): Result[seq[ToolSchema], string] =
  ok(@[gitStatusSchema(), gitLogSchema(), gitDiffSchema()])

proc invoke*(gt: var GitTools; call: ToolCall): Result[ToolResult, string] =
  case call.name
  of "git_status":
    let cwd = getCurrentDir()
    let gr = gt.runGitStatus(cwd)
    if gr.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & gr.error & "\"}", isError: true))
    let output = gr.get()
    if output.contains("failed"):
      return ok(ToolResult(callId: call.id, output: output, isError: true))
    return ok(ToolResult(callId: call.id, output: output, isError: false))
  
  of "git_log":
    let limit = call.input.getOrDefault("limit")
    let path = call.input.getOrDefault("path")
    let limitVal = if limit.isNil or limit.kind != JInt: 10 else: limit.getInt()
    let pathVal = if path.isNil or path.kind != JString: "" else: path.getStr()
    
    let cwd = getCurrentDir()
    let gr = gt.runGitLog(cwd, limitVal, pathVal)
    if gr.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & gr.error & "\"}", isError: true))
    let output = gr.get()
    if output.contains("failed"):
      return ok(ToolResult(callId: call.id, output: output, isError: true))
    return ok(ToolResult(callId: call.id, output: output, isError: false))
  
  of "git_diff":
    let path = call.input.getOrDefault("path")
    let pathVal = if path.isNil or path.kind != JString: "" else: path.getStr()
    
    let cwd = getCurrentDir()
    let gr = gt.runGitDiff(cwd, pathVal)
    if gr.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & gr.error & "\"}", isError: true))
    let output = gr.get()
    if output.contains("failed"):
      return ok(ToolResult(callId: call.id, output: output, isError: true))
    return ok(ToolResult(callId: call.id, output: output, isError: false))
  
  else:
    return ok(ToolResult(callId: call.id, output: "{\"error\": \"unknown tool: " & call.name & "\"}", isError: true))

# =============================================================================
# Constructor
# =============================================================================

proc newGitTools*(workspace: string = ""): GitTools =
  GitTools(workspace: workspace)
