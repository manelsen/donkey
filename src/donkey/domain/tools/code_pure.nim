## code_pure — pure policy, limits and argv construction for `execute_code`.
##
## No filesystem, process or network access lives here. The app layer validates
## the workspace and resolves paths; the runner executes the argv. Keeping the
## argv construction pure makes the security flags testable without Docker.

import std/[options, strutils, unicode]

type
  CodeLanguage* = enum
    clPython = "python"
    clJavaScript = "javascript"
    clShell = "shell"
    clWasm = "wasm"

  CodeSandboxKind* = enum
    cskOci
    cskWasm

  CodeLimits* = object
    timeoutSec*:     int
    maxOutputBytes*: int
    maxSourceBytes*: int

  CodeOutput* = object
    text*:      string
    truncated*: bool

const
  CodeDefaultTimeoutSec*     = 10
  CodeMinTimeoutSec*         = 1
  CodeMaxTimeoutSec*         = 60
  CodeDefaultMaxOutputBytes* = 64 * 1024
  CodeMinMaxOutputBytes*     = 1024
  CodeMaxMaxOutputBytes*     = 1024 * 1024
  CodeDefaultMaxSourceBytes* = 128 * 1024
  CodeMinMaxSourceBytes*     = 1024
  CodeMaxMaxSourceBytes*     = 1024 * 1024
  CodeDefaultImage*          = "python:3.12-alpine"
  CodeDefaultJsImage*        = "node:22-alpine"
  CodeMaxWasmBytes*          = 32 * 1024 * 1024

func parseCodeLanguage*(raw: string): Option[CodeLanguage] =
  case raw.strip.toLowerAscii
  of "python", "python3", "py": some(clPython)
  of "javascript", "js", "node": some(clJavaScript)
  of "shell", "sh", "bash": some(clShell)
  of "wasm", "wasi": some(clWasm)
  else: none(CodeLanguage)

func clampCodeTimeoutSec*(raw: int): int =
  if raw <= 0: CodeDefaultTimeoutSec
  elif raw < CodeMinTimeoutSec: CodeMinTimeoutSec
  elif raw > CodeMaxTimeoutSec: CodeMaxTimeoutSec
  else: raw

func clampCodeMaxOutputBytes*(raw: int): int =
  if raw <= 0: CodeDefaultMaxOutputBytes
  elif raw < CodeMinMaxOutputBytes: CodeMinMaxOutputBytes
  elif raw > CodeMaxMaxOutputBytes: CodeMaxMaxOutputBytes
  else: raw

func clampCodeMaxSourceBytes*(raw: int): int =
  if raw <= 0: CodeDefaultMaxSourceBytes
  elif raw < CodeMinMaxSourceBytes: CodeMinMaxSourceBytes
  elif raw > CodeMaxMaxSourceBytes: CodeMaxMaxSourceBytes
  else: raw

func parsePositiveInt(raw: string; default, minValue, maxValue: int): int =
  let value = raw.strip
  if value.len == 0:
    return default
  try:
    let parsed = parseInt(value)
    if parsed <= 0: default
    elif parsed < minValue: minValue
    elif parsed > maxValue: maxValue
    else: parsed
  except ValueError:
    default

func parseCodeTimeoutSec*(raw: string): int =
  parsePositiveInt(raw, CodeDefaultTimeoutSec,
                   CodeMinTimeoutSec, CodeMaxTimeoutSec)

func parseCodeMaxOutputBytes*(raw: string): int =
  parsePositiveInt(raw, CodeDefaultMaxOutputBytes,
                   CodeMinMaxOutputBytes, CodeMaxMaxOutputBytes)

func parseCodeMaxSourceBytes*(raw: string): int =
  parsePositiveInt(raw, CodeDefaultMaxSourceBytes,
                   CodeMinMaxSourceBytes, CodeMaxMaxSourceBytes)

func defaultCodeImage*(language: CodeLanguage): string =
  case language
  of clJavaScript: CodeDefaultJsImage
  of clPython, clShell: CodeDefaultImage
  of clWasm: ""

func validateCodeSource*(language: CodeLanguage; code: string;
                         maxSourceBytes: int): Option[string] =
  ## `none` means valid; `some(message)` is the pure rejection reason.
  if language == clWasm:
    if code.len > 0:
      return some("wasm language uses wasm_path, not code")
    return none(string)
  if code.len == 0:
    return some("code is required for language '" & $language & "'")
  if '\0' in code:
    return some("code contains a NUL byte")
  let cap = clampCodeMaxSourceBytes(maxSourceBytes)
  if code.len > cap:
    return some("code exceeds " & $cap & " bytes")
  none(string)

func validCodeImage*(image: string): bool =
  ## The image is an operator setting, but it is also an argv entry before the
  ## container command. Reject values that Docker would parse as an option or
  ## that would smuggle whitespace/control bytes.
  image.len > 0 and image[0] != '-' and
    not image.contains({' ', '\t', '\n', '\r', '\0'})

