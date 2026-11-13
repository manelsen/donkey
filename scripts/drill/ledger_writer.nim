## Drill helper: append delivery records forever while the compaction worker
## runs. Kill -9 this process and use ledger_recover.nim to verify the state.

import std/os
import donkey/adapters/state/runtime_store
import donkey/core/pipeops
import donkey/core/types
import donkey/ports/runtime_state

let dir = paramStr(1)
var store = newRuntimeStateStore(
  dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
let workerRes = startLedgerCompactionWorker(addr store, 1.0)
if workerRes.isErr:
  stderr.writeLine("worker failed: " & workerRes.error)
  quit(1)
let ledger = store.deliveryLedger()
var i = 0
while true:
  let now = epochMs()
  let id = "drill-" & $i
  let pending = ledger.recordPending(DeliveryRecord(
    id: id, userId: "drill", channel: ckSlack, channelId: "drill",
    textHash: "h", state: dlsPending, createdAtMs: now, updatedAtMs: now))
  if pending.isErr:
    stderr.writeLine("recordPending failed: " & pending.error)
    quit(1)
  let sent = ledger.markSent(id, now)
  if sent.isErr:
    stderr.writeLine("markSent failed: " & sent.error)
    quit(1)
  inc i
  if i mod 50 == 0:
    echo i
