## schedule_store — durable schedule store (US-003 slice).
##
## One JSON document per state dir, `state/schedules.json`, holding one record
## per schedule id. A record is the persisted schedule spec plus the runtime
## watermark:
##
##   {"v": 2, "schedules": [
##     {"id": "<id>", "cron_expr": "*/5 * * * *", "tz_offset_minutes": 0,
##      "user_id": "<user>", "channel": "telegram", "payload": "<text>",
##      "catch_up": "once", "enabled": true,
##      "created_at_ms": 0, "last_run_at_ms": 0, "last_fire_at_ms": 0}
##   ]}
##
## `ScheduleRecord` holds the domain `ScheduleSpec` verbatim (adapters may
## depend on domain; the reverse is forbidden), so a daemon tick can pass
## `record.spec` straight into `tickSchedule`. The store adds `lastRunAtMs`
## and `lastFireAtMs`; the creation instant lives in `spec.createdAtMs`.
##
## The adapter owns every file operation; `tickSchedule` only sees the
## `ScheduleStorePort` callbacks. A record is keyed by its `id`, so saving the
## same id again replaces the row instead of appending a duplicate.
##
## Durability points:
##   - every save rewrites the document through a sibling temp file, fsyncs
##     the temp file, renames it over the document and fsyncs the directory;
##   - a failed read (corrupt or unreadable document) fails the save closed:
##     the current bytes stay untouched for recovery.
##
## Permissions: state dir 0700, document 0600.
##
## Merge rules for `upsert` (the ctl path):
##   - `spec.createdAtMs` is write-once: the first non-zero value sticks and a
##     later upsert can never rewind it;
##   - `lastRunAtMs`/`lastFireAtMs` are only replaced by a non-zero value, so a
##     spec edit that leaves them at their zero default cannot reset the
##     scheduler watermark;
##   - every other spec field is replaced by the incoming record.
##
## Two ctl operations are single-store transactions instead of
## load-then-upsert, so a concurrent process cannot interleave between the
## check and the write:
##   - `insertIfAbsent`: refuses (returns `false`) an id that already exists;
##     used by `ctl schedule add`;
##   - `setEnabled`: flips `spec.enabled` and, on a disabled → enabled
##     transition, moves `lastRunAtMs` to `now` so a re-enabled schedule does
##     not catch up on the period the daemon was stopped. `lastFireAtMs` is
##     left untouched.
##
## `save` (the `ScheduleStorePort` path used by `tickSchedule`) reads/writes
## only the watermark: the stored spec is preserved, `createdAtMs` follows the
## same write-once rule, and `lastRunAtMs` is authoritative (a tick may
## legitimately persist zero at the epoch).
##
## Schema versions:
##   - v2 (current): spec + watermark per row.
##   - v1: watermark only. Accepted on load, never silently dropped: the row
##     keeps `id`, `last_run_at_ms` and `created_at_ms`, every spec field is
##     empty (`enabled = false`, `catch_up = scSkip`) and `loadWarning` explains
##     the upgrade. Loading does not rewrite the file; the next successful
##     `save`/`upsert`/`remove` writes v2 and preserves the watermark.
##
## Forward compatibility: unknown fields (top-level or per record) are
## ignored on load; a record without a non-empty `id` is skipped rather than
## treated as corruption. Skipped records are not rewritten by the next save.
##
## Concurrency: a module-level lock serializes every read-modify-write for all
## store instances in this process, so concurrent saves of different ids do
## not lose each other's rows.

import std/[json, locks, options, os, posix, strutils, tables]
when defined(posix):
  import std/posix
import results
import ../../app/automation_runtime
import ../../domain/automation/schedule_pure

const
  ScheduleFileName* = "schedules.json"
  ScheduleStoreVersion* = 2
  ScheduleStoreVersionV1* = 1

type
  ScheduleRecord* = object
    ## Persisted schedule row: the domain spec plus the runtime watermark.
    ##
    ## `loadWarning` is transient and never written to disk; it flags a row
    ## that was upgraded from an older schema (v1 watermarks-only) so the ctl
    ## can announce it instead of treating empty spec fields as real data.
    spec*: ScheduleSpec
    lastRunAtMs*: int64
    lastFireAtMs*: int64
    loadWarning*: string

  ScheduleStore* = ref object
    stateDir*: string
    path*: string

