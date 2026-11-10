## runtime_store — atomic file-backed session registry and delivery ledger.
##
## Layout under `$DONKEY_HOME/state/`:
##   sessions.json         full registry, replaced atomically (write tmp + rename)
##   delivery_ledger.jsonl append-only event log; replay keeps the last event per id
##
## Both stores are deliberately small and simple: the daemon is the only writer
## and owns at most a few sessions. I/O failures are returned as `Err`; callers
## on the hot path log and continue.

import std/[json, options, os, strutils, tables]
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

  StoreError = object of CatchableError

func sessionsPath(store: RuntimeStateStore): string =
  store.stateDir / SessionsFileName

func ledgerPath(store: RuntimeStateStore): string =
  store.stateDir / DeliveryLedgerFileName

proc atomicWriteText(path, content: string): Result[void, string] =
  ## Writes to a sibling temp file and renames it over the destination.
  let tmp = path & ".tmp"
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
    writeFile(tmp, content)
    moveFile(tmp, path)
    ok()
  except CatchableError as e:
    try:
      if fileExists(tmp):
        removeFile(tmp)
    except CatchableError:
      discard
    err("atomic write failed for " & path & ": " & e.msg)

proc appendJsonLine(path: string; node: JsonNode): Result[void, string] =
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
    var f = open(path, fmAppend)
    defer: f.close()
    f.writeLine($node)
    f.flushFile()
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

proc loadSessions(store: RuntimeStateStore): Result[seq[SessionRegistryRecord], string] =
  let path = store.sessionsPath()
  if not fileExists(path):
    return ok(newSeq[SessionRegistryRecord]())
  try:
    let parsed = parseFile(path)
    if parsed.kind != JObject:
      return err("session registry is not a JSON object")
    let version = jsonInt(parsed, "version", RegistryVersion)
    if version > RegistryVersion:
      return err("unsupported session registry version: " & $version)
    var records: seq[SessionRegistryRecord] = @[]
    let sessions = parsed{"sessions"}
    if sessions != nil and sessions.kind == JArray:
      for item in sessions:
        let parsedRecord = sessionFromJson(item)
        if parsedRecord.isSome:
          records.add(parsedRecord.get)
    ok(records)
  except CatchableError as e:
    err("session registry read failed: " & e.msg)

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
                   record: SessionRegistryRecord): Result[void, string] =
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

proc deliveryFromJson(node: JsonNode): Option[DeliveryRecord] =
  if node == nil or node.kind != JObject:
    return none(DeliveryRecord)
  let id = jsonStr(node, "id")
  if id.len == 0:
    return none(DeliveryRecord)
  var channel: ChannelKind = ckTelegram
  if not parseChannelKindName(jsonStr(node, "channel"), channel):
    return none(DeliveryRecord)
  var state = dlsPending
  case jsonStr(node, "state")
  of $dlsPending: state = dlsPending
  of $dlsSent:    state = dlsSent
  of $dlsFailed:  state = dlsFailed
  else:           return none(DeliveryRecord)
  some(DeliveryRecord(
    id: id,
    userId: jsonStr(node, "user_id"),
    channel: channel,
    channelId: jsonStr(node, "channel_id"),
    textHash: jsonStr(node, "text_hash"),
    state: state,
    attempts: jsonInt(node, "attempts", 0).int,
    createdAtMs: jsonInt(node, "created_at_ms"),
    updatedAtMs: jsonInt(node, "updated_at_ms"),
    error: jsonStr(node, "error"),
  ))

proc loadLedger(store: RuntimeStateStore): Result[seq[DeliveryRecord], string] =
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
        let record = deliveryFromJson(parsed)
        if record.isSome:
          let value = record.get
          if value.id notin byId:
            order.add(value.id)
          byId[value.id] = value
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

proc recordPending(store: RuntimeStateStore;
                   record: DeliveryRecord): Result[void, string] =
  store.appendLedger(record)

proc findRecord(store: RuntimeStateStore;
                id: string): Result[DeliveryRecord, string] =
  let loaded = store.loadLedger()
  if loaded.isErr:
    return err(loaded.error)
  for record in loaded.value:
    if record.id == id:
      return ok(record)
  err("delivery id not found: " & id)

proc markSent(store: RuntimeStateStore;
              id: string;
              updatedAtMs: int64): Result[void, string] =
  let found = store.findRecord(id)
  if found.isErr:
    return err(found.error)
  var record = found.value
  record.state = dlsSent
  record.updatedAtMs = updatedAtMs
  record.error = ""
  store.appendLedger(record)

proc markFailed(store: RuntimeStateStore;
                id: string;
                updatedAtMs: int64;
                error: string): Result[void, string] =
  let found = store.findRecord(id)
  if found.isErr:
    return err(found.error)
  var record = found.value
  record.state = dlsFailed
  record.updatedAtMs = updatedAtMs
  record.error = error
  store.appendLedger(record)

proc newRuntimeStateStore*(stateDir: string): RuntimeStateStore =
  RuntimeStateStore(stateDir: stateDir)

proc sessionRegistry*(store: RuntimeStateStore): SessionRegistryPort =
  SessionRegistryPort(
    loadAll: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe.} =
      store.loadSessions(),
    upsert: proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe.} =
      store.upsertSession(record),
  )

proc deliveryLedger*(store: RuntimeStateStore): DeliveryLedgerPort =
  DeliveryLedgerPort(
    recordPending: proc(record: DeliveryRecord): Result[void, string] {.gcsafe.} =
      store.recordPending(record),
    markSent: proc(id: string; updatedAtMs: int64): Result[void, string] {.gcsafe.} =
      store.markSent(id, updatedAtMs),
    markFailed: proc(id: string; updatedAtMs: int64; error: string): Result[void, string] {.gcsafe.} =
      store.markFailed(id, updatedAtMs, error),
    loadAll: proc(): Result[seq[DeliveryRecord], string] {.gcsafe.} =
      store.loadLedger(),
  )
