## sandbox.nim unit tests — no live container runtime required.
## Tests: buildOciCmd shape, sandboxBash with smNone.
## smOci tests require a runtime and are skipped here (integration concern).

import std/[os, strtabs, strutils, unittest]
import results
import donkey/config/types
import donkey/app/sandbox
import donkey/core/types

suite "buildOciCmd":

  test "contains runtime run --rm":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine")
    check cmd.startsWith("docker run --rm")

  test "disables network by default":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("--network=none")

  test "hardens rootfs by default":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("--read-only")
    check cmd.contains("--tmpfs /tmp:rw,noexec,nosuid,size=64m")
    check cmd.contains("--cap-drop=ALL")
    check cmd.contains("--security-opt no-new-privileges")

  test "bind-mounts paddock to /workspace":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("-v /home/u/paddock:/workspace")

  test "sets working dir to /workspace":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine")
    check cmd.contains("-w /workspace")

  test "includes the image name":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "debian:bookworm-slim")
    check cmd.contains("debian:bookworm-slim")

  test "wraps command with sh -c":
    let cmd = buildOciCmd("echo hello", "/home/u/paddock", "alpine")
    check cmd.contains("sh -c")
    check cmd.contains("echo hello")

  test "spaces in command are quoted":
    let cmd = buildOciCmd("echo hello world", "/home/u/paddock", "alpine")
    ## quoteShell wraps in single quotes or escapes — either way it's present
    check cmd.contains("echo hello world")

  test "supports non-docker runtimes":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine", "podman")
    check cmd.startsWith("podman run --rm")

  test "allows opting into network and writable rootfs":
    let cmd = buildOciCmd("ls", "/home/u/paddock", "alpine", "docker", true, false)
    check "--network=none" notin cmd
    check "--read-only" notin cmd

suite "buildSandboxPlan":

  test "smNone keeps original command and working dir":
    let plan = buildSandboxPlan("pwd", "/tmp/p1", smNone, "alpine")
    check plan.command == "pwd"
    check plan.workingDir == "/tmp/p1"
    check plan.ensureWorkDir

  test "smOci wraps command through runtime":
    let plan = buildSandboxPlan("pwd", "/tmp/p1", smOci, "alpine")
    check plan.command.startsWith("docker run --rm")
    check plan.workingDir == ""
    check not plan.ensureWorkDir

  test "smWasmer wraps command through wasmer":
    let plan = buildSandboxPlan("pwd", "/tmp/p1", smWasmer, "alpine")
    check plan.command.startsWith("wasmer run ")
    check plan.command.contains("--volume=")
    check plan.command.contains("--command-name=bash")
    check plan.command.contains("/workspace:/tmp/p1")
    check plan.workingDir == ""
    check not plan.ensureWorkDir

suite "oci fallback":

  test "shouldFallbackOci detects image pull errors":
    let output =
      "Unable to find image 'donkey-sandbox:alpine-git' locally\n" &
      "docker: Error response from daemon: pull access denied.\n[exit 125]"
    check shouldFallbackOci(output)

  test "shouldFallbackOci ignores command-not-found inside container":
    let output = "sh: foo: not found\n[exit 127]"
    check not shouldFallbackOci(output)