# A single lock for every store instance in this process: the file is the
# unit of serialization, not the store object.
var scheduleStoreLock: Lock
initLock(scheduleStoreLock)

# ---------------------------------------------------------------------------
# Small durable-file helpers. `turn_journal_store` keeps the same building
# blocks private; extracting them into a shared module needs a file this story
# does not own, so the minimal copies live here.
# ---------------------------------------------------------------------------

when defined(posix):
  proc cRename(oldname, newname: cstring): cint {.
    importc: "rename", header: "<stdio.h>".}

when defined(macosx):
  ## `fsync` on macOS only reaches the drive cache; `F_FULLFSYNC` flushes it.
  var F_FULLFSYNC {.importc, header: "<fcntl.h>".}: cint

proc hardenDir(dir: string): Result[void, string] {.raises: [].} =
  when defined(posix):
    if dir.len > 0 and posix.chmod(dir.cstring, posix.Mode(0o700)) != 0:
      return err("cannot restrict permissions of " & dir)
  ok()

proc hardenFile(path: string): Result[void, string] {.raises: [].} =
  when defined(posix):
    if posix.chmod(path.cstring, posix.Mode(0o600)) != 0:
      return err("cannot restrict permissions of " & path)
  ok()

proc lockFile(store: ScheduleStore): cint {.raises: [].} =
  ## Cross-process exclusion for the read-modify-write window: `ctl` and the
  ## daemon are different processes, and the in-process `Lock` cannot see each
  ## other. A dedicated `.lock` file keeps the JSON file itself untouched.
  when defined(posix):
    result = posix.open((store.path & ".lock").cstring,
                        O_CREAT or O_RDWR, 0o600)
    if result >= 0:
      if posix.lockf(result, F_LOCK, 0) != 0:
        discard posix.close(result)
        result = -1
  else:
    result = -1

proc unlockFile(fd: cint) {.raises: [].} =
  when defined(posix):
    if fd >= 0:
      discard posix.lockf(fd, F_ULOCK, 0)
      discard posix.close(fd)

proc syncFile(f: File; path: string): Result[void, string] {.raises: [].} =
  try:
    f.flushFile()
  except CatchableError as e:
    return err("flush failed for " & path & ": " & e.msg)
  when defined(posix):
    let fd = cint(f.getFileHandle())
    when defined(macosx):
      if posix.fcntl(fd, F_FULLFSYNC) == 0:
        return ok()
    if posix.fsync(fd) != 0:
      return err("fsync failed for " & path & ": " & osErrorMsg(osLastError()))
  ok()

proc syncDir(path: string): Result[void, string] {.raises: [].} =
  ## Persist a directory entry (new file, rename). Needed for durability of the
  ## name, not of the already-fsynced data.
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

proc removeQuietly(path: string) {.raises: [].} =
  try:
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc renamePath(source, dest: string): Result[void, string] {.raises: [].} =
  when defined(posix):
    if cRename(source.cstring, dest.cstring) != 0:
      return err("rename failed for " & source & ": " &
                 osErrorMsg(osLastError()))
    ok()
  else:
    try:
      {.cast(raises: []).}:
        moveFile(source, dest)
      ok()
    except CatchableError as e:
      err("rename failed for " & source & ": " & e.msg)

proc ensureStateDir(path: string): Result[void, string] {.raises: [].} =
  let dir = parentDir(path)
  if dir.len == 0:
    return ok()
  try:
    createDir(dir)
  except CatchableError as e:
    return err("cannot create schedule state directory " & dir & ": " & e.msg)
  hardenDir(dir)

var tmpSerial: int

proc atomicWriteText(path, content: string): Result[void, string] {.raises: [].} =
  ## Temp file + fsync + rename + directory fsync. Caller holds the store lock,
  ## so `tmpSerial` needs no further synchronization.
  inc tmpSerial
  let tmp = path & ".tmp." & $getCurrentProcessId() & "-" & $tmpSerial
  try:
    let prepared = ensureStateDir(path)
    if prepared.isErr:
      return err(prepared.error)
    var f = open(tmp, fmWrite)
    let hardened = hardenFile(tmp)
    if hardened.isErr:
      f.close()
      removeQuietly(tmp)
      return err(hardened.error)
    var syncError = ""
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
    let dir = parentDir(path)
    if dir.len > 0:
      ## The rename already made the new content visible. A directory fsync is
      ## a durability nicety; reporting it as a failed write would make the
      ## caller believe the watermark did not advance and skip an occurrence
      ## that is, in fact, consumed.
      discard syncDir(dir)
    ok()
  except CatchableError as e:
    removeQuietly(tmp)
    err("atomic write failed for " & path & ": " & e.msg)

