## Test sandbox enforcement rules.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/config/types
import donkey/config/loader

# Since we want to test CLI behavior and initialization logic,
# we would ideally run the binary. But for a unit/integration test,
# we can test the validation logic if we extract it.

proc validateSandboxConfig(cfg: DonkeyConfig, devMode: bool): Result[void, string] =
  ## Logic to be moved to donkey.nim or a config validator.
  if not devMode and cfg.sandboxMode == smNone:
    return err("Security Error: Sandbox mode 'none' is only allowed in --dev-mode")
  ok()

suite "Sandbox Enforcement":

  test "refuses sandbox 'none' in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smNone
    )
    let res = validateSandboxConfig(cfg, devMode = false)
    check res.isErr
    check "Security Error" in res.error

  test "allows sandbox 'none' in dev mode":
    let cfg = DonkeyConfig(
      sandboxMode: smNone
    )
    let res = validateSandboxConfig(cfg, devMode = true)
    check res.isOk

  test "allows sandbox 'oci' in production mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci
    )
    let res = validateSandboxConfig(cfg, devMode = false)
    check res.isOk
