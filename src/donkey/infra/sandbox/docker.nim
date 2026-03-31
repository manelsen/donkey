## infra/sandbox/docker — Docker Ephemeral Container Sandbox.
##
## Spawns isolated containers for arbitrary Python/Node code execution.
## Each run creates a temporary container that is removed after execution.
##
## Usage:
##   var d = newDocker(sandboxDefaults())
##   let result = d.runContainer("python", @["python", "-c", "print('hello')"]).valueOr:
##     echo "run failed: " & error
##     return
##   echo "exit: " & $result.exitCode
##   echo "stdout: " & result.stdout
##
## All functions return Result[T, string] so callers decide what to do on error.
## Functions are designed as unary or with the piped target as last argument to
## facilitate `|>` and `>>=` chaining where applicable.

import std/[os, posix, strutils, times, osproc, sequtils]

import ../../core/pipeops
import ./limits

export pipeops

# ── Types ─────────────────────────────────────────────────────────────────────

type
  DockerSandbox* = object
    ## Docker container sandbox.
    ## Create with `newDocker` or `newDockerSandbox`.
    opts: DockerOptions

  DockerOptions* = object
    ## Options for spawning a Docker container.
    image*: string           ## Docker image to use (e.g., "python:3.11", "node:20").
    cpuLimit*: CpuLimit      ## CPU time limit in seconds (0 = unlimited).
    memLimit*: MemLimit      ## Memory limit in bytes (0 = unlimited).
    timeout*: int            ## Overall timeout in seconds (0 = unlimited).
    network*: bool            ## Whether to allow network access.
    readOnlyRoot*: bool      ## Whether to make filesystem read-only.
    workingDir*: string       ## Working directory inside container.
    envVars*: seq[tuple[key, val: string]] ## Environment variables.

  DockerResult* = object
    ## Result of a Docker container run.
    exitCode*: int          ## Container exit code.
    stdout*: string         ## Captured stdout.
    stderr*: string         ## Captured stderr.
    timedOut*: bool         ## True if execution timed out.
    containerId*: string    ## Container ID that was used.

  ContainerRuntime* = enum
    ## Supported container runtimes.
    crPython
    crNode
    crGeneric

# ── Image constants ────────────────────────────────────────────────────────────

const
  DefaultPythonImage* = "python:3.11-slim"
    ## Default Python image - slim variant for smaller footprint.

  DefaultNodeImage* = "node:20-slim"
    ## Default Node.js image - slim variant for smaller footprint.

# ── Convenience constructors ───────────────────────────────────────────────────

func dockerDefaults*(): DockerOptions =
  ## Default Docker sandbox options.
  DockerOptions(
    image: DefaultPythonImage,
    cpuLimit: CpuLimit(0),
    memLimit: MemLimit(0),
    timeout: 60,
    network: false,
    readOnlyRoot: true,
    workingDir: "/workspace",
    envVars: @[]
  )

func withImage*(opts: DockerOptions; img: string): DockerOptions =
  result = opts; result.image = img

func withCpuLimitDocker*(opts: DockerOptions; limit: CpuLimit): DockerOptions =
  result = opts; result.cpuLimit = limit

func withMemLimitDocker*(opts: DockerOptions; limit: MemLimit): DockerOptions =
  result = opts; result.memLimit = limit

func withTimeout*(opts: DockerOptions; secs: int): DockerOptions =
  result = opts; result.timeout = secs

func withNetwork*(opts: DockerOptions; allow: bool): DockerOptions =
  result = opts; result.network = allow

func withReadOnlyRoot*(opts: DockerOptions; ro: bool): DockerOptions =
  result = opts; result.readOnlyRoot = ro

func withWorkingDirDocker*(opts: DockerOptions; dir: string): DockerOptions =
  result = opts; result.workingDir = dir

func withEnvVarDocker*(opts: DockerOptions; key, val: string): DockerOptions =
  result = opts; result.envVars = opts.envVars & @[(key, val)]

func pythonSandbox*(): DockerOptions =
  ## Default Python sandbox: python image, 60s timeout, 512MB memory, no network.
  dockerDefaults()
    .withImage(DefaultPythonImage)
    .withCpuLimitDocker(cpuSeconds(60))
    .withMemLimitDocker(memBytes(512 * 1024 * 1024))
    .withTimeout(60)
    .withNetwork(false)
    .withReadOnlyRoot(true)