# ---------------------------------------------------------------------------
# JSON encoding/decoding.
# ---------------------------------------------------------------------------

proc jsonStr(node: JsonNode; key: string): string =
  let value = node{key}
  if value == nil or value.kind != JString:
    return ""
  value.getStr

proc jsonInt(node: JsonNode; key: string): int64 =
  ## Only integer nodes are accepted: a future writer may have changed the
  ## type, and a wrong type is treated as a missing value, not a hard error.
  let value = node{key}
  if value == nil or value.kind != JInt:
    return 0
  value.getInt.int64

proc jsonBool(node: JsonNode; key: string; fallback = false): bool =
  ## Only boolean nodes are accepted, mirroring `jsonInt`'s leniency.
  let value = node{key}
  if value == nil or value.kind != JBool:
    return fallback
  value.getBool

proc parseCatchUp(node: JsonNode): ScheduleCatchUp =
  ## Unknown or missing values degrade to `scSkip`. Both the wire spelling
  ## ("once"/"skip") and the enum name ("scOnce"/"scSkip") are accepted, so a
  ## hand-edited or older document still loads.
  case jsonStr(node, "catch_up").strip().toLowerAscii()
  of "once", "sconce":
    scOnce
  else:
    scSkip

proc catchUpName(catchUp: ScheduleCatchUp): string =
  case catchUp
  of scSkip: "skip"
  of scOnce: "once"

proc documentVersion(doc: JsonNode): int =
  ## A missing/non-integer `v` is read as the original v1 shape: the row is
  ## then flagged by `parseRecord`, which is stricter than silently assuming
  ## the current schema.
  let value = doc{"v"}
  if value == nil or value.kind != JInt:
    return ScheduleStoreVersionV1
  value.getInt

proc parseRecord(node: JsonNode; version: int): Option[ScheduleRecord] =
  if node == nil or node.kind != JObject:
    return none(ScheduleRecord)
  let id = jsonStr(node, "id")
  if id.len == 0:
    return none(ScheduleRecord)

  var record = ScheduleRecord(
    spec: ScheduleSpec(
      id: id,
      cronExpr: jsonStr(node, "cron_expr"),
      tzOffsetMinutes: int(jsonInt(node, "tz_offset_minutes")),
      userId: jsonStr(node, "user_id"),
      channel: jsonStr(node, "channel"),
      payload: jsonStr(node, "payload"),
      catchUp: parseCatchUp(node),
      enabled: jsonBool(node, "enabled"),
      createdAtMs: jsonInt(node, "created_at_ms"),
    ),
    lastRunAtMs: jsonInt(node, "last_run_at_ms"),
    lastFireAtMs: jsonInt(node, "last_fire_at_ms"),
  )

  if version < ScheduleStoreVersion:
    record.loadWarning = "schedules.json v" & $version & " row '" & id &
      "': no spec fields, watermark preserved (next write upgrades to v" &
      $ScheduleStoreVersion & ")"

  some(record)

proc readRecordsLocked(path: string
                      ): Result[OrderedTable[string, ScheduleRecord],
                                string] {.raises: [].} =
  var records = initOrderedTable[string, ScheduleRecord]()
  if not fileExists(path):
    return ok(records)

  var raw = ""
  try:
    raw = readFile(path)
  except CatchableError as e:
    return err("cannot read schedule store " & path & ": " & e.msg)

  if raw.strip().len == 0:
    return ok(records)

  var doc: JsonNode
  try:
    doc = parseJson(raw)
  except CatchableError as e:
    return err("cannot parse schedule store " & path & ": " & e.msg)

  if doc.kind != JObject:
    return err("cannot parse schedule store " & path &
               ": top-level value is not an object")

  let list = doc{"schedules"}
  if list == nil:
    ## An empty object is a fresh/legacy store; a document with fields but no
    ## `schedules` array is a shape we do not understand, and treating it as
    ## empty would let the next save wipe every other schedule.
    if doc.len == 0:
      return ok(records)
    return err("cannot parse schedule store " & path &
               ": missing \"schedules\" array")
  if list.kind != JArray:
    return err("cannot parse schedule store " & path &
               ": \"schedules\" is not an array")

  let version = documentVersion(doc)
  for item in list:
    let parsed = parseRecord(item, version)
    if parsed.isNone:
      continue
    let record = parsed.get()
    records[record.spec.id] = record
  ok(records)

