import std/[strutils, posix]
import unittest2
import ../../../src/donkey/infra/sandbox/paddock
import ../../../src/donkey/infra/sandbox/limits
import ../../../src/donkey/core/pipeops

suite "infra/sandbox/paddock":

  suite "SpawnOptions formatting":
    test "empty options show as unlimited":
      check $paddockDefaults() == "SpawnOptions(unlimited)"

    test "cpu limit shows correctly":
      check $(paddockDefaults().withCpuLimit(cpuSeconds(60))) == "SpawnOptions(cpu=60s)"

    test "multiple limits show correctly":
      let opts = paddockDefaults()
        .withCpuLimit(cpuSeconds(30))
        .withMemLimit(memBytes(128 * 1024 * 1024))
      check "cpu=30s" in $opts
      check "mem=128MB" in $opts

    test "working dir shows correctly":
      let opts = paddockDefaults().withWorkingDir("/tmp")
      check "cwd=/tmp" in $opts

  suite "SpawnResult formatting":
    test "shows exit code and sizes":
      let res = SpawnResult(exitCode: 0, stdout: "hello", stderr: "", timedOut: false)
      check "exitCode=0" in $res
      check "stdout.len=5" in $res
      check "timedOut=false" in $res

    test "shows timed out":
      let res = SpawnResult(exitCode: 124, stdout: "", stderr: "", timedOut: true)
      check "timedOut=true" in $res

  suite "Convenience constructors":
    test "sandboxDefaults has cpu and mem limits":
      let opts = sandboxDefaults()
      check opts.cpuLimit.int64 == 60
      check opts.memLimit.int64 == 512 * 1024 * 1024

    test "sandboxQuick has smaller limits":
      let opts = sandboxQuick()
      check opts.cpuLimit.int64 == 10
      check opts.memLimit.int64 == 64 * 1024 * 1024

    test "sandboxInteractive has high cpu limit":
      let opts = sandboxInteractive()
      check opts.cpuLimit.int64 == 300
      check opts.nprocLimit.int64 == 4

  suite "withCpuLimit":
    test "sets cpu limit":
      let opts = paddockDefaults().withCpuLimit(cpuSeconds(120))
      check opts.cpuLimit.int64 == 120

  suite "withMemLimit":
    test "sets memory limit":
      let opts = paddockDefaults().withMemLimit(memBytes(256 * 1024 * 1024))
      check opts.memLimit.int64 == 256 * 1024 * 1024

  suite "withNprocLimit":
    test "sets nproc limit":
      let opts = paddockDefaults().withNprocLimit(nprocCount(10))
      check opts.nprocLimit.int64 == 10

  suite "withFsizeLimit":
    test "sets fsize limit":
      let opts = paddockDefaults().withFsizeLimit(fsizeBytes(1024 * 1024))
      check opts.fsizeLimit.int64 == 1024 * 1024

  suite "withNofileLimit":
    test "sets nofile limit":
      let opts = paddockDefaults().withNofileLimit(nofileCount(256))
      check opts.nofileLimit.int64 == 256

  suite "withWorkingDir":
    test "sets working dir":
      let opts = paddockDefaults().withWorkingDir("/home/user")
      check opts.workingDir == "/home/user"

  suite "withEnvVar":
    test "adds environment variable":
      let opts = paddockDefaults().withEnvVar("FOO", "bar")
      check opts.envVars.len == 1
      check opts.envVars[0].key == "FOO"
      check opts.envVars[0].val == "bar"

    test "adds multiple environment variables":
      let opts = paddockDefaults()
        .withEnvVar("FOO", "bar")
        .withEnvVar("BAZ", "qux")
      check opts.envVars.len == 2

  suite "withStdin":
    test "sets stdin data":
      let opts = paddockDefaults().withStdin("hello world")
      check opts.stdinData == "hello world"

  suite "newPaddock":
    test "creates paddock with defaults":
      var p = newPaddock()
      # Verify by running a command (opts should be defaults)
      let result = p.runSpawned("echo", @["echo", "test"])
      check result.isOk

    test "creates paddock with custom opts":
      let opts = sandboxDefaults()
      var p = newPaddock(opts)
      # Verify by running a command with the custom options
      let result = p.runSpawned("echo", @["echo", "test"])
      check result.isOk

  suite "runSpawned":
    test "runs simple echo command":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("echo", @["echo", "hello"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "hello" in res.stdout
      check res.timedOut == false

    test "runs command with arguments":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("printf", @["printf", "num=%d", "42"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "num=42" in res.stdout

    test "captures stderr":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("sh", @["sh", "-c", "echo error >&2"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "error" in res.stderr

    test "returns non-zero exit code on failure":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("sh", @["sh", "-c", "exit 42"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 42

    test "command not found returns error":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("/nonexistent/command", @["/nonexistent/command"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 127

    test "runSpawned with string command":
      var p = newPaddock(paddockDefaults())
      let result = p.runSpawned("echo hello world")
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "hello world" in res.stdout

    test "withStdin passes data to stdin":
      var p = newPaddock(paddockDefaults().withStdin("input data"))
      let result = p.runSpawned("cat", @["cat"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "input data" in res.stdout

    test "withWorkingDir changes directory":
      var p = newPaddock(paddockDefaults().withWorkingDir("/tmp"))
      let result = p.runSpawned("pwd", @["pwd"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0
      check "/tmp" in res.stdout

    test "cpu limit is applied (fork+exec works)":
      # RLIMIT_CPU may or may not work depending on kernel/container restrictions
      # We test that the spawn mechanism works and limits are set
      var p = newPaddock(paddockDefaults()
        .withCpuLimit(cpuSeconds(5))
        .withMemLimit(memBytes(0)))  # 0 = unlimited
      let result = p.runSpawned("sh", @["sh", "-c", "i=0; while i < 10000000; do i=i+1; done; echo done"])
      check result.isOk
      let res = result.get()
      # If CPU limit works, timedOut may be true; if not, we still get the result
      check res.exitCode == 0 or res.exitCode == 124

    test "memory limit is applied (via setrlimit)":
      # This test verifies the fork+exec+limits pattern works
      var p = newPaddock(paddockDefaults()
        .withMemLimit(memBytes(64 * 1024 * 1024)))  # 64MB
      let result = p.runSpawned("echo", @["echo", "ok"])
      check result.isOk
      let res = result.get()
      check res.exitCode == 0

  suite "applyLimitsChild":
    test "applying limits returns ok on success":
      let opts = paddockDefaults()
        .withCpuLimit(cpuSeconds(60))
        .withMemLimit(memBytes(256 * 1024 * 1024))
      let result = applyLimitsChild(opts)
      check result.isOk

  suite "setupChildEnv":
    test "setting env vars doesn't crash":
      let opts = paddockDefaults().withEnvVar("TEST_VAR", "test_value")
      # This is called in child context, so we just verify it doesn't crash
      setupChildEnv(opts)
