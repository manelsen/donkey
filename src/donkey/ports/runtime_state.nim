## RuntimeStatePort — durable session registry and outbound delivery ledger.
##
## The hot path keeps authoritative state in memory:
##   - `SessionManager` owns live session entries;
##   - outbound routing sends directly through `ChannelPort`.
##
## These ports are best-effort persistence/audit sinks around that hot path.
## Implementations live in `adapters/state/`; application code only sees the
## callback structs below. A nil callback means persistence is disabled.

import ../core/pipeops
import ../core/types

type
  SessionRegistryRecord* = object
    ## Durable metadata for one user session.
    userId*: string
    channels*: seq[(ChannelKind, string)]
    lastInboundAtMs*: int64          ## wall-clock epoch milliseconds
    sessionId*: string
    runtimeSignature*: string

  SessionRegistryPort* = object
    loadAll*: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe, raises: [].}
    upsert*:  proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe, raises: [].}

  DeliveryState* = enum
    dlsPending = "pending"
    dlsSent    = "sent"
    dlsFailed  = "failed"

  DeliveryRecord* = object
    ## One outbound delivery attempt.
    id*:          string
    userId*:      string
    channel*:     ChannelKind
    channelId*:   string
    textHash*:    string              ## short non-reversible reference to text
    state*:       DeliveryState
    attempts*:    int
    createdAtMs*: int64
    updatedAtMs*: int64
    error*:       string

  DeliveryLedgerPort* = object
    recordPending*: proc(record: DeliveryRecord): Result[void, string] {.gcsafe, raises: [].}
    markSent*:      proc(id: string; updatedAtMs: int64): Result[void, string] {.gcsafe, raises: [].}
    markFailed*:    proc(id: string; updatedAtMs: int64; error: string): Result[void, string] {.gcsafe, raises: [].}
    loadAll*:       proc(): Result[seq[DeliveryRecord], string] {.gcsafe, raises: [].}

func hasSessionRegistry*(p: SessionRegistryPort): bool =
  p.loadAll != nil and p.upsert != nil

func hasDeliveryLedger*(p: DeliveryLedgerPort): bool =
  p.recordPending != nil and p.markSent != nil and
    p.markFailed != nil and p.loadAll != nil

func parseChannelKindName*(name: string; value: var ChannelKind): bool =
  ## Parses the string spelling of a `ChannelKind` (e.g. "telegram").
  for kind in ChannelKind:
    if $kind == name:
      value = kind
      return true
  false
