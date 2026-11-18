## schedule_store — durable schedule watermark store (US-003 slice).
##
## One JSON document per state dir, `state/schedules.json`, holding one record
## per schedule id:
##
##   {"v": 1, "schedules": [
##     {"id": "<schedule id>", "last_run_at_ms": 0, "created_at_ms": 0}
##   ]}
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
## Forward compatibility: unknown fields (top-level or per record) are
## ignored on load; a record without a non-empty `id` is skipped rather than
## treated as corruption. Skipped records are not rewritten by the next save.
##
## Concurrency: a module-level lock serializes every read-modify-write for all
## store instances in this process, so concurrent saves of different ids do
## not lose each other's rows.

import std/[json, locks, options, os, strutils, tables]
when defined(posix):
  import std/posix
import results
import ../../app/automation_runtime

const
  ScheduleFileName* = "schedules.json"
  ScheduleStoreVersion* = 1

type
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
      let synced = syncDir(dir)
      if synced.isErr:
        return err(synced.error)
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

proc parseRecord(node: JsonNode): Option[ScheduleWatermark] =
  if node == nil or node.kind != JObject:
    return none(ScheduleWatermark)
  let id = jsonStr(node, "id")
  if id.len == 0:
    return none(ScheduleWatermark)
  some(ScheduleWatermark(
    id: id,
    lastRunAtMs: jsonInt(node, "last_run_at_ms"),
    createdAtMs: jsonInt(node, "created_at_ms"),
  ))

proc readRecordsLocked(path: string
                      ): Result[OrderedTable[string, ScheduleWatermark],
                                string] {.raises: [].} =
  var records = initOrderedTable[string, ScheduleWatermark]()
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
    return ok(records)
  if list.kind != JArray:
    return err("cannot parse schedule store " & path &
               ": \"schedules\" is not an array")

  for item in list:
    let parsed = parseRecord(item)
    if parsed.isNone:
      continue
    let record = parsed.get()
    records[record.id] = record
  ok(records)

proc recordsToJson(records: OrderedTable[string, ScheduleWatermark]): JsonNode =
  result = newJObject()
  result["v"] = %ScheduleStoreVersion
  var list = newJArray()
  for record in records.values:
    var node = newJObject()
    node["id"] = %record.id
    node["last_run_at_ms"] = %record.lastRunAtMs
    node["created_at_ms"] = %record.createdAtMs
    list.add(node)
  result["schedules"] = list

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------

proc newScheduleStoreRef*(stateDir: string): ScheduleStore =
  ## Concrete store handle. The daemon uses `newScheduleStore` (the port);
  ## tests and the future tick loop use this one for `loadAll`.
  ScheduleStore(stateDir: stateDir, path: stateDir / ScheduleFileName)

proc load*(store: ScheduleStore; scheduleId: string
          ): Result[Option[ScheduleWatermark], string] {.gcsafe, raises: [].} =
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  if scheduleId in records.get():
    ok(some(records.get().getOrDefault(scheduleId)))
  else:
    ok(none(ScheduleWatermark))

proc loadAll*(store: ScheduleStore
             ): Result[seq[ScheduleWatermark], string] {.gcsafe, raises: [].} =
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let records = readRecordsLocked(store.path)
  if records.isErr:
    return err(records.error)
  var states: seq[ScheduleWatermark]
  for record in records.get().values:
    states.add(record)
  ok(states)

proc save*(store: ScheduleStore; state: ScheduleWatermark
          ): Result[void, string] {.gcsafe, raises: [].} =
  ## Upsert by id, then atomically rewrite the whole document. A corrupt
  ## document is an error: replacing it would destroy recoverable rows.
  if state.id.len == 0:
    return err("schedule store: empty schedule id")
  acquire(scheduleStoreLock)
  defer: release(scheduleStoreLock)
  let current = readRecordsLocked(store.path)
  if current.isErr:
    return err(current.error)
  var records = current.get()
  records[state.id] = state
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
