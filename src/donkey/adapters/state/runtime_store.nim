## runtime_store — atomic file-backed session registry and delivery ledger.
##
## Layout under `$DONKEY_HOME/state/`:
##   sessions.json         full registry, replaced atomically (write tmp + fsync + rename)
##   delivery_ledger.jsonl append-only, newline-framed event log
##
## Both stores are deliberately small and simple: the daemon is the only writer
## and owns at most a few sessions. I/O failures are returned as `Err`; callers
## on the hot path log and continue.

import std/[json, options, os, strutils, tables]
when defined(posix):
  import std/posix
import ../../core/pipeops
import ../../core/types
import ../../ports/runtime_state

const
  SessionsFileName*     = "sessions.json"
  DeliveryLedgerFileName* = "delivery_ledger.jsonl"
  RegistryVersion*      = 1

type
  RuntimeStateStore* = ref object
    stateDir*: string
    ## Records still awaiting `sent`/`failed`. Loaded once at construction so
    ## the hot path does not replay the ledger file on every update.
    pending*: Table[string, DeliveryRecord]

  StoreError = object of CatchableError

  ## One ledger line. Every field except `id` is optional so a later minimal
  ## event (`id`, `state`, `updated_at_ms`, `error`) can be merged on top of a
  ## full `pending` event without erasing delivery metadata.
  LedgerEvent = object
    id: string
    userId: Option[string]
    channel: Option[ChannelKind]
    channelId: Option[string]
    textHash: Option[string]
    state: Option[DeliveryState]
    attempts: Option[int]
    createdAtMs: Option[int64]
    updatedAtMs: Option[int64]
    error: Option[string]

func sessionsPath(store: RuntimeStateStore): string =
  store.stateDir / SessionsFileName

func ledgerPath(store: RuntimeStateStore): string =
  store.stateDir / DeliveryLedgerFileName

when defined(posix):
  proc cRename(oldname, newname: cstring): cint {.
    importc: "rename", header: "<stdio.h>".}

when defined(macosx):
  ## On macOS a plain `fsync` only pushes data to the drive cache; `fcntl`
  ## with `F_FULLFSYNC` asks the drive to flush its own cache as well.
  var F_FULLFSYNC {.importc, header: "<fcntl.h>".}: cint

proc syncFile(f: File; path: string): Result[void, string] =
  ## Flush userspace buffers, then ask the OS to persist the file contents.
  ## Best effort on filesystems that ignore `fsync` (documented in
  ## SPEC_RUNTIME.md).
  try:
    f.flushFile()
  except CatchableError as e:
    return err("flush failed for " & path & ": " & e.msg)
  when defined(posix):
    let fd = cint(f.getFileHandle())
    when defined(macosx):
      if posix.fcntl(fd, F_FULLFSYNC) == 0:
        return ok()
      ## Some filesystems do not implement F_FULLFSYNC; fall back to fsync.
    if posix.fsync(fd) != 0:
      return err("fsync failed for " & path & ": " & osErrorMsg(osLastError()))
  ok()

proc syncDir(path: string): Result[void, string] =
  ## Persist a directory entry (needed after `rename`) on POSIX.
  when defined(posix):
    try:
      let fd = posix.open(path.cstring, posix.O_RDONLY)
      if fd < 0:
        return err("open failed for directory " & path & ": " &
                   osErrorMsg(osLastError()))
      defer: discard posix.close(fd)
      if posix.fsync(fd) != 0:
        return err("fsync failed for directory " & path & ": " &
                   osErrorMsg(osLastError()))
    except CatchableError as e:
      return err("fsync failed for directory " & path & ": " & e.msg)
  ok()

proc removeQuietly(path: string) =
  try:
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc renamePath(source, dest: string): Result[void, string] =
  ## Atomic replace. `std/os.moveFile` is avoided on POSIX because its effect
  ## inference includes `Exception` (from an unreachable stdlib re-raise),
  ## which would leak through `raises: []` port boundaries.
  when defined(posix):
    if cRename(source.cstring, dest.cstring) != 0:
      return err("rename failed for " & source & ": " & osErrorMsg(osLastError()))
    ok()
  else:
    try:
      {.cast(raises: []).}:
        moveFile(source, dest)
      ok()
    except CatchableError as e:
      err("rename failed for " & source & ": " & e.msg)