func nodeSandbox*(): DockerOptions =
  ## Default Node.js sandbox: node image, 60s timeout, 512MB memory, no network.
  dockerDefaults()
    .withImage(DefaultNodeImage)
    .withCpuLimitDocker(cpuSeconds(60))
    .withMemLimitDocker(memBytes(512 * 1024 * 1024))
    .withTimeout(60)
    .withNetwork(false)
    .withReadOnlyRoot(true)

func newDocker*(): DockerSandbox =
  ## Create a Docker sandbox with default options.
  DockerSandbox(opts: dockerDefaults())

func newDocker*(opts: DockerOptions): DockerSandbox =
  DockerSandbox(opts: opts)

func newDockerSandbox*(): DockerSandbox =
  ## Alias for newDocker.
  newDocker()

func newDockerSandbox*(opts: DockerOptions): DockerSandbox =
  ## Alias for newDocker with options.
  newDocker(opts)

# ── Internal: check if Docker is available ─────────────────────────────────────

proc dockerAvailable*(): bool =
  ## Check if docker command is available.
  let path = findExe("docker")
  path.len > 0

# ── Internal: build docker run arguments ──────────────────────────────────────

func buildDockerArgs*(opts: DockerOptions; cmd: string; args: seq[string]): seq[string] =
  ## Build docker run argument list from options and command.
  var dockerArgs: seq[string] = @[]

  # Use system 'timeout' command if a timeout is specified
  if opts.timeout > 0:
    dockerArgs.add("timeout")
    dockerArgs.add("--signal=SIGKILL")
    dockerArgs.add($opts.timeout & "s")

  dockerArgs.add("docker")
  dockerArgs.add("run")

  # Remove container after exit
  dockerArgs.add("--rm")

  # Isolated network (no network access unless explicitly allowed)
  if not opts.network:
    dockerArgs.add("--network=none")

  # Read-only root filesystem unless explicitly disabled
  if opts.readOnlyRoot:
    dockerArgs.add("--read-only")

  # Memory limit
  if opts.memLimit.int64 > 0:
    dockerArgs.add("--memory=" & $opts.memLimit.int64)

  # CPU limit (in seconds of CPU time)
  if opts.cpuLimit.int64 > 0:
    dockerArgs.add("--cpus=" & $(opts.cpuLimit.int64))

  # Working directory
  if opts.workingDir.len > 0:
    dockerArgs.add("--workdir=" & opts.workingDir)

  # Environment variables
  for (key, val) in opts.envVars:
    dockerArgs.add("-e=" & key & "=" & val)

  # Add a workspace tmpfs mount if root is read-only
  if opts.readOnlyRoot:
    dockerArgs.add("--tmpfs=/tmp:rw,noexec,nosuid,size=64m")

  # Image
  dockerArgs.add(opts.image)

  # Command and arguments
  dockerArgs.add(cmd)
  for arg in args:
    dockerArgs.add(arg)

  dockerArgs

# ── Internal: run docker command ───────────────────────────────────────────────

proc runDockerCmd*(args: seq[string]): Result[tuple[output: string, exitCode: int], string] =
  ## Run docker (or timeout docker) with given arguments and return output + exit code.
  if args.len == 0: return err("Empty arguments")
  let cmd = args[0]
  let remainingArgs = args[1..^1]
  let fullCmd = quoteShell(cmd) & " " & remainingArgs.mapIt(quoteShell(it)).join(" ")
  let (output, exitCode) = execCmdEx(fullCmd)
  ok((output: output, exitCode: exitCode))

# ── Run container ─────────────────────────────────────────────────────────────