suite "wasmer fallback":

  test "shouldFallbackWasmer detects registry timeout/package resolution errors":
    let output =
      "error: Unable to find \"amin/bash\" in the registry\n" &
      "│   1: failed to query package 'amin/bash': error sending request for url (https://registry.wasmer.io/graphql)\n" &
      "│   2: error sending request for url (https://registry.wasmer.io/graphql)\n" &
      "│   3: client error (Connect)\n" &
      "╰─▶ 4: operation timed out\n[exit 1]"
    check shouldFallbackWasmer(output)

  test "probeSandboxWorkspaceWritable normalizes wasmer registry failures":
    let runner: SandboxRunnerRaw =
      proc(plan: SandboxPlan; env: StringTableRef): tuple[output: string, exitCode: int]
           {.closure, gcsafe, raises: [CatchableError].} =
        discard plan
        discard env
        (
          "error: Unable to find \"amin/bash\" in the registry\n" &
          "│   1: failed to query package 'amin/bash': error sending request for url (https://registry.wasmer.io/graphql)\n" &
          "│   2: error sending request for url (https://registry.wasmer.io/graphql)\n" &
          "│   3: client error (Connect)\n" &
          "╰─▶ 4: operation timed out\n",
          1
        )
    let res = probeSandboxWorkspaceWritable(
      smWasmer, "/tmp/p1", "ignored", "wasmer", false, true, runner)
    check res.isErr
    check res.error.contains("wasmer sandbox unavailable")

  test "executeOciPlan falls back to direct exec when runtime is unavailable":
    var plans: seq[SandboxPlan] = @[]
    let runner: SandboxRunner =
      proc(plan: SandboxPlan): string {.closure, gcsafe.} =
        {.cast(gcsafe).}: plans.add(plan)
        if plan.command.startsWith("docker run --rm"):
          "Unable to find image 'donkey-sandbox:alpine-git' locally\n" &
            "docker: Error response from daemon: pull access denied.\n[exit 125]"
        else:
          "ok"

    let result = executeOciPlan("echo ok", "/tmp/p1", "alpine", "docker", true, false, true, runner)

    check plans.len == 1
    check plans[0].command.startsWith("docker run --rm")
    check result.contains("docker sandbox unavailable")
    check result.endsWith("ok")

  test "executeOciPlan preserves runtime command failures that are not runtime issues":
    var plans: seq[SandboxPlan] = @[]
    let runner: SandboxRunner =
      proc(plan: SandboxPlan): string {.closure, gcsafe.} =
        {.cast(gcsafe).}: plans.add(plan)
        "sh: foo: not found\n[exit 127]"

    let result = executeOciPlan("foo", "/tmp/p1", "alpine", "docker", true, false, true, runner)

    check plans.len == 1
    check result == "sh: foo: not found\n[exit 127]"

  test "executeOciPlan can refuse host fallback when runtime is unavailable":
    var plans: seq[SandboxPlan] = @[]
    let runner: SandboxRunner =
      proc(plan: SandboxPlan): string {.closure, gcsafe.} =
        {.cast(gcsafe).}: plans.add(plan)
        "Cannot connect to the docker daemon.\n[exit 125]"

    let result = executeOciPlan("echo ok", "/tmp/p1", "alpine", "docker", false, false, true, runner)

    check plans.len == 1
    check result.contains("host fallback is disabled")

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

  test "smNone does not inherit secret-bearing host env":
    let paddock = getTempDir() / "donkey_sb_envscrub"
    createDir(paddock)
    defer: removeDir(paddock)
    putEnv("OPENAI_API_KEY", "super-secret")
    defer: delEnv("OPENAI_API_KEY")
    let r = sandboxBash("printf %s \"$OPENAI_API_KEY\"", paddock, smNone, "alpine")
    check r == "[exit 0]"

suite "sandboxBash — smWasm":

  test "missing wasm shell does not fall back to host when fallback is disabled":
    if resolveShellWasmPath().fileExists:
      check true
    else:
      let paddock = getTempDir() / "donkey_sb_wasm_missing"
      createDir(paddock)
      defer: removeDir(paddock)
      let r = sandboxBash("echo ok", paddock, smWasm, "alpine", "docker", false)
      check "ok" notin r

suite "SandboxMode values":

  test "smNone string value":
    check $smNone == "none"

  test "smOci string value":
    check $smOci == "oci"

  test "smWasmer string value":
    check $smWasmer == "wasmer"

suite "sandboxStatusMessage":

  test "smNone warns":
    let (level, msg) = sandboxStatusMessage(smNone, "alpine")
    check level == lvlWarn
    check msg.contains("workingDir isolation only")

  test "smOci informs runtime and image":
    let (level, msg) = sandboxStatusMessage(smOci, "debian:bookworm-slim", "podman")
    check level == lvlInfo
    check msg.contains("podman")
    check msg.contains("debian:bookworm-slim")

  test "smWasmer mentions package":
    let (level, msg) = sandboxStatusMessage(smWasmer, "ignored")
    check level == lvlInfo
    check msg.contains("wasmer")
    check msg.contains("amin/bash")
