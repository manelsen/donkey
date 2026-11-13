## code_runner — bounded OCI/WASI execution for the `execute_code` tool.
##
## All I/O lives here. The security decisions and argv construction are in
## `domain/tools/code_pure`; this module only enforces the wall-clock timeout,
## caps the output and cleans up the container.

import std/[atomics, os, strtabs, strutils, times]
when defined(posix):
  import std/posix

import chronos
import chronos/asyncproc as asyncproc
import chronos/streams/asyncstream
import nimcrypto/sha2
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
    artifactHash*:  string
    artifactBytes*: int64

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

proc canonicalPath*(path: string): Result[string, string] =
  ## Filesystem I/O stays in infra; the app layer only interprets the Result.
  try:
    ok(expandFilename(path))
  except CatchableError as e:
    err("cannot canonicalize path: " & e.msg)

proc stringSha256*(data: string): string =
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(toHex(int(b), 2).toLowerAscii())

proc fileSha256*(path: string): Result[string, string] =
  ## Hash the artifact that will actually be executed (WASI module bytes).
  ## The size check bounds the daemon's own read to the same cap as the guest.
  try:
    let size = getFileSize(path)
    if size <= 0 or size > CodeMaxWasmBytes:
      return err("wasm module size is invalid: " & path)
    let data = readFile(path)
    ok(stringSha256(data))
  except CatchableError as e:
    err("cannot hash file: " & path & ": " & e.msg)

proc regularFileSize*(path: string): Result[int64, string] =
  try:
    if not fileExists(path):
      return err("file not found: " & path)
    let size = getFileSize(path)
    if size < 0:
      return err("cannot read file size: " & path)
    ok(size)
  except CatchableError as e:
    err("cannot read file size: " & path & ": " & e.msg)

proc killProcessGroup(p: AsyncProcessRef) =
  ## timeout is started with ProcessGroup, so a hard kill must target the whole
  ## group; otherwise a child that ignores SIGTERM survives as an orphan.
  when defined(posix):
    if p.pid > 0:
      discard posix.kill(Pid(-p.pid), SIGKILL)
  discard p.kill()

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

proc cleanupContainerAsync(runtimeCmd, name: string): Future[void] {.async.} =
  if runtimeCmd.len == 0 or name.len == 0:
    return
  let timeoutExe = timeoutCommand()
  if timeoutExe.len == 0:
    return
  var p: AsyncProcessRef
  try:
    p = await asyncproc.startProcess(
      timeoutExe,
      arguments = @["--kill-after=2s", "2s", runtimeCmd, "kill", name],
      environment = codeProcessEnv(),
      options = {AsyncProcessOption.UsePath, AsyncProcessOption.StdErrToStdOut,
                 AsyncProcessOption.ProcessGroup},
      stdoutHandle = AsyncProcess.Pipe)
  except CancelledError:
    raise
  except CatchableError:
    return
  try:
    try:
      discard await p.waitForExit()
    except CancelledError:
      killProcessGroup(p)
      try:
        discard await p.waitForExit(chronos.seconds(2))
      except CatchableError:
        discard
      raise
    except CatchableError:
      discard
  finally:
    await p.closeWait()

proc killAfter(p: AsyncProcessRef; seconds: int) {.async.} =
  await sleepAsync(chronos.seconds(seconds))
  killProcessGroup(p)