proc runContainer*(d: var DockerSandbox; cmd: string; args: seq[string]): Result[DockerResult, string] =
  ## Run a command inside an ephemeral Docker container.
  ##
  ## The container is automatically removed after execution (--rm flag).
  ## Returns DockerResult with stdout, stderr, and exit code.
  ##
  ## Returns err if docker is not available or if docker command fails.
  let opts = d.opts

  # Check docker availability
  if not dockerAvailable():
    return err("Docker is not available. Is docker installed and in PATH?")

  # Build docker run arguments
  let dockerArgs = opts.buildDockerArgs(cmd, args)

  # Run docker
  let dockerRes = runDockerCmd(dockerArgs)
  if dockerRes.isErr:
    return err(dockerRes.error)

  let (output, exitCode) = dockerRes.get()

  # Check for timeout (exit code 124 is standard for 'timeout' command, 137 if SIGKILL used)
  let timedOut = (exitCode == 124 or exitCode == 137)
  let actualExitCode = exitCode

  # Docker output format: stdout and stderr are combined in output
  # We need to split them - docker outputs to stdout/stderr separately
  # For simplicity, we capture combined output; the exit code tells us success/failure
  let res = DockerResult(
    exitCode: actualExitCode,
    stdout: output,  # docker run captures stdout
    stderr: "",      # stderr is merged into stdout by docker
    timedOut: timedOut,
    containerId: ""  # Container is removed immediately with --rm
  )

  ok(res)

proc runContainer*(d: var DockerSandbox; image: string; cmd: string; args: seq[string]): Result[DockerResult, string] =
  ## Run a command inside an ephemeral Docker container with a specific image.
  d.opts.image = image
  d.runContainer(cmd, args)

proc runContainer*(d: var DockerSandbox; runtime: ContainerRuntime; code: string): Result[DockerResult, string] =
  ## Run code in a container using the specified runtime.
  ## Python code uses `python -c "$code"`, Node code uses `node -e "$code"`.
  case runtime
  of crPython:
    d.runContainer("python", @["-c", code])
  of crNode:
    d.runContainer("node", @["-e", code])
  of crGeneric:
    err("Generic runtime requires explicit command")

# ── Pull image (utility) ───────────────────────────────────────────────────────

proc pullImage*(image: string): Result[string, string] =
  ## Pull a Docker image. Returns the image name on success.
  if not dockerAvailable():
    return err("Docker is not available")
  let (output, exitCode) = execCmdEx("docker pull " & quoteShell(image))
  if exitCode != 0:
    return err("docker pull failed: " & output)
  ok(image)

# ── List running containers (utility) ─────────────────────────────────────────

proc listContainers*(): Result[seq[string], string] =
  ## List running container IDs.
  if not dockerAvailable():
    return err("Docker is not available")
  let (output, exitCode) = execCmdEx("docker ps -q")
  if exitCode != 0:
    return err("docker ps failed")
  let ids = output.strip().splitLines().filterIt(it.len > 0)
  ok(ids)

# ── Stop all containers (utility) ──────────────────────────────────────────────

proc stopAllContainers*(): Result[int, string] =
  ## Stop all running containers. Returns count of stopped containers.
  if not dockerAvailable():
    return err("Docker is not available")
  let (output, exitCode) = execCmdEx("docker stop $(docker ps -q)")
  if exitCode != 0:
    return err("docker stop failed")
  let count = output.strip().splitLines().filterIt(it.len > 0).len
  ok(count)

# ── Formatting ─────────────────────────────────────────────────────────────────

func `$`*(opts: DockerOptions): string =
  var parts: seq[string] = @[]
  parts.add("image=" & opts.image)
  if opts.cpuLimit.int64 > 0:
    parts.add("cpu=" & $opts.cpuLimit)
  if opts.memLimit.int64 > 0:
    parts.add("mem=" & $opts.memLimit)
  if opts.timeout > 0:
    parts.add("timeout=" & $opts.timeout & "s")
  if not opts.network:
    parts.add("no-network")
  if opts.readOnlyRoot:
    parts.add("readonly-root")
  if opts.workingDir.len > 0:
    parts.add("workdir=" & opts.workingDir)
  "DockerOptions(" & parts.join(", ") & ")"

func `$`*(res: DockerResult): string =
  "DockerResult(exitCode=" & $res.exitCode &
    ", timedOut=" & (if res.timedOut: "true" else: "false") &
    ", stdout.len=" & $res.stdout.len &
    ", stderr.len=" & $res.stderr.len &
    ", containerId=" & (if res.containerId.len > 0: res.containerId else: "(removed)") & ")"