proc atomicWriteText(path, content: string): Result[void, string] =
  ## Writes to a sibling temp file, fsyncs it, renames it over the destination
  ## and fsyncs the parent directory.
  let tmp = path & ".tmp"
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
    var syncError = ""
    var f = open(tmp, fmWrite)
    try:
      f.write(content)
      let synced = syncFile(f, tmp)
      if synced.isErr:
        syncError = synced.error
    finally:
      f.close()
    if syncError.len > 0:
      removeQuietly(tmp)
      return err(syncError)
    let renamed = renamePath(tmp, path)
    if renamed.isErr:
      removeQuietly(tmp)
      return err(renamed.error)
    if dir.len > 0:
      let dirSynced = syncDir(dir)
      if dirSynced.isErr:
        return err(dirSynced.error)
    ok()
  except CatchableError as e:
    removeQuietly(tmp)
    err("atomic write failed for " & path & ": " & e.msg)

proc appendJsonLine(path: string; node: JsonNode): Result[void, string] =
  ## Appends one newline-framed record and fsyncs it. Framing both sides means
  ## a torn write can never merge with the following event.
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
    var f = open(path, fmAppend)
    try:
      f.write("\n" & $node & "\n")
      let synced = syncFile(f, path)
      if synced.isErr:
        return err(synced.error)
    finally:
      f.close()
    ok()
  except CatchableError as e:
    err("append failed for " & path & ": " & e.msg)

func jsonInt(node: JsonNode; key: string; default: int64 = 0): int64 =
  let value = node{key}
  if value == nil:
    return default
  case value.kind
  of JInt:   value.getInt.int64
  of JFloat: value.getFloat.int64
  else:      default

func jsonStr(node: JsonNode; key: string; default = ""): string =
  let value = node{key}
  if value == nil or value.kind == JNull:
    return default
  if value.kind == JString:
    return value.getStr
  default

proc sessionToJson(record: SessionRegistryRecord): JsonNode =
  var channels = newJArray()
  for (kind, rawId) in record.channels:
    channels.add(%* {"kind": $kind, "id": rawId})
  %* {
    "user_id": record.userId,
    "channels": channels,
    "last_inbound_at_ms": record.lastInboundAtMs,
    "session_id": record.sessionId,
    "runtime_signature": record.runtimeSignature,
  }

proc sessionFromJson(node: JsonNode): Option[SessionRegistryRecord] =
  if node == nil or node.kind != JObject:
    return none(SessionRegistryRecord)
  let userId = jsonStr(node, "user_id")
  if userId.len == 0:
    return none(SessionRegistryRecord)
  var record = SessionRegistryRecord(
    userId: userId,
    lastInboundAtMs: jsonInt(node, "last_inbound_at_ms"),
    sessionId: jsonStr(node, "session_id"),
    runtimeSignature: jsonStr(node, "runtime_signature"),
  )
  let channels = node{"channels"}
  if channels != nil and channels.kind == JArray:
    for item in channels:
      if item.kind != JObject:
        continue
      var kind: ChannelKind
      if parseChannelKindName(jsonStr(item, "kind"), kind):
        let rawId = jsonStr(item, "id")
        if rawId.len > 0:
          record.channels.add((kind, rawId))
  some(record)

proc backupCorruptSessions(store: RuntimeStateStore;
                           path: string): Result[void, string] {.raises: [].} =
  ## Moves an unreadable/invalid registry aside so writes can resume.
  let base = path & ".corrupt-" & $epochMs()
  var target = base
  var suffix = 1
  while fileExists(target):
    target = base & "-" & $suffix
    inc suffix
  let renamed = renamePath(path, target)
  if renamed.isErr:
    return err("session registry corrupt backup failed: " & renamed.error)
  ok()

proc loadSessions(store: RuntimeStateStore): Result[seq[SessionRegistryRecord], string] {.raises: [].} =
  let path = store.sessionsPath()
  if not fileExists(path):
    return ok(newSeq[SessionRegistryRecord]())
  var raw = ""
  try:
    raw = readFile(path)
  except CatchableError:
    let backed = store.backupCorruptSessions(path)
    if backed.isErr:
      return err(backed.error)
    return ok(newSeq[SessionRegistryRecord]())
  var parsed: JsonNode
  try:
    parsed = parseJson(raw)
  except CatchableError:
    let backed = store.backupCorruptSessions(path)
    if backed.isErr:
      return err(backed.error)
    return ok(newSeq[SessionRegistryRecord]())
  if parsed.kind != JObject:
    let backed = store.backupCorruptSessions(path)
    if backed.isErr:
      return err(backed.error)
    return ok(newSeq[SessionRegistryRecord]())
  let version = jsonInt(parsed, "version", RegistryVersion)
  if version > RegistryVersion:
    ## Forward-incompatible state is preserved, never treated as corruption.
    return err("unsupported session registry version: " & $version)
  var records: seq[SessionRegistryRecord] = @[]
  let sessions = parsed{"sessions"}
  if sessions != nil and sessions.kind == JArray:
    for item in sessions:
      let parsedRecord = sessionFromJson(item)
      if parsedRecord.isSome:
        records.add(parsedRecord.get)
  ok(records)

