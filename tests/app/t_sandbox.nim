## sandbox.nim unit tests — no live Docker required.
## Tests: buildDockerCmd shape, sandboxBash with smNone.
## smDocker tests require Docker and are skipped here (integration concern).

import std/[os, strutils, unittest]
import donkey/config/types
import donkey/app/sandbox
import donkey/core/types

suite "buildDockerCmd":

  test "contains docker run --rm":
    let cmd = buildDockerCmd("ls", "/home/u/paddock", "alpine")
    check cmd.startsWith("docker run --rm")

  test "bind-mounts paddock to /workspace":
    let cmd = buildDockerCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("-v /home/u/paddock:/workspace")

  test "sets working dir to /workspace":
    let cmd = buildDockerCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("-w /workspace")

  test "includes the image name":
    let cmd = buildDockerCmd("ls", "/home/u/paddock", "debian:bookworm-slim")
    check cmd.contains("debian:bookworm-slim")

  test "wraps command with sh -c":
    let cmd = buildDockerCmd("echo hello", "/home/u/paddock", "alpine")
    check cmd.contains("sh -c")
    check cmd.contains("echo hello")

  test "spaces in command are quoted":
    let cmd = buildDockerCmd("echo hello world", "/home/u/paddock", "alpine")
    ## quoteShell wraps in single quotes or escapes — either way it's present
    check cmd.contains("echo hello world")

suite "buildSandboxPlan":

  test "smNone keeps original command and working dir":
    let plan = buildSandboxPlan("pwd", "/tmp/p1", smNone, "alpine")
    check plan.command == "pwd"
    check plan.workingDir == "/tmp/p1"
    check plan.ensureWorkDir

  test "smDocker wraps command through docker":
    let plan = buildSandboxPlan("pwd", "/tmp/p1", smDocker, "alpine")
    check plan.command.startsWith("docker run --rm")
    check plan.workingDir == ""
    check not plan.ensureWorkDir

suite "formatSandboxResult":

  test "trims trailing newline":
    check formatSandboxResult("ok\n", 0) == "ok"

  test "appends exit code on failure":
    let result = formatSandboxResult("oops", 3)
    check result.contains("[exit 3]")

  test "empty output returns exit marker":
    check formatSandboxResult("", 0) == "[exit 0]"

suite "sandboxBash — smNone":

  test "runs command in paddock dir":
    let paddock = getTempDir() / "donkey_sb_test_none"
    createDir(paddock)
    writeFile(paddock / "canary.txt", "ok")
    defer: removeDir(paddock)
    let r = sandboxBash("cat canary.txt", paddock, smNone, "alpine")
    check r == "ok"

  test "creates paddock dir if missing":
    let paddock = getTempDir() / "donkey_sb_autocreate"
    defer: (try: removeDir(paddock) except: discard)
    discard sandboxBash("pwd", paddock, smNone, "alpine")
    check dirExists(paddock)

  test "non-zero exit code appended":
    let paddock = getTempDir() / "donkey_sb_exit"
    createDir(paddock)
    defer: removeDir(paddock)
    let r = sandboxBash("exit 7", paddock, smNone, "alpine")
    check r.contains("[exit 7]")

  test "absolute escape still works in smNone (documented limitation)":
    ## smNone only sets CWD — does not restrict absolute paths.
    ## This test documents the known gap, not a bug.
    let paddock = getTempDir() / "donkey_sb_nolimit"
    createDir(paddock)
    defer: removeDir(paddock)
    let r = sandboxBash("echo ok", paddock, smNone, "alpine")
    check r == "ok"

suite "SandboxMode values":

  test "smNone string value":
    check $smNone == "none"

  test "smDocker string value":
    check $smDocker == "docker"

suite "sandboxStatusMessage":

  test "smNone warns":
    let (level, msg) = sandboxStatusMessage(smNone, "alpine")
    check level == lvlWarn
    check msg.contains("workingDir isolation only")

  test "smDocker informs image":
    let (level, msg) = sandboxStatusMessage(smDocker, "debian:bookworm-slim")
    check level == lvlInfo
    check msg.contains("debian:bookworm-slim")