proc recordsToJson(records: OrderedTable[string, ScheduleRecord]): JsonNode =
  result = newJObject()
  result["v"] = %ScheduleStoreVersion
  var list = newJArray()
  for record in records.values:
    var node = newJObject()
    node["id"] = %record.spec.id
    node["cron_expr"] = %record.spec.cronExpr
    node["tz_offset_minutes"] = %record.spec.tzOffsetMinutes
    node["user_id"] = %record.spec.userId
    node["channel"] = %record.spec.channel
    node["payload"] = %record.spec.payload
    node["catch_up"] = %catchUpName(record.spec.catchUp)
    node["enabled"] = %record.spec.enabled
    node["created_at_ms"] = %record.spec.createdAtMs
    node["last_run_at_ms"] = %record.lastRunAtMs
    node["last_fire_at_ms"] = %record.lastFireAtMs
    list.add(node)
  result["schedules"] = list

proc mergeUpsert(existing: ScheduleRecord; incoming: ScheduleRecord
                ): ScheduleRecord =
  ## See the module header for the merge contract.
  result = incoming
  result.loadWarning = ""
  if existing.spec.createdAtMs != 0:
    result.spec.createdAtMs = existing.spec.createdAtMs
  if result.lastRunAtMs == 0:
    result.lastRunAtMs = existing.lastRunAtMs
  if result.lastFireAtMs == 0:
    result.lastFireAtMs = existing.lastFireAtMs

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------

proc newScheduleStoreRef*(stateDir: string): ScheduleStore =
  ## Concrete store handle. The daemon uses `newScheduleStore` (the port);
  ## the ctl and the tick loop use this one for the record API.
  ScheduleStore(stateDir: stateDir, path: stateDir / ScheduleFileName)

func toWatermark*(record: ScheduleRecord): ScheduleWatermark =
  ## Projection used by `ScheduleStorePort`: the runtime sees the watermark
  ## and the last fire instant.
  ScheduleWatermark(
    id: record.spec.id,
    lastRunAtMs: record.lastRunAtMs,
    createdAtMs: record.spec.createdAtMs,
    lastFireAtMs: record.lastFireAtMs,
  )

proc loadRecord*(store: ScheduleStore; scheduleId: string
                ): Result[Option[ScheduleRecord], string] {.
    gcsafe, raises: [].} =
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  if scheduleId in records.get():
    ok(some(records.get().getOrDefault(scheduleId)))
  else:
    ok(none(ScheduleRecord))

proc loadAllRecords*(store: ScheduleStore
                    ): Result[seq[ScheduleRecord], string] {.
    gcsafe, raises: [].} =
  ## Every stored record in file order (the same order rows are rewritten).
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  var loaded: seq[ScheduleRecord]
  for record in records.get().values:
    loaded.add(record)
  ok(loaded)

proc upsert*(store: ScheduleStore; record: ScheduleRecord
            ): Result[void, string] {.gcsafe, raises: [].} =
  ## Insert or replace the row keyed by `record.spec.id`. Creation time is
  ## write-once and zero watermark fields keep the stored values; a corrupt
  ## document is an error and is left untouched.
  let id = record.spec.id.strip()
  if id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  var toStore = record
  toStore.spec.id = id
  if id in records:
    toStore = mergeUpsert(records.getOrDefault(id), toStore)
  else:
    toStore.loadWarning = ""
  records[id] = toStore
  atomicWriteText(store.path, $recordsToJson(records))

proc insertIfAbsent*(store: ScheduleStore; record: ScheduleRecord
                    ): Result[bool, string] {.gcsafe, raises: [].} =
  ## Create-only write: the duplicate check and the insert happen under the
  ## same in-process lock and file lock, so two concurrent adds cannot both
  ## see a free id. Returns `true` when the row was written and `false` when
  ## the id already exists (the stored row is left byte-for-byte untouched).
  ## A corrupt document is an error and is left untouched.
  let id = record.spec.id.strip()
  if id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  if id in records:
    return ok(false)
  var toStore = record
  toStore.spec.id = id
  toStore.loadWarning = ""
  records[id] = toStore
  let written = atomicWriteText(store.path, $recordsToJson(records))
  if written.isErr:
    return err(written.error)
  ok(true)