proc saveSessions(store: RuntimeStateStore;
                  records: seq[SessionRegistryRecord]): Result[void, string] =
  var sessions = newJArray()
  for record in records:
    sessions.add(sessionToJson(record))
  let payload = %* {
    "version": RegistryVersion,
    "sessions": sessions,
  }
  atomicWriteText(store.sessionsPath(), $payload)

proc upsertSession(store: RuntimeStateStore;
                   record: SessionRegistryRecord): Result[void, string] {.raises: [].} =
  let loaded = store.loadSessions()
  if loaded.isErr:
    return err(loaded.error)
  var records = loaded.value
  var replaced = false
  for i in 0 ..< records.len:
    if records[i].userId == record.userId:
      records[i] = record
      replaced = true
      break
  if not replaced:
    records.add(record)
  store.saveSessions(records)

proc deliveryToJson(record: DeliveryRecord): JsonNode =
  %* {
    "id": record.id,
    "user_id": record.userId,
    "channel": $record.channel,
    "channel_id": record.channelId,
    "text_hash": record.textHash,
    "state": $record.state,
    "attempts": record.attempts,
    "created_at_ms": record.createdAtMs,
    "updated_at_ms": record.updatedAtMs,
    "error": record.error,
  }

proc ledgerEventFromJson(node: JsonNode): Option[LedgerEvent] =
  if node == nil or node.kind != JObject:
    return none(LedgerEvent)
  let id = jsonStr(node, "id")
  if id.len == 0:
    return none(LedgerEvent)
  var event = LedgerEvent(id: id)
  if node{"user_id"} != nil:
    event.userId = some(jsonStr(node, "user_id"))
  if node{"channel"} != nil:
    var channel: ChannelKind
    if not parseChannelKindName(jsonStr(node, "channel"), channel):
      return none(LedgerEvent)
    event.channel = some(channel)
  if node{"channel_id"} != nil:
    event.channelId = some(jsonStr(node, "channel_id"))
  if node{"text_hash"} != nil:
    event.textHash = some(jsonStr(node, "text_hash"))
  if node{"state"} != nil:
    case jsonStr(node, "state")
    of $dlsPending: event.state = some(dlsPending)
    of $dlsSent:    event.state = some(dlsSent)
    of $dlsFailed:  event.state = some(dlsFailed)
    else:           return none(LedgerEvent)
  if node{"attempts"} != nil:
    event.attempts = some(jsonInt(node, "attempts", 0).int)
  if node{"created_at_ms"} != nil:
    event.createdAtMs = some(jsonInt(node, "created_at_ms"))
  if node{"updated_at_ms"} != nil:
    event.updatedAtMs = some(jsonInt(node, "updated_at_ms"))
  if node{"error"} != nil:
    event.error = some(jsonStr(node, "error"))
  some(event)

proc mergeEvent(records: var Table[string, DeliveryRecord];
                order: var seq[string];
                event: LedgerEvent) =
  ## Merges one event per id. A minimal event keeps the metadata written by an
  ## earlier full event; the last state/updated/error wins.
  var record: DeliveryRecord
  if event.id in records:
    record = records[event.id]
  else:
    record = DeliveryRecord(id: event.id)
    order.add(event.id)
  if event.userId.isSome:
    record.userId = event.userId.get
  if event.channel.isSome:
    record.channel = event.channel.get
  if event.channelId.isSome:
    record.channelId = event.channelId.get
  if event.textHash.isSome:
    record.textHash = event.textHash.get
  if event.state.isSome:
    record.state = event.state.get
  if event.attempts.isSome:
    record.attempts = event.attempts.get
  if event.createdAtMs.isSome:
    record.createdAtMs = event.createdAtMs.get
  if event.updatedAtMs.isSome:
    record.updatedAtMs = event.updatedAtMs.get
  if event.error.isSome:
    record.error = event.error.get
  records[event.id] = record

