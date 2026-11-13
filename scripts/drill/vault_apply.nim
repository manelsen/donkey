## Drill helper: apply the encrypted vault to the environment and print one
## value. Used by the operational drill; not part of the daemon.

import std/os
import donkey/core/pipeops
import donkey/adapters/secrets/vault

let home = paramStr(1)
let secretVault = newSecretVault(home)
let applied = secretVault.applyToEnv()
if applied.isErr:
  stderr.writeLine("vault apply failed: " & applied.error)
  quit(1)
echo "applied=" & $applied.get()
echo "token=" & getEnv("DRILL_TOKEN")