proc setEnabled*(store: ScheduleStore; scheduleId: string; enabled: bool;
                 nowMs: int64): Result[bool, string] {.gcsafe, raises: [].} =
  ## Single-transaction enable/disable. Flipping `spec.enabled` and moving the
  ## watermark cannot be split by a concurrent tick or ctl write.
  ##
  ## A disabled → enabled transition sets `lastRunAtMs = max(lastRun, now)`:
  ## a daemon that was stopped for the whole disabled period has no watermark
  ## from that window, so without this the first tick would catch up on it.
  ## The watermark never moves backwards (clock rollback keeps the old value).
  ## `lastFireAtMs` records the last real firing and is never touched here.
  ## Returns `false` when the id is absent.
  let id = scheduleId.strip()
  if id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  if id notin records:
    return ok(false)
  var record = records.getOrDefault(id)
  let reenabling = enabled and not record.spec.enabled
  record.spec.enabled = enabled
  if reenabling:
    record.lastRunAtMs = max(record.lastRunAtMs, nowMs)
  record.loadWarning = ""
  records[id] = record
  let written = atomicWriteText(store.path, $recordsToJson(records))
  if written.isErr:
    return err(written.error)
  ok(true)

proc remove*(store: ScheduleStore; scheduleId: string
            ): Result[void, string] {.gcsafe, raises: [].} =
  ## Remove the row and atomically rewrite the document. Removing an absent id
  ## is a no-op (no rewrite), so retries are safe. A corrupt document is an
  ## error and is left untouched.
  let id = scheduleId.strip()
  if id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  if id notin records:
    return ok()
  records.del(id)
  atomicWriteText(store.path, $recordsToJson(records))

proc load*(store: ScheduleStore; scheduleId: string
          ): Result[Option[ScheduleWatermark], string] {.gcsafe, raises: [].} =
  ## Port-facing read: watermark only.
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  if scheduleId in records.get():
    ok(some(toWatermark(records.get().getOrDefault(scheduleId))))
  else:
    ok(none(ScheduleWatermark))

proc loadAll*(store: ScheduleStore
             ): Result[seq[ScheduleWatermark], string] {.gcsafe, raises: [].} =
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  var states: seq[ScheduleWatermark]
  for record in records.get().values:
    states.add(toWatermark(record))
  ok(states)

proc save*(store: ScheduleStore; state: ScheduleWatermark
          ): Result[void, string] {.gcsafe, raises: [].} =
  ## Port-facing write of the watermark. The stored spec is preserved, so a
  ## `tickSchedule` save never erases the schedule definition. A corrupt
  ## document is an error: replacing it would destroy recoverable rows.
  if state.id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let fileLock = lockFile(store)
  defer: unlockFile(fileLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  var record =
    if state.id in records: records.getOrDefault(state.id)
    else: ScheduleRecord(spec: ScheduleSpec(id: state.id))
  record.spec.id = state.id
  record.lastRunAtMs = state.lastRunAtMs
  if state.lastFireAtMs > 0:
    record.lastFireAtMs = state.lastFireAtMs
  if record.spec.createdAtMs == 0:
    record.spec.createdAtMs = state.createdAtMs
  record.loadWarning = ""
  records[state.id] = record
  atomicWriteText(store.path, $recordsToJson(records))

proc scheduleStorePort*(store: ScheduleStore): ScheduleStorePort =
  ## Adapter-to-port binding, mirroring `turn_journal_store`'s port accessor.
  ScheduleStorePort(
    load: proc(scheduleId: string
              ): Result[Option[ScheduleWatermark], string] {.gcsafe, raises: [].} =
      store.load(scheduleId),
    save: proc(state: ScheduleWatermark
              ): Result[void, string] {.gcsafe, raises: [].} =
      store.save(state),
  )

proc newScheduleStore*(stateDir: string): ScheduleStorePort =
  ## Daemon-facing constructor: a store bound to `{stateDir}/schedules.json`.
  scheduleStorePort(newScheduleStoreRef(stateDir))
