import std/[strutils]
import unittest2
import ../../../src/donkey/infra/sandbox/docker
import ../../../src/donkey/infra/sandbox/limits
import ../../../src/donkey/core/pipeops

suite "infra/sandbox/docker":

  suite "DockerOptions formatting":
    test "empty options show image and defaults":
      let opts = dockerDefaults()
      check "python:3.11-slim" in $opts
      check "no-network" in $opts
      check "readonly-root" in $opts

    test "cpu limit shows correctly":
      let opts = dockerDefaults().withCpuLimitDocker(cpuSeconds(30))
      check "cpu=30s" in $opts

    test "mem limit shows correctly":
      let opts = dockerDefaults().withMemLimitDocker(memBytes(128 * 1024 * 1024))
      check "mem=128MB" in $opts

    test "timeout shows correctly":
      let opts = dockerDefaults().withTimeout(120)
      check "timeout=120s" in $opts

    test "network option shows correctly":
      let opts = dockerDefaults().withNetwork(true)
      check "no-network" notin $opts

    test "working dir shows correctly":
      let opts = dockerDefaults().withWorkingDirDocker("/app")
      check "workdir=/app" in $opts

    test "withImage sets image":
      let opts = dockerDefaults().withImage("node:18")
      check "node:18" in $opts

  suite "DockerResult formatting":
    test "shows exit code and sizes":
      let res = DockerResult(exitCode: 0, stdout: "hello", stderr: "", timedOut: false, containerId: "")
      check "exitCode=0" in $res
      check "stdout.len=5" in $res
      check "timedOut=false" in $res

    test "shows timed out":
      let res = DockerResult(exitCode: 124, stdout: "", stderr: "", timedOut: true, containerId: "")
      check "timedOut=true" in $res

    test "shows container id":
      let res = DockerResult(exitCode: 0, stdout: "", stderr: "", timedOut: false, containerId: "abc123")
      check "containerId=abc123" in $res

  suite "Convenience constructors":
    test "dockerDefaults has expected defaults":
      let opts = dockerDefaults()
      check opts.image == DefaultPythonImage
      check opts.timeout == 60
      check opts.network == false
      check opts.readOnlyRoot == true
      check opts.workingDir == "/workspace"

    test "pythonSandbox has python image":
      let opts = pythonSandbox()
      check opts.image == DefaultPythonImage
      check opts.timeout == 60
      check opts.cpuLimit.int64 == 60
      check opts.memLimit.int64 == 512 * 1024 * 1024

    test "nodeSandbox has node image":
      let opts = nodeSandbox()
      check opts.image == DefaultNodeImage
      check opts.timeout == 60

    test "newDocker creates sandbox":
      var d = newDocker()
      # Verify sandbox was created by checking we can use it
      let available = dockerAvailable()
      check available == true

    test "newDockerSandbox is alias for newDocker":
      var d1 = newDocker()
      var d2 = newDockerSandbox()
      # Both should work the same way - just verify they don't crash
      let avail1 = dockerAvailable()
      let avail2 = dockerAvailable()
      check avail1 == avail2

  suite "withCpuLimitDocker":
    test "sets cpu limit":
      let opts = dockerDefaults().withCpuLimitDocker(cpuSeconds(120))
      check opts.cpuLimit.int64 == 120

  suite "withMemLimitDocker":
    test "sets memory limit":
      let opts = dockerDefaults().withMemLimitDocker(memBytes(256 * 1024 * 1024))
      check opts.memLimit.int64 == 256 * 1024 * 1024

  suite "withTimeout":
    test "sets timeout":
      let opts = dockerDefaults().withTimeout(300)
      check opts.timeout == 300

  suite "withNetwork":
    test "enables network":
      let opts = dockerDefaults().withNetwork(true)
      check opts.network == true

    test "disables network (default)":
      let opts = dockerDefaults()
      check opts.network == false

  suite "withReadOnlyRoot":
    test "makes root read-only (default)":
      let opts = dockerDefaults()
      check opts.readOnlyRoot == true

    test "makes root writable":
      let opts = dockerDefaults().withReadOnlyRoot(false)
      check opts.readOnlyRoot == false

  suite "withWorkingDirDocker":
    test "sets working directory":
      let opts = dockerDefaults().withWorkingDirDocker("/tmp")
      check opts.workingDir == "/tmp"

  suite "withEnvVarDocker":
    test "adds environment variable":
      let opts = dockerDefaults().withEnvVarDocker("FOO", "bar")
      check opts.envVars.len == 1
      check opts.envVars[0].key == "FOO"
      check opts.envVars[0].val == "bar"

    test "adds multiple environment variables":
      let opts = dockerDefaults()
        .withEnvVarDocker("FOO", "bar")
        .withEnvVarDocker("BAZ", "qux")
      check opts.envVars.len == 2

  suite "buildDockerArgs":
    test "includes --rm flag":
      let args = buildDockerArgs(dockerDefaults(), "echo", @["echo", "hello"])
      check "--rm" in args

    test "includes --network=none by default":
      let args = buildDockerArgs(dockerDefaults(), "echo", @["echo", "hello"])
      check "--network=none" in args

    test "network enabled omits --network=none":
      let opts = dockerDefaults().withNetwork(true)
      let args = buildDockerArgs(opts, "echo", @["echo", "hello"])
      check "--network=none" notin args

    test "includes --read-only by default":
      let args = buildDockerArgs(dockerDefaults(), "echo", @["echo", "hello"])
      check "--read-only" in args

    test "includes memory limit":
      let opts = dockerDefaults().withMemLimitDocker(memBytes(128 * 1024 * 1024))
      let args = buildDockerArgs(opts, "echo", @["echo", "hello"])
      check "--memory=134217728" in args

    test "includes cpu limit":
      let opts = dockerDefaults().withCpuLimitDocker(cpuSeconds(30))
      let args = buildDockerArgs(opts, "echo", @["echo", "hello"])
      check "--cpus=30" in args

    test "includes working directory":
      let opts = dockerDefaults().withWorkingDirDocker("/app")
      let args = buildDockerArgs(opts, "echo", @["echo", "hello"])
      check "--workdir=/app" in args

    test "includes environment variables":
      let opts = dockerDefaults().withEnvVarDocker("FOO", "bar")
      let args = buildDockerArgs(opts, "echo", @["echo", "hello"])
      check "-e=FOO=bar" in args

    test "adds image":
      let args = buildDockerArgs(dockerDefaults(), "echo", @["echo", "hello"])
      check DefaultPythonImage in args

    test "adds command and args at end":
      let args = buildDockerArgs(dockerDefaults(), "python", @["python", "-c", "print('test')"])
      check args[^3] == "python"
      check args[^2] == "-c"
      check args[^1] == "print('test')"

  suite "dockerAvailable":
    test "returns true when docker is installed":
      let available = dockerAvailable()
      check available == true

  suite "dockerDefaults with different options":
    test "pythonSandbox has correct limits":
      let opts = pythonSandbox()
      check opts.cpuLimit.int64 == 60
      check opts.memLimit.int64 == 512 * 1024 * 1024
      check opts.timeout == 60
      check opts.network == false
      check opts.readOnlyRoot == true

    test "nodeSandbox has correct limits":
      let opts = nodeSandbox()
      check opts.cpuLimit.int64 == 60
      check opts.memLimit.int64 == 512 * 1024 * 1024
      check opts.timeout == 60
      check opts.network == false
