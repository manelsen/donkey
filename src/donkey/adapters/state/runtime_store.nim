## runtime_store — atomic file-backed session registry and delivery ledger.
##
## Layout under `$DONKEY_HOME/state/`:
##   sessions.json         full registry, replaced atomically (write tmp + fsync + rename)
##   delivery_ledger.jsonl append-only, newline-framed event log
##
## Both stores are deliberately small and simple: the daemon is the only writer
## and owns at most a few sessions. I/O failures are returned as `Err`; callers
## on the hot path log and continue.

import std/[atomics, json, locks, options, os, strutils, tables]
when defined(posix):
  import std/posix
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../ports/runtime_state

const
  SessionsFileName*     = "sessions.json"
  DeliveryLedgerFileName* = "delivery_ledger.jsonl"
  RegistryVersion*      = 1
  SessionsFlushIntervalMs = 1000
    ## Timestamp-only updates are coalesced to at most one write per second.
    ## Structural changes (channels, session id, runtime signature) flush
    ## immediately. `flushSessions` forces a pending write.
  LedgerRetentionDaysDefault*      = 30.0
  LedgerCompactIntervalSecDefault* = 3600.0

type
  RuntimeStateStore* = ref object
    stateDir*: string
    ## Records still awaiting `sent`/`failed`. Loaded once at construction so
    ## the hot path does not replay the ledger file on every update.
    pending*: Table[string, DeliveryRecord]
    ## Session registry cache. Loaded once and kept in memory so an upsert
    ## never has to read/parse the whole file. Guarded by `lock`.
    sessions: seq[SessionRegistryRecord]
    sessionsLoaded: bool
    sessionsDirty: bool
    lastSessionsWriteMs: int64
    ledgerDirSynced: bool
    ledgerRetentionMs: int64
    ledgerCompactIntervalMs: int64
    lastLedgerCompactMs: int64
    lastLedgerCompactError: string
    compactStarts: Atomic[int]
    ## Serializes session upserts, ledger appends and their in-memory caches.
    ## Gateway workers can persist concurrently with the event loop.
    lock: Lock
    tmpCounter: int

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

proc atomicWriteText(path, content, tmpSuffix: string): Result[void, string] =
  ## Writes to a sibling temp file unique to this write, fsyncs it, renames it
  ## over the destination and fsyncs the parent directory.
  let tmp = path & ".tmp." & tmpSuffix
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

proc appendJsonLine(path: string; node: JsonNode;
                    durable: bool; syncParent: bool): Result[void, string] =
  ## Appends one newline-framed record. `durable` controls the file fsync;
  ## pending events are best-effort, terminal sent/failed events are synced.
  ## Framing both sides means a torn write can never merge with the next event.
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
    let isNew = not fileExists(path)
    var f = open(path, fmAppend)
    try:
      f.write("\n" & $node & "\n")
      if durable:
        let synced = syncFile(f, path)
        if synced.isErr:
          return err(synced.error)
      else:
        f.flushFile()
    finally:
      f.close()
    if syncParent and dir.len > 0:
      ## The file's directory entry only exists after the first append; sync
      ## the parent so a power loss cannot lose the whole ledger.
      let dirSynced = syncDir(dir)
      if dirSynced.isErr:
        return err(dirSynced.error)
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

proc loadSessionsFromDisk(store: RuntimeStateStore): Result[seq[SessionRegistryRecord], string] {.raises: [].} =
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

proc ensureSessionsLoadedLocked(store: RuntimeStateStore): Result[void, string] {.raises: [].} =
  ## Caller must hold `store.lock`.
  if store.sessionsLoaded:
    return ok()
  let loaded = store.loadSessionsFromDisk()
  if loaded.isErr:
    return err(loaded.error)
  store.sessions = loaded.value
  store.sessionsLoaded = true
  ok()

