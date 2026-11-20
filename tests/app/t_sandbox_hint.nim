import std/[os, strtabs, strutils, times, unittest]
import results
import donkey/app/sandbox
import donkey/config/types

const FakeBin = "/tmp/donkey_fake_oci_bin"

proc makeFakeRuntime(name, body: string) =
  removeDir(FakeBin)
  createDir(FakeBin)
  let path = FakeBin / name
  writeFile(path, "#!/bin/sh\n" & body & "\n")
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc runTests*() =
  suite "sandbox docker permission hints":

    test "write probe maps permission denied to an actionable hint":
      let fake = proc(plan: SandboxPlan;
                      env: StringTableRef): tuple[output: string, exitCode: int]
                      {.gcsafe, raises: [].} =
        ("permission denied while trying to connect to the docker API at unix:///var/run/docker.sock", 1)
      let res = probeSandboxWorkspaceWritable(
        smOci, "/tmp", "alpine", "docker", false, true, fake)
      check res.isErr
      check "usermod -aG docker" in res.error
      check "systemctl --user restart donkey" in res.error

    test "executeOciPlan maps permission denied without host fallback":
      let fake = proc(plan: SandboxPlan): string {.gcsafe, raises: [].} =
        "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock"
      let output = executeOciPlan(
        "true", "/tmp", "alpine", "docker", false, false, true, fake)
      check "usermod -aG docker" in output
      check "systemctl --user restart donkey" in output

    test "sandboxAvailabilityResult maps a denied docker probe":
      makeFakeRuntime("docker",
        "echo 'permission denied while trying to connect to the docker API at unix:///var/run/docker.sock' >&2\n" &
        "exit 1")
      let oldPath = getEnv("PATH")
      putEnv("PATH", FakeBin & ":" & oldPath)
      defer:
        putEnv("PATH", oldPath)
        removeDir(FakeBin)
      let cfg = DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker")
      let res = sandboxAvailabilityResult(cfg)
      check res.isErr
      check "usermod -aG docker" in res.error

    test "sandboxAvailabilityResult accepts a reachable podman":
      makeFakeRuntime("podman", "exit 0")
      let oldPath = getEnv("PATH")
      putEnv("PATH", FakeBin & ":" & oldPath)
      defer:
        putEnv("PATH", oldPath)
        removeDir(FakeBin)
      let cfg = DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "podman")
      let res = sandboxAvailabilityResult(cfg)
      check res.isOk
      check "runtime=podman" in res.get()

    test "sandboxAvailabilityResult times out a hung probe":
      makeFakeRuntime("docker", "exec sleep 10")
      let oldPath = getEnv("PATH")
      putEnv("PATH", FakeBin & ":" & oldPath)
      defer:
        putEnv("PATH", oldPath)
        removeDir(FakeBin)
      let cfg = DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker")
      let started = epochTime()
      let res = sandboxAvailabilityResult(cfg, timeoutMs = 50)
      check res.isErr
      check epochTime() - started < 2.0

when isMainModule:
  runTests()
