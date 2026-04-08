## Test sandbox enforcement rules.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/config/types
import donkey/config/loader
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
