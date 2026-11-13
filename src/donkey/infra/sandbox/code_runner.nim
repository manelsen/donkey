## code_runner — bounded OCI/WASI execution for the `execute_code` tool.
##
## All I/O lives here. The security decisions and argv construction are in
## `domain/tools/code_pure`; this module only enforces the wall-clock timeout,
## caps the output and cleans up the container.

import std/[atomics, os, osproc, streams, strtabs, times]
import results
when defined(posix):
  import std/posix

import ../../core/pipeops
import ../../domain/tools/code_pure

type
  CodeRunResult* = object
    output*:        string
    exitCode*:      int
    timedOut*:      bool
    truncated*:     bool
    durationMs*:    int64
    sandbox*:       CodeSandboxKind
    containerName*: string
    image*:         string

var codeRunCounter: Atomic[int]
## Atomic, not a gcsafe promise: container names must stay unique even if a
## future caller invokes execute_code from more than one OS thread.

proc findExeSafe(name: string): string =
  try:
    findExe(name)
  except CatchableError:
    ""

proc executableAvailable(name: string): bool =
  if name.len == 0:
    return false
  if '/' in name or '\\' in name:
    return fileExists(name)
  findExeSafe(name).len > 0

proc timeoutCommand(): string =
  ## GNU coreutils `timeout`; Homebrew installs it as `gtimeout`.
  result = findExeSafe("timeout")
  if result.len == 0:
    result = findExeSafe("gtimeout")

proc nextContainerName(): string =
  buildContainerName(getCurrentProcessId().int, epochMs(),
                     codeRunCounter.fetchAdd(1))

proc hardenScratchDir(path: string): bool =
  when defined(posix):
    posix.chmod(path.cstring, posix.Mode(0o700)) == 0
  else:
    true

