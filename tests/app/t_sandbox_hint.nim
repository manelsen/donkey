import std/[strtabs, strutils, unittest]
import results
import donkey/app/sandbox
import donkey/config/types

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
