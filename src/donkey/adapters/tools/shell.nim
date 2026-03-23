## Shell Execution Tools — ToolPort adapter for safe shell command execution.
##
## Provides shell command execution with security validation via shell_ast.
## All commands are checked for dangerous operators (|, &, ;, <, >, etc.)
## before execution. Blocked commands return an error, not executed.
##
## Tools:
##   - shell_exec — execute a shell command via /bin/sh

import std/[json, os, osproc, strutils]
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/shell_ast

type
  ShellTools* = object
    workspace*: string  ## Optional root directory to restrict command execution.
                        ## Empty string means no restriction (uses OS cwd).

# ── Tool Schemas ─────────────────────────────────────────────────────────────

proc shellExecSchema*(): ToolSchema =
  ToolSchema(
    name: "shell_exec",
    description: "Execute a shell command via /bin/sh. " &
                 "Dangerous operators are blocked: | & ; < > && || 2> >>",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "command": {
          "type": "string",
          "description": "The shell command to execute."
        },
        "cwd": {
          "type": "string",
          "description": "Optional working directory to execute in. Defaults to current directory."
        }
      },
      "required": ["command"]
    }
  )

# ── ToolPort Conformance ─────────────────────────────────────────────────────

proc listTools*(st: ShellTools): Result[seq[ToolSchema], string] =
  ok(@[shellExecSchema()])

# ── Validation ──────────────────────────────────────────────────────────────

proc validateCommand*(cmd: string): Result[string, string] =
  ## Validates a command using shell_ast. Returns normalized command or error.
  let validation = validateShellSafe(cmd)
  if validation.isClean:
    ok(validation.normalized)
  else:
    err(shellValidationErrorMsg(cmd))

# ── Internal Helpers ────────────────────────────────────────────────────────

proc runShellExec*(st: ShellTools; command: string; cwd: string = ""): Result[string, string] =
  ## Execute a shell command after validation.
  ## Returns stdout on success, or error message on failure/blocking.
  let validated = command |> validateCommand
  if validated.isErr:
    return err(validated.error)
  
  let normalizedCmd = validated.get()
  let workDir = if cwd.len > 0: cwd elif st.workspace.len > 0: st.workspace else: getCurrentDir()
  
  # Quote the command for safe shell execution
  let shellCmd = "sh -c " & quoteShell(normalizedCmd)
  let (output, exitCode) = execCmdEx(shellCmd, workingDir=workDir)
  if exitCode == 0:
    ok(output)
  else:
    err("command exited with code " & $exitCode & ": " & output)

# ── invoke — ToolPort method ─────────────────────────────────────────────────

proc invoke*(st: var ShellTools; call: ToolCall): Result[ToolResult, string] =
  ## Routes tool call by name and executes the appropriate handler.
  ## Shell operators detected by shell_ast result in error ToolResult.

  case call.name
  of "shell_exec":
    let cmdNode = call.input.getOrDefault("command")
    if cmdNode.isNil or cmdNode.kind != JString or cmdNode.getStr("").len == 0:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"missing required field: command\"}",
        isError: true
      ))
    
    let rawCommand = cmdNode.getStr("")
    let cwdNode = call.input.getOrDefault("cwd")
    let cwd = if cwdNode.isNil or cwdNode.kind != JString: "" else: cwdNode.getStr("")
    
    let execResult = st.runShellExec(rawCommand, cwd)
    if execResult.isErr:
      return ok(ToolResult(
        callId: call.id,
        output: "{\"error\": \"" & execResult.error & "\"}",
        isError: true
      ))
    return ok(ToolResult(
      callId: call.id,
      output: execResult.get(),
      isError: false
    ))

  else:
    return ok(ToolResult(
      callId: call.id,
      output: "{\"error\": \"unknown tool: '" & call.name & "'\"}",
      isError: true
    ))

# ── Constructor ─────────────────────────────────────────────────────────────

proc newShellTools*(workspace: string = ""): ShellTools =
  ShellTools(workspace: workspace)