func codeWorkspaceMountAllowed*(workspace: string): bool =
  ## Docker bind mounts cannot represent a colon in the host path safely and a
  ## NUL would truncate the option. The workspace is daemon-generated, but a
  ## defensive check keeps a compromised config from injecting options.
  workspace.len > 0 and ':' notin workspace and '\0' notin workspace

func interpreterArgv*(language: CodeLanguage; code: string): seq[string] =
  case language
  of clPython:
    @["python3", "-I", "-B", "-c", code]
  of clJavaScript:
    @["node", "--no-warnings", "-e", code]
  of clShell:
    @["sh", "-c", code]
  of clWasm:
    @[]

func buildOciCodeArgv*(runtimeCmd, image, workspace: string;
                       uid, gid: int;
                       language: CodeLanguage;
                       code: string;
                       containerName: string): seq[string] =
  ## Builds a dedicated, locked-down container invocation. The command is
  ## passed as separate argv entries; the host never evaluates a shell string.
  if runtimeCmd.len == 0 or containerName.len == 0 or
     not validCodeImage(image):
    return @[]
  if not codeWorkspaceMountAllowed(workspace):
    return @[]
  result = @[
    runtimeCmd, "run", "--rm",
    "--name", containerName,
    "--network=none",
    "--read-only",
    "--tmpfs", "/tmp:rw,noexec,nosuid,size=64m",
    "--cap-drop=ALL",
    "--security-opt", "no-new-privileges",
    "--pids-limit=128",
    "--memory=512m",
    "--memory-swap=512m",
    "--cpus=1",
    "--ulimit", "nofile=256:256",
    "--stop-timeout=1",
    "--init",
    "--label=donkey.execute_code=true",
    "--workdir", "/workspace",
    "-v", workspace & ":/workspace:rw,z",
    "-e", "HOME=/tmp",
    "-e", "XDG_CACHE_HOME=/tmp/.cache",
    "-e", "PYTHONDONTWRITEBYTECODE=1",
    "-e", "PYTHONUNBUFFERED=1",
  ]
  if uid >= 0 and gid >= 0:
    result.add("--user")
    result.add($uid & ":" & $gid)
  result.add(image)
  result.add(interpreterArgv(language, code))

func buildWasmCodeArgv*(wasmtimePath, workspace, wasmPath,
                        scratchDir: string): seq[string] =
  ## WASI gets only the workspace and an isolated scratch directory mapped to
  ## /tmp. No listener/socket flag is ever added, so the guest has no network.
  if wasmtimePath.len == 0 or workspace.len == 0 or wasmPath.len == 0 or
     scratchDir.len == 0:
    return @[]
  @[
    wasmtimePath, "run",
    "--dir=" & workspace,
    "--dir=" & scratchDir & "::/tmp",
    "--",
    wasmPath,
  ]

func capUtf8Bytes*(text: string; maxBytes: int): string =
  ## Cuts at a UTF-8 boundary, including when the input already ends with a
  ## partial rune at the cap. A byte cap never emits a partial sequence.
  if maxBytes <= 0:
    return ""
  var i = 0
  while i < text.len:
    let n = runeLenAt(text, i)
    if n <= 0 or i + n > text.len or i + n > maxBytes:
      break
    i += n
  text[0 ..< i]

func capExecutionOutput*(output: string; maxBytes: int): CodeOutput =
  let cap = clampCodeMaxOutputBytes(maxBytes)
  let cappedText = capUtf8Bytes(output, cap)
  if output.len <= cap and cappedText.len == output.len:
    return CodeOutput(text: output, truncated: false)
  CodeOutput(text: cappedText & "\n[output truncated]", truncated: true)

func ociInfrastructureFailure*(output: string): bool =
  ## Distinguishes a broken daemon/image from code that exited non-zero.
  let normalized = output.toLowerAscii
  "cannot connect to the docker daemon" in normalized or
    "cannot connect to the podman" in normalized or
    "permission denied while trying to connect" in normalized or
    "pull access denied" in normalized or
    "no such image" in normalized or
    "unable to find image" in normalized or
    "error response from daemon" in normalized

func formatCodeResult*(output: string; exitCode: int;
                       timedOut, truncated: bool): string =
  result = output
  if result.endsWith('\n'):
    result.setLen(result.len - 1)
  if timedOut:
    if result.len > 0: result.add('\n')
    result.add("[timeout]")
  elif exitCode != 0:
    if result.len > 0: result.add('\n')
    result.add("[exit " & $exitCode & "]")
  if result.len == 0:
    result = "[exit " & $exitCode & "]"
  if truncated and "[output truncated]" notin result:
    result.add("\n[output truncated]")

func buildContainerName*(pid: int; epochMs: int64; counter: int): string =
  ## Only [a-z0-9-] so the name is safe as an argv entry for `docker kill`.
  "donkey-code-" & $max(pid, 0) & "-" & $max(epochMs, 0'i64) & "-" &
    $max(counter, 0)
