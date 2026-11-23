## ProcessRuntimePort — running a child process, as the application layer
## sees it: a spec in, the combined output and the exit code out. The
## implementation (`adapters/process/process_adapter`) owns osproc and every
## exception; a test hands in a fake that records the spec.

import ../core/pipeops

type
  ProcessSpec* = object
    command*:          string  ## run through the shell when `argv` is empty
    argv*:             seq[string]  ## program and arguments, no shell
    workingDir*:       string  ## empty: the current directory
    createWorkingDir*: bool    ## create `workingDir` (and parents) first
    env*:              seq[(string, string)]
    replaceEnv*:       bool    ## `env` is the whole environment; otherwise
                               ## the child inherits ours and `env` is ignored
    timeoutMs*:        int     ## 0: wait as long as it runs; otherwise the
                               ## process is killed and the run is an error.
                               ## For short probes: the output is read after
                               ## the exit, so it must fit in a pipe

  ProcessOutput* = object
    output*:   string  ## stdout and stderr, interleaved
    exitCode*: int

  ProcessRuntimePort* = object
    run*: proc(spec: ProcessSpec): Result[ProcessOutput, string] {.gcsafe, raises: [].}
      ## An error when the process could not be started or timed out; a
      ## process that ran and failed is an `ok` with its exit code.

func unavailableProcess*(): ProcessRuntimePort =
  ## Fail-closed default: a zeroed proc field would crash.
  ProcessRuntimePort(
    run: proc(spec: ProcessSpec): Result[ProcessOutput, string] {.gcsafe, raises: [].} =
      err("process runtime unavailable"))

func orUnavailable*(p: ProcessRuntimePort): ProcessRuntimePort =
  if p.run == nil: unavailableProcess() else: p

func shellSpec*(command: string; workingDir = ""): ProcessSpec =
  ProcessSpec(command: command, workingDir: workingDir)

func argvSpec*(argv: seq[string]; workingDir = ""; timeoutMs = 0): ProcessSpec =
  ProcessSpec(argv: argv, workingDir: workingDir, timeoutMs: timeoutMs)
