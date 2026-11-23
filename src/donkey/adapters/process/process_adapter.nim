## process_adapter.nim — `ProcessRuntimePort` on std/osproc.

import std/[os, osproc, streams, strtabs, times]
import ../../core/pipeops
import ../../ports/process

export process

proc envTable(spec: ProcessSpec): StringTableRef =
  if not spec.replaceEnv:
    return nil
  result = newStringTable(modeCaseSensitive)
  for (k, v) in spec.env:
    result[k] = v

proc runWithTimeout(p: Process; timeoutMs: int): Result[ProcessOutput, string] =
  ## Waits up to the deadline, then reads the output. A child that writes
  ## more than a pipe holds stalls until it is killed: meant for short probes
  ## such as `docker info`, not for long output.
  ## `waitForExit` kills the child itself when the timeout passes (SIGKILL,
  ## exit 137 on POSIX); the clock tells that apart from a child that exited
  ## with 137 in time.
  let started = epochTime()
  let code = p.waitForExit(timeout = timeoutMs)
  let elapsedMs = int((epochTime() - started) * 1000)
  if p.running or (code == 128 + 9 and elapsedMs >= timeoutMs):
    if p.running:
      p.kill()
      discard p.waitForExit()
    return err("timed out after " & $timeoutMs & " ms")
  ok(ProcessOutput(output: p.outputStream.readAll(), exitCode: code))

proc runSpec(spec: ProcessSpec): Result[ProcessOutput, string] {.gcsafe, raises: [].} =
  try:
    if spec.createWorkingDir and spec.workingDir.len > 0:
      createDir(spec.workingDir)
    let env = envTable(spec)
    if spec.argv.len == 0 and spec.timeoutMs <= 0:
      let (output, code) = execCmdEx(spec.command,
                                     options = {poEvalCommand, poStdErrToStdOut},
                                     workingDir = spec.workingDir, env = env)
      return ok(ProcessOutput(output: output, exitCode: code))
    let p =
      if spec.argv.len > 0:
        startProcess(spec.argv[0], workingDir = spec.workingDir,
                     args = spec.argv[1 .. ^1], env = env,
                     options = {poStdErrToStdOut, poUsePath})
      else:
        startProcess(spec.command, workingDir = spec.workingDir, env = env,
                     options = {poEvalCommand, poStdErrToStdOut})
    defer: p.close()
    if spec.timeoutMs > 0:
      return runWithTimeout(p, spec.timeoutMs)
    let output = p.outputStream.readAll()
    ok(ProcessOutput(output: output, exitCode: p.waitForExit()))
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

proc newProcessAdapter*(): ProcessRuntimePort =
  ProcessRuntimePort(run: runSpec)