proc runBoundedProcessAsync*(argv: seq[string]; timeoutSec: int;
                             maxOutputBytes: int):
                             Future[Result[CodeRunResult, string]] {.async.} =
  ## Asynchronous variant of the bounded runner. It never blocks the Chronos
  ## loop while the child runs; stdout is read with async I/O, the output cap
  ## is enforced incrementally, and a timer kills the whole process group at
  ## the wall-clock deadline.
  if argv.len == 0:
    return err("empty execution argv")
  let seconds = clampCodeTimeoutSec(timeoutSec)
  let cap = clampCodeMaxOutputBytes(maxOutputBytes)

  var p: AsyncProcessRef
  let started = epochTime()
  try:
    p = await asyncproc.startProcess(
      argv[0],
      arguments = argv[1 .. ^1],
      environment = codeProcessEnv(),
      options = {AsyncProcessOption.UsePath, AsyncProcessOption.StdErrToStdOut,
                 AsyncProcessOption.ProcessGroup},
      stdoutHandle = AsyncProcess.Pipe)
  except CatchableError as e:
    return err("cannot start execution: " & e.msg)

  let killerFut = killAfter(p, seconds)
  var output = ""
  var truncated = false
  var readError = ""
  try:
    let stream = p.stdoutStream
    while true:
      let want = min(8192, cap - output.len + 1)
      let chunk = await stream.read(want)
      if chunk.len == 0:
        break
      if output.len + chunk.len > cap:
        let take = max(0, cap - output.len)
        for i in 0 ..< take:
          output.add(char(chunk[i]))
        truncated = true
        break
      for b in chunk:
        output.add(char(b))
  except CancelledError:
    ## Cancellation must not leave the child or its descendants running.
    if not finished(killerFut):
      await killerFut.cancelAndWait()
    killProcessGroup(p)
    try:
      discard await p.waitForExit(chronos.seconds(2))
    except CatchableError:
      discard
    await p.closeWait()
    raise
  except CatchableError as e:
    readError = e.msg

  if truncated:
    killProcessGroup(p)
  if not finished(killerFut):
    await killerFut.cancelAndWait()
  var exitCode = -1
  try:
    if truncated:
      exitCode = await p.waitForExit(chronos.seconds(2))
    else:
      ## The timer owns the wall-clock deadline. Waiting here with a short
      ## grace period would kill a program that closes stdout but keeps working.
      exitCode = await p.waitForExit()
  except CancelledError:
    killProcessGroup(p)
    try:
      discard await p.waitForExit(chronos.seconds(2))
    except CatchableError:
      discard
    await p.closeWait()
    raise
  except CatchableError:
    killProcessGroup(p)
    try:
      exitCode = await p.waitForExit(chronos.seconds(2))
    except CatchableError:
      exitCode = -1
  let durationMs = int64((epochTime() - started) * 1000.0)
  await p.closeWait()
  let capped = capExecutionOutput(output, cap)
  let timedOut = exitCode in {137, 143} and
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

proc runOciCodeAsync*(runtimeCmd, image, workspace: string;
                      uid, gid: int;
                      language: CodeLanguage;
                      code: string;
                      timeoutSec: int;
                      maxOutputBytes: int):
                      Future[Result[CodeRunResult, string]] {.async.} =
  if language == clWasm:
    return err("wasm code requires sandbox.mode='wasm'")
  if not executableAvailable(runtimeCmd):
    return err("container runtime not found: " & runtimeCmd)
  let name = nextContainerName()
  let argv = buildOciCodeArgv(runtimeCmd, image, workspace, uid, gid,
                              language, code, name)
  if argv.len == 0:
    return err("invalid OCI execution request")
  try:
    let run = await runBoundedProcessAsync(argv, timeoutSec, maxOutputBytes)
    if run.isErr:
      return err(run.error)
    var res = run.get()
    res.sandbox = cskOci
    res.containerName = name
    res.image = image
    res.artifactHash = stringSha256(code)
    res.artifactBytes = int64(code.len)
    if res.exitCode == 125 or
       (res.exitCode != 0 and ociInfrastructureFailure(res.output)):
      return err("container runtime failed: " & formatCodeResult(
        res.output, res.exitCode, res.timedOut, res.truncated))
    ok(res)
  finally:
    await cleanupContainerAsync(runtimeCmd, name)

