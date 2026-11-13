## Drill helper: reopen the ledger after a kill -9 and verify replay.

import std/os
import donkey/core/pipeops
import donkey/adapters/state/runtime_store

let dir = paramStr(1)
let store = newRuntimeStateStore(
  dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
let loaded = store.deliveryLedger().loadAll()
if loaded.isErr:
  stderr.writeLine("recovery failed: " & loaded.error)
  quit(1)
echo "records=" & $loaded.get().len
echo "compact_error=" & store.ledgerLastCompactError()
