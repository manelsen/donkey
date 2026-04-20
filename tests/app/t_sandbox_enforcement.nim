## Test sandbox enforcement rules.

import std/[os, strtabs, strutils, unittest]
import donkey/core/pipeops
import donkey/config/types
import donkey/app/sandbox

suite "Sandbox Enforcement":

  test "refuses sandbox 'none' in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smNone
    )
    let res = validateSandboxPolicy(cfg, devMode = false)
    check res.isErr
    check "Security Error" in res.error

  test "allows sandbox 'none' in dev mode":
    let cfg = DonkeyConfig(
      sandboxMode: smNone
    )
    let res = validateSandboxPolicy(cfg, devMode = true)
    check res.isOk

  test "allows sandbox 'oci' in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: true
    )
    let res = validateSandboxPolicy(cfg, devMode = false)
    check res.isOk

  test "refuses host fallback in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxAllowHostFallback: true
    )
    let res = validateSandboxPolicy(cfg, devMode = false)
    check res.isErr
    check "allow_host_fallback" in res.error

  test "allows host fallback in dev mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxAllowHostFallback: true
    )
    let res = validateSandboxPolicy(cfg, devMode = true)
    check res.isOk

  test "refuses oci network egress in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxAllowNetwork: true,
      sandboxReadOnlyRootfs: true
    )
    let res = validateSandboxPolicy(cfg, devMode = false)
    check res.isErr
    check "allow_network" in res.error

  test "refuses writable oci rootfs in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: false
    )
    let res = validateSandboxPolicy(cfg, devMode = false)
    check res.isErr
    check "read_only_rootfs" in res.error

  test "allows matching paddock ownership in production mode":
    let cfg = DonkeyConfig(paddocks: "/tmp/paddocks")
    let ownerFn: PathOwnerFn = proc(path: string): Result[int, string] {.gcsafe.} =
      discard path
      ok(1000)
    let res = validatePaddockOwnership(cfg, devMode = false, ownerFn = ownerFn, uid = 1000)
    check res.isOk

  test "refuses mismatched paddock ownership in production mode":
    let root = getTempDir() / "donkey_owner_guard_mismatch"
    try: removeDir(root) except OSError: discard
    createDir(root / "u1" / "memory")
    writeFile(root / "u1" / "memory" / "heartbeat-state.json", "{}")
    defer:
      try: removeDir(root) except OSError: discard
    let ownerFn: PathOwnerFn = proc(path: string): Result[int, string] {.gcsafe.} =
      if path.endsWith("heartbeat-state.json"): ok(0)
      else: ok(1000)
    let cfg = DonkeyConfig(paddocks: root)
    let res = validatePaddockOwnership(cfg, devMode = false, ownerFn = ownerFn, uid = 1000)
    check res.isErr
    check "Security Error" in res.error
    check "heartbeat-state.json" in res.error

  test "ignores mismatched paddock ownership in dev mode":
    let root = getTempDir() / "donkey_owner_guard_dev"
    try: removeDir(root) except OSError: discard
    createDir(root / "u1")
    defer:
      try: removeDir(root) except OSError: discard
    let ownerFn: PathOwnerFn = proc(path: string): Result[int, string] {.gcsafe.} =
      discard path
      ok(0)
    let cfg = DonkeyConfig(paddocks: root)
    let res = validatePaddockOwnership(cfg, devMode = true, ownerFn = ownerFn, uid = 1000)
    check res.isOk

  test "workspace write probe succeeds on zero exit":
    let runner: SandboxRunnerRaw =
      proc(plan: SandboxPlan; env: StringTableRef): tuple[output: string, exitCode: int]
           {.closure, gcsafe, raises: [CatchableError].} =
        discard plan
        discard env
        ("", 0)
    let res = probeSandboxWorkspaceWritable(
      smOci, "/tmp/paddock", "alpine", runPlanRaw = runner)
    check res.isOk

  test "workspace write probe command uses create and cleanup":
    let cmd = buildSandboxWriteProbeCmd()
    check "touch " in cmd
    check "rm -f " in cmd
    check SandboxWriteProbeFile in cmd

  test "workspace write probe returns formatted failure":
    let runner: SandboxRunnerRaw =
      proc(plan: SandboxPlan; env: StringTableRef): tuple[output: string, exitCode: int]
           {.closure, gcsafe, raises: [CatchableError].} =
        discard plan
        discard env
        ("touch: permission denied\n", 1)
    let res = probeSandboxWorkspaceWritable(
      smOci, "/tmp/paddock", "alpine", runPlanRaw = runner)
    check res.isErr
    check "permission denied" in res.error
    check "[exit 1]" in res.error