proc runWasmCodeAsync*(workspace, wasmPath: string;
                       timeoutSec: int;
                       maxOutputBytes: int):
                       Future[Result[CodeRunResult, string]] {.async.} =
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

  ## Execute a private copy, not the guest-writable workspace file. The copy is
  ## outside every --dir, so the module cannot grow/change after the hash.
  let moduleDir = getTempDir() / ("donkey-code-module-" & name)
  try:
    createDir(moduleDir)
  except CatchableError as e:
    return err("cannot create execute_code module directory: " & e.msg)
  defer:
    try: removeDir(moduleDir) except CatchableError: discard
  if not hardenScratchDir(moduleDir):
    return err("cannot restrict execute_code module directory")
  let moduleCopy = moduleDir / "module.wasm"
  try:
    copyFile(wasmPath, moduleCopy)
  except CatchableError as e:
    return err("cannot copy wasm module: " & e.msg)
  let moduleSize = regularFileSize(moduleCopy).valueOr:
    return err(error)
  if moduleSize <= 0 or moduleSize > CodeMaxWasmBytes:
    return err("wasm module size is invalid")
  let moduleHash = fileSha256(moduleCopy).valueOr:
    return err(error)

  var argv = buildWasmCodeArgv(wasmtimeExe, workspace, moduleCopy, scratch)
  if argv.len == 0:
    return err("invalid WASI execution request")
  ## wasmtime's CLI does not expose a per-run memory cap. util-linux prlimit is
  ## therefore required for WASI: without a host address-space bound, a module
  ## could exhaust host memory before the wall-clock timeout.
  let prlimitExe = findExeSafe("prlimit")
  if prlimitExe.len == 0:
    return err("prlimit is required for WASI execute_code; refusing to run without a host memory bound")
  argv = @[prlimitExe, "--as=10737418240", "--"] & argv
  let run = await runBoundedProcessAsync(argv, timeoutSec, maxOutputBytes)
  if run.isErr:
    return err(run.error)
  var res = run.get()
  res.sandbox = cskWasm
  res.containerName = name
  res.image = "wasmtime"
  res.artifactHash = moduleHash
  res.artifactBytes = moduleSize
  ok(res)

proc executeCodeAsync*(sandbox: CodeSandboxKind;
                       runtimeCmd, image, workspace: string;
                       uid, gid: int;
                       language: CodeLanguage;
                       code, wasmPath: string;
                       timeoutSec: int;
                       maxOutputBytes: int):
                       Future[Result[CodeRunResult, string]] {.async.} =
  case sandbox
  of cskOci:
    let effectiveImage =
      if image.len > 0: image
      else: defaultCodeImage(language)
    if effectiveImage.len == 0:
      return err("no container image configured for " & $language)
    return await runOciCodeAsync(runtimeCmd, effectiveImage, workspace, uid,
                                 gid, language, code, timeoutSec,
                                 maxOutputBytes)
  of cskWasm:
    if language != clWasm:
      return err("sandbox.mode='wasm' only supports language='wasm'")
    if wasmPath.len == 0:
      return err("wasm_path is required for language='wasm'")
    return await runWasmCodeAsync(workspace, wasmPath, timeoutSec,
                                  maxOutputBytes)

# Synchronous wrappers keep the existing test/manual API. Production calls the
# Async variants from the Chronos event loop.
proc runBoundedProcess*(argv: seq[string]; timeoutSec: int;
                        maxOutputBytes: int): Result[CodeRunResult, string] =
  waitFor runBoundedProcessAsync(argv, timeoutSec, maxOutputBytes)

proc runOciCode*(runtimeCmd, image, workspace: string;
                 uid, gid: int;
                 language: CodeLanguage;
                 code: string;
                 timeoutSec: int;
                 maxOutputBytes: int): Result[CodeRunResult, string] =
  waitFor runOciCodeAsync(runtimeCmd, image, workspace, uid, gid, language,
                          code, timeoutSec, maxOutputBytes)

proc runWasmCode*(workspace, wasmPath: string;
                  timeoutSec: int;
                  maxOutputBytes: int): Result[CodeRunResult, string] =
  waitFor runWasmCodeAsync(workspace, wasmPath, timeoutSec, maxOutputBytes)

proc executeCode*(sandbox: CodeSandboxKind;
                  runtimeCmd, image, workspace: string;
                  uid, gid: int;
                  language: CodeLanguage;
                  code, wasmPath: string;
                  timeoutSec: int;
                  maxOutputBytes: int): Result[CodeRunResult, string] =
  waitFor executeCodeAsync(sandbox, runtimeCmd, image, workspace, uid, gid,
                           language, code, wasmPath, timeoutSec,
                           maxOutputBytes)