proc loadLedger(store: RuntimeStateStore): Result[seq[DeliveryRecord], string] {.raises: [].} =
  let path = store.ledgerPath()
  if not fileExists(path):
    return ok(newSeq[DeliveryRecord]())
  try:
    var byId = initTable[string, DeliveryRecord]()
    var order: seq[string] = @[]
    for line in lines(path):
      let trimmed = line.strip
      if trimmed.len == 0:
        continue
      try:
        let parsed = parseJson(trimmed)
        let event = ledgerEventFromJson(parsed)
        if event.isSome:
          mergeEvent(byId, order, event.get)
      except CatchableError:
        ## A torn trailing line is ignored; earlier events remain valid.
        continue
    var records: seq[DeliveryRecord] = @[]
    for id in order:
      records.add(byId[id])
    ok(records)
  except CatchableError as e:
    err("delivery ledger read failed: " & e.msg)

proc appendLedger(store: RuntimeStateStore;
                  record: DeliveryRecord): Result[void, string] =
  appendJsonLine(store.ledgerPath(), deliveryToJson(record))

proc appendMinimalEvent(store: RuntimeStateStore;
                        id: string;
                        state: DeliveryState;
                        updatedAtMs: int64;
                        error: string): Result[void, string] =
  appendJsonLine(store.ledgerPath(), %* {
    "id": id,
    "state": $state,
    "updated_at_ms": updatedAtMs,
    "error": error,
  })

proc recordPending(store: RuntimeStateStore;
                   record: DeliveryRecord): Result[void, string] {.raises: [].} =
  store.pending[record.id] = record
  store.appendLedger(record)

proc markSent(store: RuntimeStateStore;
              id: string;
              updatedAtMs: int64): Result[void, string] {.raises: [].} =
  if id in store.pending:
    var record = store.pending.getOrDefault(id)
    store.pending.del(id)
    record.state = dlsSent
    record.updatedAtMs = updatedAtMs
    record.error = ""
    store.appendLedger(record)
  else:
    ## Restart or failed pending write: emit a minimal event. Replay merges it
    ## with any earlier full event.
    store.appendMinimalEvent(id, dlsSent, updatedAtMs, "")

proc markFailed(store: RuntimeStateStore;
                id: string;
                updatedAtMs: int64;
                error: string): Result[void, string] {.raises: [].} =
  if id in store.pending:
    var record = store.pending.getOrDefault(id)
    store.pending.del(id)
    record.state = dlsFailed
    record.updatedAtMs = updatedAtMs
    record.error = error
    store.appendLedger(record)
  else:
    store.appendMinimalEvent(id, dlsFailed, updatedAtMs, error)

proc newRuntimeStateStore*(stateDir: string): RuntimeStateStore =
  result = RuntimeStateStore(
    stateDir: stateDir,
    pending: initTable[string, DeliveryRecord](),
  )
  ## Load the ledger once: the hot path only touches the pending table.
  try:
    let loaded = result.loadLedger()
    if loaded.isOk:
      for record in loaded.value:
        if record.state == dlsPending:
          result.pending[record.id] = record
  except CatchableError:
    ## A broken ledger must not prevent the daemon from starting.
    discard

proc sessionRegistry*(store: RuntimeStateStore): SessionRegistryPort =
  SessionRegistryPort(
    loadAll: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe, raises: [].} =
      store.loadSessions(),
    upsert: proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe, raises: [].} =
      store.upsertSession(record),
  )

proc deliveryLedger*(store: RuntimeStateStore): DeliveryLedgerPort =
  DeliveryLedgerPort(
    recordPending: proc(record: DeliveryRecord): Result[void, string] {.gcsafe, raises: [].} =
      store.recordPending(record),
    markSent: proc(id: string; updatedAtMs: int64): Result[void, string] {.gcsafe, raises: [].} =
      store.markSent(id, updatedAtMs),
    markFailed: proc(id: string; updatedAtMs: int64; error: string): Result[void, string] {.gcsafe, raises: [].} =
      store.markFailed(id, updatedAtMs, error),
    loadAll: proc(): Result[seq[DeliveryRecord], string] {.gcsafe, raises: [].} =
      store.loadLedger(),
  )