proc loadSessions(store: RuntimeStateStore): Result[seq[SessionRegistryRecord], string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  let loaded = store.ensureSessionsLoadedLocked()
  if loaded.isErr:
    return err(loaded.error)
  ## Return a shallow copy: the caller may iterate while another thread
  ## upserts a different user.
  var records = newSeq[SessionRegistryRecord](store.sessions.len)
  for i, record in store.sessions:
    records[i] = record
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
  inc store.tmpCounter
  atomicWriteText(store.sessionsPath(), $payload,
                  $getCurrentProcessId() & "-" & $store.tmpCounter)

func sameStructuralFields(a, b: SessionRegistryRecord): bool =
  a.channels == b.channels and
    a.sessionId == b.sessionId and
    a.runtimeSignature == b.runtimeSignature

proc flushSessionsLocked(store: RuntimeStateStore;
                         force: bool): Result[void, string] {.raises: [].} =
  ## Caller must hold `store.lock`.
  if not store.sessionsDirty and not force:
    return ok()
  let now = epochMs()
  if not force and now - store.lastSessionsWriteMs < SessionsFlushIntervalMs:
    return ok()
  let saved = store.saveSessions(store.sessions)
  if saved.isOk:
    store.lastSessionsWriteMs = now
    store.sessionsDirty = false
  saved

proc flushSessions*(store: RuntimeStateStore): Result[void, string] {.raises: [].} =
  ## Forces a pending session-registry write. Called on shutdown/tests.
  acquire(store.lock)
  defer: release(store.lock)
  store.flushSessionsLocked(force = true)

proc upsertSession(store: RuntimeStateStore;
                   record: SessionRegistryRecord): Result[void, string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  let loaded = store.ensureSessionsLoadedLocked()
  if loaded.isErr:
    return err(loaded.error)
  var replaced = false
  var structural = true
  for i in 0 ..< store.sessions.len:
    if store.sessions[i].userId == record.userId:
      structural = not sameStructuralFields(store.sessions[i], record)
      store.sessions[i] = record
      replaced = true
      break
  if not replaced:
    store.sessions.add(record)
  store.sessionsDirty = true
  store.flushSessionsLocked(force = structural)

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

proc loadLedgerFromDisk(store: RuntimeStateStore): Result[seq[DeliveryRecord], string] {.raises: [].} =
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

proc loadLedger(store: RuntimeStateStore): Result[seq[DeliveryRecord], string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  store.loadLedgerFromDisk()

const LedgerEventFields = [
  "id", "user_id", "channel", "channel_id", "text_hash", "state",
  "attempts", "created_at_ms", "updated_at_ms", "error",
]

func isKnownLedgerEvent(node: JsonNode): bool =
  ## Rejects unknown fields as well as unknown channels/states: a future event
  ## that adds a field must survive a rollback, so compaction skips it.
  if node.kind != JObject:
    return false
  for key, _ in node:
    if key notin LedgerEventFields:
      return false
  ledgerEventFromJson(node).isSome

proc hasForwardIncompatibleEvents(path: string): Result[bool, string] {.raises: [].} =
  ## A valid JSON object that replay cannot interpret, or that carries fields
  ## this version does not know, is treated as a future event; compaction must
  ## not drop it. Torn/invalid JSON lines are ignored because replay also
  ## ignores them.
  try:
    for line in lines(path):
      let trimmed = line.strip
      if trimmed.len == 0:
        continue
      try:
        let parsed = parseJson(trimmed)
        if parsed.kind == JObject and not isKnownLedgerEvent(parsed):
          return ok(true)
      except CatchableError:
        continue
  except CatchableError as e:
    return err("ledger scan failed: " & e.msg)
  ok(false)

proc compactLedgerLocked(store: RuntimeStateStore;
                         force: bool;
                         nowMs: int64): Result[void, string] {.raises: [].} =
  ## Caller must hold `store.lock`. Rewrites the ledger atomically with one
  ## record per id, keeping every pending record and terminal records newer
  ## than the retention window.
  let path = store.ledgerPath()
  if not fileExists(path):
    store.lastLedgerCompactMs = nowMs
    store.lastLedgerCompactError = ""
    return ok()
  if not force and store.ledgerCompactIntervalMs > 0 and
     nowMs - store.lastLedgerCompactMs < store.ledgerCompactIntervalMs:
    return ok()

  discard store.compactStarts.fetchAdd(1)
  let scan = hasForwardIncompatibleEvents(path)
  if scan.isErr:
    store.lastLedgerCompactMs = nowMs
    store.lastLedgerCompactError = scan.error
    return err(scan.error)
  if scan.get():
    store.lastLedgerCompactMs = nowMs
    store.lastLedgerCompactError =
      "ledger contains unrecognized events; compaction skipped"
    return err(store.lastLedgerCompactError)

  let loaded = store.loadLedgerFromDisk()
  if loaded.isErr:
    store.lastLedgerCompactMs = nowMs
    store.lastLedgerCompactError = loaded.error
    return err(loaded.error)

  var byId = initTable[string, DeliveryRecord]()
  var order: seq[string] = @[]
  for record in loaded.get():
    if record.id notin byId:
      order.add(record.id)
    byId[record.id] = record

  ## Reconcile the in-memory pending table with disk. A missing disk entry is
  ## added; a disk `pending` may be replaced by newer memory metadata; a disk
  ## terminal state is never overwritten by a stale pending entry.
  for id, record in store.pending:
    if id notin byId:
      order.add(id)
      byId[id] = record
    elif byId.getOrDefault(id).state == dlsPending:
      byId[id] = record

  let cutoff = nowMs - store.ledgerRetentionMs
  var kept: seq[DeliveryRecord] = @[]
  for id in order:
    let record = byId.getOrDefault(id)
    if record.state == dlsPending:
      kept.add(record)
      continue
    let timestamp =
      if record.updatedAtMs > 0: record.updatedAtMs
      else: record.createdAtMs
    if timestamp <= 0 or timestamp >= cutoff:
      kept.add(record)

  var content = ""
  for record in kept:
    content.add("\n" & $deliveryToJson(record) & "\n")

  inc store.tmpCounter
  let saved = atomicWriteText(path, content,
                              $getCurrentProcessId() & "-" & $store.tmpCounter)
  store.lastLedgerCompactMs = nowMs
  if saved.isOk:
    store.ledgerDirSynced = true
    store.lastLedgerCompactError = ""
  else:
    store.lastLedgerCompactError = saved.error
  saved

proc compactLedger*(store: RuntimeStateStore; force = false;
                    nowMs = epochMs()): Result[void, string] {.raises: [].} =
  ## Compacts the append-only ledger, enforcing retention. `force` bypasses the
  ## interval throttle; `nowMs` is injectable for tests.
  acquire(store.lock)
  defer: release(store.lock)
  store.compactLedgerLocked(force, nowMs)

func ledgerCompactIntervalSec*(store: RuntimeStateStore): float =
  ## Interval used by the daemon to schedule periodic compaction.
  float(store.ledgerCompactIntervalMs) / 1000.0

proc ledgerLastCompactMs*(store: RuntimeStateStore): int64 =
  acquire(store.lock)
  defer: release(store.lock)
  store.lastLedgerCompactMs

proc ledgerCompactStarts*(store: RuntimeStateStore): int =
  ## Lock-free start signal: visible while compaction still holds the lock.
  store.compactStarts.load()

type
  LedgerCompactionWorker* = ref object
    store:      RuntimeStateStore
    intervalMs: int64
    logger:     Logger
    stop:       Atomic[bool]
    stopped:    bool
    thread:     Thread[LedgerCompactionWorker]

proc ledgerCompactionLoop(worker: LedgerCompactionWorker) {.thread.} =
  {.cast(gcsafe).}:
    while not worker.stop.load():
      ## Sleep in bounded slices so shutdown does not wait for the whole
      ## interval (default is one hour).
      var waited = 0'i64
      while waited < worker.intervalMs and not worker.stop.load():
        sleep(1000)
        waited += 1000
      if worker.stop.load():
        break
      let res = worker.store.compactLedger()
      if res.isErr and worker.logger.sink != nil:
        worker.logger.warn("ledger compaction: " & res.error)

proc startLedgerCompactionWorker*(store: RuntimeStateStore;
                                  intervalSec: float;
                                  logger: Logger): LedgerCompactionWorker =
  ## Starts a dedicated OS thread for ledger compaction. Returns nil when the
  ## interval is disabled or the thread cannot be created.
  if store == nil or intervalSec <= 0.0:
    return nil
  let intervalMs = max(1000'i64, int64(max(1.0, intervalSec) * 1000.0))
  result = LedgerCompactionWorker(
    store: store, intervalMs: intervalMs, logger: logger)
  result.stop.store(false)
  try:
    createThread(result.thread, ledgerCompactionLoop, result)
  except CatchableError as e:
    if logger.sink != nil:
      logger.warn("ledger compaction worker not started: " & e.msg)
    result = nil

proc stopLedgerCompactionWorker*(worker: LedgerCompactionWorker) =
  if worker == nil or worker.stopped:
    return
  worker.stopped = true
  worker.stop.store(true)
  {.cast(gcsafe).}:
    joinThread(worker.thread)

func ledgerLastCompactError*(store: RuntimeStateStore): string =
  ## Last compaction failure, for the daemon to log after startup.
  store.lastLedgerCompactError

proc appendLedger(store: RuntimeStateStore;
                  record: DeliveryRecord;
                  durable: bool): Result[void, string] =
  let syncParent = durable and not store.ledgerDirSynced
  let saved = appendJsonLine(store.ledgerPath(), deliveryToJson(record),
                             durable, syncParent)
  if saved.isOk and syncParent:
    store.ledgerDirSynced = true
  saved

proc appendMinimalEvent(store: RuntimeStateStore;
                        id: string;
                        state: DeliveryState;
                        updatedAtMs: int64;
                        error: string): Result[void, string] =
  let syncParent = not store.ledgerDirSynced
  let saved = appendJsonLine(store.ledgerPath(), %* {
    "id": id,
    "state": $state,
    "updated_at_ms": updatedAtMs,
    "error": error,
  }, durable = true, syncParent = syncParent)
  if saved.isOk and syncParent:
    store.ledgerDirSynced = true
  saved

proc recordPending(store: RuntimeStateStore;
                   record: DeliveryRecord): Result[void, string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  store.pending[record.id] = record
  ## Pending is best-effort: avoid a second synchronous fsync per delivery.
  store.appendLedger(record, durable = false)

proc markSent(store: RuntimeStateStore;
              id: string;
              updatedAtMs: int64): Result[void, string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  if id in store.pending:
    var record = store.pending.getOrDefault(id)
    record.state = dlsSent
    record.updatedAtMs = updatedAtMs
    record.error = ""
    let saved = store.appendLedger(record, durable = true)
    if saved.isOk:
      store.pending.del(id)
    saved
  else:
    ## Restart or failed pending write: emit a minimal event. Replay merges it
    ## with any earlier full event.
    store.appendMinimalEvent(id, dlsSent, updatedAtMs, "")

proc markFailed(store: RuntimeStateStore;
                id: string;
                updatedAtMs: int64;
                error: string): Result[void, string] {.raises: [].} =
  acquire(store.lock)
  defer: release(store.lock)
  if id in store.pending:
    var record = store.pending.getOrDefault(id)
    record.state = dlsFailed
    record.updatedAtMs = updatedAtMs
    record.error = error
    let saved = store.appendLedger(record, durable = true)
    if saved.isOk:
      store.pending.del(id)
    saved
  else:
    store.appendMinimalEvent(id, dlsFailed, updatedAtMs, error)

proc newRuntimeStateStore*(stateDir: string;
                           ledgerRetentionDays = LedgerRetentionDaysDefault;
                           ledgerCompactIntervalSec = LedgerCompactIntervalSecDefault
                          ): RuntimeStateStore =
  ## Sanitize the configurable windows before converting to integer
  ## milliseconds; NaN/Inf and out-of-range values fall back to the defaults.
  let retentionDays =
    if ledgerRetentionDays >= 0.0 and ledgerRetentionDays <= 3650.0:
      ledgerRetentionDays
    else:
      LedgerRetentionDaysDefault
  let compactSec =
    if ledgerCompactIntervalSec >= 0.0 and
       ledgerCompactIntervalSec <= 7.0 * 24.0 * 3600.0:
      ledgerCompactIntervalSec
    else:
      LedgerCompactIntervalSecDefault
  result = RuntimeStateStore(
    stateDir: stateDir,
    pending: initTable[string, DeliveryRecord](),
    sessionsLoaded: false,
    ledgerDirSynced: false,
    sessionsDirty: false,
    lastSessionsWriteMs: 0,
    ledgerRetentionMs: int64(retentionDays * 86_400_000.0),
    ledgerCompactIntervalMs: int64(compactSec * 1000.0),
    lastLedgerCompactMs: 0,
    lastLedgerCompactError: "",
    tmpCounter: 0,
  )
  initLock(result.lock)
  result.ledgerDirSynced = fileExists(result.ledgerPath())
  ## Load the ledger once: the hot path only touches the pending table.
  try:
    let loaded = result.loadLedgerFromDisk()
    if loaded.isOk:
      for record in loaded.value:
        if record.state == dlsPending:
          result.pending[record.id] = record
  except CatchableError:
    ## A broken ledger must not prevent the daemon from starting.
    discard
  ## Enforce retention at startup while the daemon is still single-threaded.
  discard result.compactLedger()

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