proc codeProcessEnv(): StringTableRef =
  ## Do not leak provider tokens into the container runtime CLI. Preserve the
  ## Docker client configuration and basic process environment.
  result = newStringTable(mode = modeCaseSensitive)
  for name in ["PATH", "HOME", "TMPDIR", "TMP", "TEMP", "LANG", "LC_ALL",
               "USER", "LOGNAME", "DOCKER_HOST", "DOCKER_CONFIG",
               "DOCKER_CERT_PATH", "DOCKER_TLS_VERIFY", "DOCKER_CONTEXT",
               "XDG_RUNTIME_DIR", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"]:
    let value = getEnv(name)
    if value.len > 0:
      result[name] = value
  when defined(windows):
    for name in ["SystemRoot", "WINDIR", "COMSPEC", "PATHEXT"]:
      let value = getEnv(name)
      if value.len > 0:
        result[name] = value

proc cleanupContainer(runtimeCmd, name: string) =
  ## `timeout` already kills the CLI. This second call handles the case where
  ## the CLI died but the container process survived in the daemon.
  if runtimeCmd.len == 0 or name.len == 0:
    return
  let timeoutExe = timeoutCommand()
  if timeoutExe.len == 0:
    return
  try:
    let p = startProcess(timeoutExe,
                         args = @["2s", runtimeCmd, "kill", name],
                         env = codeProcessEnv(),
                         options = {poUsePath, poStdErrToStdOut})
    try:
      discard p.waitForExit()
    finally:
      p.close()
  except CatchableError:
    discard

proc runBoundedProcess*(argv: seq[string]; timeoutSec: int;
                        maxOutputBytes: int): Result[CodeRunResult, string] =
  ## Runs argv with a hard wall-clock limit and a bounded read. The child is
  ## killed as soon as the output cap is reached; otherwise it is drained to
  ## EOF and the exit code is preserved.
  if argv.len == 0:
    return err("empty execution argv")
  let timeoutExe = timeoutCommand()
  if timeoutExe.len == 0:
    return err("GNU timeout (or gtimeout) is required for execute_code")
  let seconds = clampCodeTimeoutSec(timeoutSec)
  let cap = clampCodeMaxOutputBytes(maxOutputBytes)
  let fullArgv = @[timeoutExe, "--kill-after=2s", $seconds & "s"] & argv

  var p: Process
  let started = epochTime()
  try:
    p = startProcess(fullArgv[0], args = fullArgv[1 .. ^1],
                     env = codeProcessEnv(),
                     options = {poUsePath, poStdErrToStdOut})
  except CatchableError as e:
    return err("cannot start execution: " & e.msg)

  var output = ""
  var truncated = false
  var readError = ""
  try:
    let stream = p.outputStream
    var buffer = newString(8192)
    while true:
      let n = try:
        stream.readData(addr buffer[0], buffer.len)
      except CatchableError as e:
        readError = e.msg
        break
      if n <= 0:
        break
      if output.len + n > cap:
        let take = max(0, cap - output.len)
        if take > 0:
          output.add(buffer[0 ..< take])
        truncated = true
        break
      output.add(buffer[0 ..< n])
    if truncated:
      p.terminate()
  finally:
    let exitCode = try:
      p.waitForExit()
    except CatchableError:
      -1
    let durationMs = int64((epochTime() - started) * 1000.0)
    p.close()
    let capped = capExecutionOutput(output, cap)
    ## 124/137 are the timeout wrapper's codes, but our own output-cap kill can
    ## also surface as 137. The wall-clock check distinguishes the two.
    let timedOut = exitCode in {124, 137} and
      durationMs >= int64(seconds * 1000 - 250)
    result = ok(CodeRunResult(
      output: capped.text,
      exitCode: exitCode,
      timedOut: timedOut,
      truncated: truncated or capped.truncated,
      durationMs: durationMs,
    ))
    if readError.len > 0 and output.len == 0:
      result = err("cannot read execution output: " & readError)

proc runOciCode*(runtimeCmd, image, workspace: string;
                 uid, gid: int;
                 language: CodeLanguage;
                 code: string;
                 timeoutSec: int;
                 maxOutputBytes: int): Result[CodeRunResult, string] =
  if language == clWasm:
    return err("wasm code requires sandbox.mode='wasm'")
  if not executableAvailable(runtimeCmd):
    return err("container runtime not found: " & runtimeCmd)
  let name = nextContainerName()
  let argv = buildOciCodeArgv(runtimeCmd, image, workspace, uid, gid,
                              language, code, name)
  if argv.len == 0:
    return err("invalid OCI execution request")
  defer: cleanupContainer(runtimeCmd, name)
  let run = runBoundedProcess(argv, timeoutSec, maxOutputBytes)
  if run.isErr:
    return err(run.error)
  var res = run.get()
  res.sandbox = cskOci
  res.containerName = name
  res.image = image
  if res.exitCode == 125 or
     (res.exitCode != 0 and ociInfrastructureFailure(res.output)):
    return err("container runtime failed: " & formatCodeResult(
      res.output, res.exitCode, res.timedOut, res.truncated))
  ok(res)

proc runWasmCode*(workspace, wasmPath: string;
                  timeoutSec: int;
                  maxOutputBytes: int): Result[CodeRunResult, string] =
  if workspace.len == 0 or ':' in workspace or '\0' in workspace:
    return err("invalid WASI workspace path")
  let wasmtimeExe = findExeSafe("wasmtime")
  if wasmtimeExe.len == 0:
    return err("wasmtime not found in PATH")
  let name = nextContainerName()
  let scratch = getTempDir() / ("donkey-code-scratch-" & name)
  try:
    createDir(scratch)
  except CatchableError as e:
    return err("cannot create execute_code scratch directory: " & e.msg)
  defer:
    try: removeDir(scratch) except CatchableError: discard
  if not hardenScratchDir(scratch):
    return err("cannot restrict execute_code scratch directory")

  var argv = buildWasmCodeArgv(wasmtimeExe, workspace, wasmPath, scratch)
  if argv.len == 0:
    return err("invalid WASI execution request")
  ## wasmtime's CLI does not expose a per-run memory cap. util-linux prlimit
  ## bounds the host address space when available; otherwise the guest's own
  ## declared memory is the limit and the outer timeout still bounds CPU time.
  let prlimitExe = findExeSafe("prlimit")
  if prlimitExe.len > 0:
    argv = @[prlimitExe, "--as=536870912", "--"] & argv
  let run = runBoundedProcess(argv, timeoutSec, maxOutputBytes)
  if run.isErr:
    return err(run.error)
  var res = run.get()
  res.sandbox = cskWasm
  res.containerName = name
  res.image = "wasmtime"
  ok(res)

proc executeCode*(sandbox: CodeSandboxKind;
                  runtimeCmd, image, workspace: string;
                  uid, gid: int;
                  language: CodeLanguage;
                  code, wasmPath: string;
                  timeoutSec: int;
                  maxOutputBytes: int): Result[CodeRunResult, string] =
  case sandbox
  of cskOci:
    let effectiveImage =
      if image.len > 0: image
      else: defaultCodeImage(language)
    if effectiveImage.len == 0:
      return err("no container image configured for " & $language)
    runOciCode(runtimeCmd, effectiveImage, workspace, uid, gid, language, code,
               timeoutSec, maxOutputBytes)
  of cskWasm:
    if language != clWasm:
      return err("sandbox.mode='wasm' only supports language='wasm'")
    if wasmPath.len == 0:
      return err("wasm_path is required for language='wasm'")
    runWasmCode(workspace, wasmPath, timeoutSec, maxOutputBytes)
