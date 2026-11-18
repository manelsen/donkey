## turn_journal_store — append-only durable journal for turns (US-002).
##
## One JSONL file per state dir, `state/turn_journal.jsonl`. Every line is a
## `TurnEvent` (US-001) framed as `"\n<json>\n"`, so a torn tail can never
## merge with the next event. The adapter owns every file operation; the pure
## reducer in `domain/session/turn_journal_pure` owns the state transitions.
##
## Durability points:
##   - `append` returns `ok` only after the data file is fsynced. An `err`
##     means the bytes may be visible but are not confirmed durable.
##   - when a data fsync fails, the tail is marked unsynced for that journal
##     path and the next append retries the fsync *before* writing more.
##     `commitIfTerminal` never reports an already-visible commit frame as
##     persisted until that retry succeeds (B1).
##   - the journal's directory entry is fsynced when the file is created, and
##     a failed directory fsync stays pending and is retried by the next
##     append instead of being forgotten because `isNew` is now false (B2).
##   - when this store creates the state directory, its entry in the parent
##     directory is fsynced too, so the directory itself survives a power loss
##     (B3).
##   - compaction writes a sibling temp file, fsyncs it, renames it over the
##     journal and fsyncs the directory.
##
## Guarantee across restarts: the pending flags only close the in-process
## window where a frame sits in the page cache and a power loss could still
## drop it. After a fresh open there is no flag, and framing decides: a
## complete `\n<json>\n` frame read back from disk survived the power loss,
## while a lost or torn frame is discarded by `repairTornTail` and the turn
## stays active for recovery. A visible `tevCommitted` is therefore trusted
## after a restart, but never trusted by the process that failed to fsync it.
## A per-frame durability marker would change the on-disk schema, which this
## story forbids.
##
## Permissions: state dir 0700, journal file 0600.
##
## Forward compatibility: unknown fields on a known event are ignored, a torn
## trailing line is ignored, and unknown versions/event kinds are skipped.
## Compaction refuses to rewrite a journal that contains any of those, so a
## newer writer's data is never silently discarded.
##
## Concurrency: a module-level lock serializes append/commit/compact/read for
## every store instance in this process (the daemon has one writer actor and a
## drainer thread). Check-then-append for `tevCommitted` happens under the
## same lock, which makes the second commit a no-op even across instances.
## Cross-process writers are not supported: the daemon lease is the single
## writer.

import std/[json, locks, options, os, strutils, tables]
when defined(posix):
  import std/posix
import ../../core/pipeops
import ../../domain/session/turn_journal_pure

const
  TurnJournalFileName* = "turn_journal.jsonl"
  TurnJournalVersion* = 1
  DefaultTurnJournalRetentionMs* = 7'i64 * 24 * 60 * 60 * 1000
    ## Terminals older than this are dropped by `compact`; active turns stay.
  MaxInboundBytes* = 16 * 1024
  MaxReplyBytes* = 32 * 1024
  MaxMediaUrls* = 10
  MaxMediaUrlBytes* = 2 * 1024

  JournalFields = [
    "v", "kind", "turn_id", "ts_ms",
    "user_id", "channel", "chat_id", "channel_message_id", "task_kind",
    "inbound_text", "media_urls", "created_at_ms",
    "reply_text", "reply_hash", "memory_hash", "reply_source",
    "delivery_id", "owner_epoch_ms",
  ]

type
  TurnJournalStore* = ref object
    stateDir*: string
    path*: string

  TurnJournalPort* = object
    ## Application-facing boundary. A nil callback means the journal is off;
    ## callers must then keep the current behaviour. All callbacks take the
    ## turn id explicitly because only `tevInboundAccepted` carries one in the
    ## closed event schema.
    append*: proc(turnId: string; event: TurnEvent;
                  nowMs: int64): Result[void, string] {.gcsafe, raises: [].}
    loadAll*: proc(): Result[seq[TurnEntry], string] {.gcsafe, raises: [].}
    loadActive*: proc(): Result[seq[TurnEntry], string] {.gcsafe, raises: [].}
    loadById*: proc(turnId: string): Result[Option[TurnEntry], string] {.gcsafe, raises: [].}
    loadByInbound*: proc(turnId: string): Result[Option[TurnEntry], string] {.gcsafe, raises: [].}
    commitIfTerminal*: proc(turnId: string;
                            nowMs: int64): Result[bool, string] {.gcsafe, raises: [].}
    compact*: proc(nowMs: int64): Result[bool, string] {.gcsafe, raises: [].}

  JournalSnapshot = object
    entries: OrderedTable[string, TurnEntry]
    lastTs: Table[string, int64]
    rawLines: seq[tuple[turnId, line: string]]
    unknownFields: bool
    unknownKind: bool
    corruptMiddle: bool

  ParsedEvent = object
    event: Option[TurnEvent]
    unknownFields: bool
    unknownKind: bool

  PendingSync = object
    ## Durability of the last write has not been confirmed yet. A flag is
    ## cleared only by a successful fsync of the same kind.
    data: bool       ## tail bytes were written but their fsync failed
    directory: bool  ## a directory entry on the journal path is not fsynced
    commit: bool     ## a `tevCommitted` frame was written but not fsynced,
                     ## and its writer never waited for a later fsync of it

# A single lock for every journal instance in this process: the file is the
# unit of serialization, not the store object.
var journalLock: Lock
initLock(journalLock)

# Pending sync flags are keyed by journal path, not by store instance: the
# daemon's actor and drainer hold distinct instances over the same file, and a
# commit written by one must not be trusted by the other before its fsync
# succeeds. All access happens under `journalLock`.
var pendingSyncByPath: Table[string, PendingSync]

proc loadPending(path: string): PendingSync {.raises: [].} =
  {.cast(gcsafe).}:
    result = pendingSyncByPath.getOrDefault(path)

proc savePending(path: string; pending: PendingSync) {.raises: [].} =
  {.cast(gcsafe).}:
    if pending.data or pending.directory or pending.commit:
      pendingSyncByPath[path] = pending
    else:
      pendingSyncByPath.del(path)

# ---------------------------------------------------------------------------
# Test seam for the durability guarantees (B1/B2/B3). Production code never
# installs a hook: the default is nil and every fsync goes to the kernel. The
# tests use it to fail a specific fsync and assert that the store retries.
# ---------------------------------------------------------------------------

type
  JournalSyncKind* = enum
    jskData       ## data-file fsync (the frame bytes)
    jskDirectory  ## directory-entry fsync (new file, rename, new state dir)

  JournalSyncHook* = proc(path: string; kind: JournalSyncKind): bool
    {.gcsafe, raises: [].}
    ## Returns `true` to perform the real fsync, `false` to simulate failure.

var journalSyncHook {.threadvar.}: JournalSyncHook
  ## Thread-local so the seam never needs a lock and tests are independent.

proc setTurnJournalSyncHook*(hook: JournalSyncHook) {.raises: [].} =
  ## Test-only injection point. Pass `nil` to restore real fsync behaviour.
  journalSyncHook = hook

proc syncAllowed(path: string; kind: JournalSyncKind): bool {.raises: [].} =
  let hook = journalSyncHook
  hook == nil or hook(path, kind)

# ---------------------------------------------------------------------------
# Small durable-file helpers. `adapters/state/runtime_store.nim` has the same
# building blocks inline; extracting them into `durable_file.nim` needs a file
# this story does not own, so the helpers stay private here for now.
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
    if not syncAllowed(path, jskData):
      return err("fsync failed for " & path & ": injected failure")
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
    if not syncAllowed(path, jskDirectory):
      return err("fsync failed for directory " & path & ": injected failure")
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

proc ensureJournalDir(path: string;
                      pendingDirSync: var bool): Result[void, string] {.raises: [].} =
  let dir = parentDir(path)
  if dir.len == 0:
    return ok()
  let existed = dirExists(dir)
  try:
    createDir(dir)
  except CatchableError as e:
    return err("cannot create journal directory " & dir & ": " & e.msg)
  let hardened = hardenDir(dir)
  if hardened.isErr:
    if not existed:
      pendingDirSync = true
    return err(hardened.error)
  if not existed:
    # B3: the new directory's own entry lives in its parent. Without this
    # fsync a crash right after creation can lose the state dir and the
    # journal inside it, even though the journal file itself was fsynced.
    let parent = parentDir(dir)
    if parent.len > 0:
      let synced = syncDir(parent)
      if synced.isErr:
        pendingDirSync = true
        return err(synced.error)
  ok()

proc repairTornTail(path: string): Result[void, string] {.raises: [].} =
  ## Frames always end with '\n'. If the last byte is not a newline, the
  ## previous append never completed (it did not return Ok), so the partial
  ## frame is safe to drop. Without this, a torn tail followed by a new append
  ## would become permanent middle corruption and block compaction.
  when defined(posix):
    try:
      let size = getFileSize(path)
      if size <= 0:
        return ok()
      var f = open(path, fmReadWriteExisting)
      defer: f.close()
      f.setFilePos(size - 1)
      if f.readChar() == '\n':
        return ok()
      var cut = 0'i64
      var pos = size - 1
      while pos > 0:
        dec pos
        f.setFilePos(pos)
        if f.readChar() == '\n':
          cut = pos + 1
          break
      if posix.ftruncate(cint(f.getFileHandle()), posix.Off(cut)) != 0:
        return err("cannot repair torn journal " & path & ": " &
                   osErrorMsg(osLastError()))
      f.setFilePos(cut)
      ok()
    except CatchableError as e:
      err("cannot repair torn journal " & path & ": " & e.msg)
  else:
    # Non-POSIX builds keep the torn bytes; reads still ignore them.
    ok()

proc syncJournalDirs(path: string): Result[void, string] {.raises: [].} =
  ## Persists the directory entries that make the journal reachable: the file
  ## entry in the state dir (B2) and, one level up, the state dir's own entry
  ## when this store created it (B3). Both are idempotent; a missing directory
  ## is skipped because `ensureJournalDir` will create and sync it.
  let dir = parentDir(path)
  if dir.len > 0 and dirExists(dir):
    let synced = syncDir(dir)
    if synced.isErr:
      return err(synced.error)
  let parent = parentDir(dir)
  if parent.len > 0 and dirExists(parent):
    let synced = syncDir(parent)
    if synced.isErr:
      return err(synced.error)
  ok()

proc syncExistingFile(path: string): Result[void, string] {.raises: [].} =
  ## Re-fsyncs a file that was written earlier without reopening it for
  ## append. Used to retry a data fsync that failed on a previous call.
  if not fileExists(path):
    return ok()
  try:
    var f = open(path, fmReadWriteExisting)
    defer: f.close()
    syncFile(f, path)
  except CatchableError as e:
    err("cannot reopen journal " & path & " for fsync: " & e.msg)

proc retryPendingSync(path: string;
                      pending: var PendingSync): Result[void, string] {.raises: [].} =
  ## Runs before any new bytes are written. A tail whose fsync failed is
  ## confirmed first; writing on top of it would extend the unconfirmed range
  ## and make the window larger. A resynced commit keeps `commit = true`: its
  ## bytes are now durable, but only a later process that reads them back may
  ## report the commit as persisted.
  if pending.directory:
    let synced = syncJournalDirs(path)
    if synced.isErr:
      return err(synced.error)
    pending.directory = false
  if pending.data:
    let synced = syncExistingFile(path)
    if synced.isErr:
      return err(synced.error)
    pending.data = false
  ok()

proc appendFramedLine(path, line: string; isCommit: bool;
                      pending: var PendingSync): Result[void, string] {.raises: [].} =
  ## Appends exactly one frame and fsyncs the data file. The directory entry is
  ## fsynced when this append created the journal, or retried when an earlier
  ## creation could not confirm it. On a failed data fsync the frame stays on
  ## disk (a later retry can still make it durable) but the call returns `err`
  ## and the tail is marked pending. `isCommit` keeps that mark on a
  ## `tevCommitted` frame even after a retry resyncs it.
  var mayHaveWritten = false
  try:
    let prepared = ensureJournalDir(path, pending.directory)
    if prepared.isErr:
      return err(prepared.error)
    let retried = retryPendingSync(path, pending)
    if retried.isErr:
      return err(retried.error)
    let isNew = not fileExists(path)
    if not isNew:
      let repaired = repairTornTail(path)
      if repaired.isErr:
        return err(repaired.error)
    var f = open(path, fmAppend)
    let hardened = hardenFile(path)
    if hardened.isErr:
      f.close()
      return err(hardened.error)
    mayHaveWritten = true
    var syncError = ""
    try:
      f.write("\n" & line & "\n")
      let synced = syncFile(f, path)
      if synced.isErr:
        syncError = synced.error
    finally:
      f.close()
    if syncError.len > 0:
      pending.data = true
      if isCommit:
        pending.commit = true
      return err(syncError)
    pending.data = false
    # A later frame must not clear the mark of a commit the retry resynced:
    # only a new commit this call fsynced, or a restart, settles that one.
    if isCommit:
      pending.commit = false
    if isNew:
      let dir = parentDir(path)
      if dir.len > 0:
        let synced = syncDir(dir)
        if synced.isErr:
          pending.directory = true
          return err(synced.error)
    ok()
  except CatchableError as e:
    if mayHaveWritten:
      pending.data = true
      if isCommit:
        pending.commit = true
    err("append failed for " & path & ": " & e.msg)

proc atomicWriteText(path, content, tmpSuffix: string;
                     pending: var PendingSync): Result[void, string] {.raises: [].} =
  ## Temp file + fsync + rename + directory fsync. Used by compaction only.
  let tmp = path & ".tmp." & tmpSuffix
  try:
    let prepared = ensureJournalDir(path, pending.directory)
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
    # The renamed file's data was fsynced above, so a pending tail from the
    # old file no longer exists.
    pending.data = false
    pending.commit = false
    let dir = parentDir(path)
    if dir.len > 0:
      let synced = syncDir(dir)
      if synced.isErr:
        pending.directory = true
        return err(synced.error)
    ok()
  except CatchableError as e:
    removeQuietly(tmp)
    err("atomic write failed for " & path & ": " & e.msg)

# ---------------------------------------------------------------------------
# Redaction and size limits (schema/privacy, FR-8 and §9).
# ---------------------------------------------------------------------------

func lowerAscii(c: char): char =
  if c in {'A'..'Z'}: chr(ord(c) + 32) else: c

func isAsciiAlphaNum(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9'}

func matchesAt(text: string; i: int; lit: string): bool =
  if i < 0 or i + lit.len > text.len:
    return false
  for k in 0 ..< lit.len:
    if lowerAscii(text[i + k]) != lowerAscii(lit[k]):
      return false
  true

func isValueDelimiter(c: char): bool =
  c in {' ', '\t', '\n', '\r', '&', '"', '\'', ',', ';', ')', ']', '}', '<', '>'}

func redactSecrets*(text: string): string =
  ## Removes credentials before the append: `Bearer <token>`, `sk-...`,
  ## `key=<value>` and `token=<value>`. The label is kept so an operator can
  ## still see that a credential was present; the value never reaches disk.
  result = newStringOfCap(text.len)
  var i = 0
  while i < text.len:
    if matchesAt(text, i, "bearer") and
       (i == 0 or not isAsciiAlphaNum(text[i - 1])):
      var j = i + "bearer".len
      while j < text.len and text[j] in {' ', '\t'}:
        inc j
      if j > i + "bearer".len and j < text.len:
        result.add text[i ..< j]
        result.add "[redacted]"
        i = j
        while i < text.len and
              text[i] notin {' ', '\t', '\n', '\r', '"', '\'', ',', ';'}:
          inc i
        continue
    elif matchesAt(text, i, "sk-") and
         (i == 0 or not isAsciiAlphaNum(text[i - 1])):
      var j = i + "sk-".len
      while j < text.len and
            (isAsciiAlphaNum(text[j]) or text[j] in {'-', '_'}):
        inc j
      if j > i + "sk-".len:
        result.add "sk-[redacted]"
        i = j
        continue
    elif (matchesAt(text, i, "key=") or matchesAt(text, i, "token=")) and
         (i == 0 or not isAsciiAlphaNum(text[i - 1])):
      let label = if matchesAt(text, i, "key="): "key=" else: "token="
      result.add text[i ..< i + label.len]
      i += label.len
      if i < text.len and text[i] in {'"', '\''}:
        ## A quoted value ends at the matching quote; stopping at the opening
        ## quote would leave the secret itself in the journal.
        let quote = text[i]
        inc i
        while i < text.len and text[i] != quote:
          inc i
        if i < text.len:
          inc i
      else:
        while i < text.len and not isValueDelimiter(text[i]):
          inc i
      result.add "[redacted]"
      continue
    result.add text[i]
    inc i

func truncateUtf8(text: string; maxBytes: int): string =
  ## Hard cap by bytes without splitting a UTF-8 sequence.
  if maxBytes <= 0:
    return ""
  if text.len <= maxBytes:
    return text
  var cut = maxBytes
  while cut > 0 and (ord(text[cut]) and 0xC0) == 0x80:
    dec cut
  text[0 ..< cut]

func sanitizeEvent(event: TurnEvent): TurnEvent =
  ## Privacy and size limits are enforced by the adapter, before encoding, so
  ## every writer gets them regardless of caller discipline.
  result = event
  case event.kind
  of tevInboundAccepted:
    result.inboundText = truncateUtf8(redactSecrets(event.inboundText),
                                      MaxInboundBytes)
    var urls: seq[string]
    for url in event.mediaUrls:
      if urls.len >= MaxMediaUrls:
        break
      urls.add truncateUtf8(redactSecrets(url), MaxMediaUrlBytes)
    result.mediaUrls = urls
  of tevReplyReady:
    result.replyText = truncateUtf8(redactSecrets(event.replyText),
                                    MaxReplyBytes)
  else:
    discard

# ---------------------------------------------------------------------------
# JSON encoding/decoding.
# ---------------------------------------------------------------------------

proc jsonStr(node: JsonNode; key: string): string =
  let value = node{key}
  if value == nil or value.kind != JString:
    return ""
  value.getStr

proc jsonInt(node: JsonNode; key: string; default: int64 = 0): int64 =
  let value = node{key}
  if value == nil:
    return default
  case value.kind
  of JInt: value.getInt.int64
  of JFloat: value.getFloat.int64
  else: default

proc eventToJson(turnId: string; event: TurnEvent; stamp: int64): JsonNode =
  result = newJObject()
  result["v"] = %TurnJournalVersion
  result["kind"] = %($event.kind)
  result["turn_id"] = %turnId
  result["ts_ms"] = %stamp
  case event.kind
  of tevInboundAccepted:
    result["user_id"] = %event.userId
    result["channel"] = %event.channel
    result["chat_id"] = %event.chatId
    result["channel_message_id"] = %event.channelMessageId
    result["task_kind"] = %event.taskKind
    result["inbound_text"] = %event.inboundText
    var media = newJArray()
    for url in event.mediaUrls:
      media.add(%url)
    result["media_urls"] = media
    result["created_at_ms"] = %event.createdAtMs
  of tevReplyReady:
    result["reply_text"] = %event.replyText
    result["reply_hash"] = %event.replyHash
    result["memory_hash"] = %event.memoryHash
    result["reply_source"] = %($event.replySource)
    if event.deliveryId.len > 0:
      result["delivery_id"] = %event.deliveryId
  of tevDeliveryAttempted:
    result["owner_epoch_ms"] = %event.ownerEpochMs
    if event.deliveryId.len > 0:
      result["delivery_id"] = %event.deliveryId
  else:
    if event.deliveryId.len > 0:
      result["delivery_id"] = %event.deliveryId

proc parseReplySource(value: string; parsed: var ReplySource): bool =
  if value.len == 0:
    return true
  try:
    parsed = parseEnum[ReplySource](value)
    true
  except ValueError:
    false

proc parseEvent(node: JsonNode): ParsedEvent =
  ## Returns the event plus forward-compatibility flags. An unknown version or
  ## kind is skipped; unknown fields on a known event are ignored but flagged.
  let version = jsonInt(node, "v", TurnJournalVersion)
  if version > TurnJournalVersion:
    result.unknownKind = true
    return
  let kindName = jsonStr(node, "kind")
  var kind: TurnEventKind
  try:
    kind = parseEnum[TurnEventKind](kindName)
  except ValueError:
    result.unknownKind = true
    return

  var event = TurnEvent(kind: kind)
  case kind
  of tevInboundAccepted:
    event.turnId = jsonStr(node, "turn_id")
    event.userId = jsonStr(node, "user_id")
    event.channel = jsonStr(node, "channel")
    event.chatId = jsonStr(node, "chat_id")
    event.channelMessageId = jsonStr(node, "channel_message_id")
    event.taskKind = jsonStr(node, "task_kind")
    event.inboundText = jsonStr(node, "inbound_text")
    let media = node{"media_urls"}
    if media != nil and media.kind == JArray:
      for item in media:
        if item.kind == JString:
          event.mediaUrls.add(item.getStr)
    event.createdAtMs = jsonInt(node, "created_at_ms")
  of tevReplyReady:
    event.replyText = jsonStr(node, "reply_text")
    event.replyHash = jsonStr(node, "reply_hash")
    event.memoryHash = jsonStr(node, "memory_hash")
    event.deliveryId = jsonStr(node, "delivery_id")
    if not parseReplySource(jsonStr(node, "reply_source"), event.replySource):
      # An unknown reply source changes the resume decision; keep the line for
      # a newer build instead of guessing `rsBuffered`.
      result.unknownKind = true
      return
  of tevDeliveryAttempted:
    event.ownerEpochMs = jsonInt(node, "owner_epoch_ms")
    event.deliveryId = jsonStr(node, "delivery_id")
  else:
    event.deliveryId = jsonStr(node, "delivery_id")

  for key, _ in node.pairs:
    if key notin JournalFields:
      result.unknownFields = true
      break
  result.event = some(event)

# ---------------------------------------------------------------------------
# Reading and folding the journal.
# ---------------------------------------------------------------------------

proc readJournal(path: string): Result[JournalSnapshot, string] {.raises: [].} =
  var snapshot = JournalSnapshot(
    entries: initOrderedTable[string, TurnEntry](),
    lastTs: initTable[string, int64](),
  )
  if not fileExists(path):
    return ok(snapshot)
  var raw = ""
  try:
    raw = readFile(path)
  except CatchableError as e:
    return err("cannot read turn journal " & path & ": " & e.msg)

  ## Frames are written as `\n<json>\n`. A trailing segment without its LF is
  ## a torn append even when the JSON happens to be complete: applying it would
  ## report an event the writer never confirmed, and the next append repairs
  ## (removes) exactly that segment.
  var lines = raw.split('\n')
  if raw.len > 0 and raw[^1] == '\n':
    if lines.len > 0: lines.setLen(lines.len - 1)
  elif lines.len > 0:
    lines.setLen(lines.len - 1)
  var lastNonEmpty = -1
  for idx, line in lines:
    if line.strip().len > 0:
      lastNonEmpty = idx

  for idx, line in lines:
    if line.strip().len == 0:
      continue
    var node: JsonNode
    try:
      node = parseJson(line)
    except CatchableError:
      if idx == lastNonEmpty:
        discard  # Torn trailing append: ignore and let the next append repair.
      else:
        snapshot.corruptMiddle = true
      continue
    if node.kind != JObject:
      if idx == lastNonEmpty:
        discard
      else:
        snapshot.corruptMiddle = true
      continue

    let turnId = jsonStr(node, "turn_id")
    if turnId.len == 0:
      snapshot.unknownKind = true
      continue
    let parsed = parseEvent(node)
    if parsed.unknownKind:
      snapshot.unknownKind = true
      continue
    if parsed.unknownFields:
      snapshot.unknownFields = true
    if parsed.event.isNone:
      continue

    let event = parsed.event.get()
    let stamp = jsonInt(node, "ts_ms", 0)
    if stamp > snapshot.lastTs.getOrDefault(turnId, 0'i64):
      snapshot.lastTs[turnId] = stamp
    snapshot.rawLines.add((turnId: turnId, line: line))

    let previous =
      if turnId in snapshot.entries: some(snapshot.entries.getOrDefault(turnId))
      else: none(TurnEntry)
    let advanced = applyTurnEvent(previous, event)
    if advanced.isSome:
      snapshot.entries[turnId] = advanced.get()

  ok(snapshot)

proc loadByIdLocked(store: TurnJournalStore;
                    turnId: string): Result[Option[TurnEntry], string] {.raises: [].} =
  let snapshot = readJournal(store.path)
  if snapshot.isErr:
    return err(snapshot.error)
  if turnId in snapshot.get().entries:
    ok(some(snapshot.get().entries.getOrDefault(turnId)))
  else:
    ok(none(TurnEntry))

# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------

proc newTurnJournalStore*(stateDir: string): TurnJournalStore =
  TurnJournalStore(stateDir: stateDir,
                   path: stateDir / TurnJournalFileName)

proc appendEventLocked(store: TurnJournalStore; turnId: string;
                       event: TurnEvent; stamp: int64): Result[void, string] {.raises: [].} =
  ## Caller must hold `journalLock`.
  let effective = sanitizeEvent(event)
  let line = $eventToJson(turnId, effective, stamp)
  var pending = loadPending(store.path)
  let saved = appendFramedLine(store.path, line,
                               event.kind == tevCommitted, pending)
  savePending(store.path, pending)
  saved

proc confirmDurabilityLocked(store: TurnJournalStore): Result[void, string] {.raises: [].} =
  ## Caller must hold `journalLock`. Confirms a tail left pending by an earlier
  ## failed fsync. Used before reporting an already-visible commit frame as
  ## persisted (B1). A failed retry keeps the flag so the next call tries again.
  ## Resyncing the bytes does not settle a `commit` mark: that record says its
  ## writer never waited for the fsync, so only a process that reads the frame
  ## back from disk may treat the commit as persisted.
  var pending = loadPending(store.path)
  if pending.data:
    let synced = syncExistingFile(store.path)
    if synced.isErr:
      savePending(store.path, pending)
      return err(synced.error)
    pending.data = false
  if pending.directory:
    let synced = syncJournalDirs(store.path)
    if synced.isErr:
      savePending(store.path, pending)
      return err(synced.error)
    pending.directory = false
  savePending(store.path, pending)
  if pending.commit:
    return err("commit frame of " & store.path &
               " was not fsynced by its writer")
  ok()

proc append*(store: TurnJournalStore; turnId: string; event: TurnEvent;
             nowMs: int64 = 0): Result[void, string] {.gcsafe, raises: [].} =
  ## Appends one event and fsyncs it. `ok` means written *and* fsynced; `err`
  ## means the event is not confirmed durable. A second `tevCommitted` for an
  ## already committed turn is a no-op: the drainer and the actor may both
  ## reach the commit point, and the journal is the arbiter. That no-op still
  ## confirms a pending fsync first, so it never reports success for a frame
  ## that may only be in the page cache.
  if turnId.len == 0:
    return err("turn journal: empty turn id")
  acquire(journalLock)
  defer: release(journalLock)
  let stamp = if nowMs > 0: nowMs else: epochMs()
  if event.kind == tevCommitted:
    let snapshot = readJournal(store.path)
    if snapshot.isErr:
      return err(snapshot.error)
    let current =
      if turnId in snapshot.get().entries:
        some(snapshot.get().entries.getOrDefault(turnId))
      else:
        none(TurnEntry)
    if current.isSome and current.get.phase == tpsCommitted:
      return store.confirmDurabilityLocked()
  store.appendEventLocked(turnId, event, stamp)

proc commitIfTerminal*(store: TurnJournalStore; turnId: string;
                       nowMs: int64 = 0): Result[bool, string] {.gcsafe, raises: [].} =
  ## Commits only when delivery, memory and transcript are terminal. Returns
  ## `true` when this call wrote and fsynced `tevCommitted` and `false` when
  ## there was nothing to do (missing, active, not terminal or already
  ## committed). An already-visible commit frame whose fsync failed is retried
  ## before `false` is returned, and an `err` means the frame is not durable.
  acquire(journalLock)
  defer: release(journalLock)
  let snapshot = readJournal(store.path)
  if snapshot.isErr:
    return err(snapshot.error)
  if turnId notin snapshot.get().entries:
    return ok(false)
  let entry = snapshot.get().entries.getOrDefault(turnId)
  if entry.phase in {tpsCommitted, tpsAbandoned}:
    if entry.phase == tpsCommitted:
      let confirmed = store.confirmDurabilityLocked()
      if confirmed.isErr:
        return err(confirmed.error)
    return ok(false)
  if not isTurnTerminal(entry):
    return ok(false)
  let stamp = if nowMs > 0: nowMs else: epochMs()
  let saved = store.appendEventLocked(turnId,
    TurnEvent(kind: tevCommitted), stamp)
  if saved.isErr:
    return err(saved.error)
  ok(true)

proc loadAll*(store: TurnJournalStore): Result[seq[TurnEntry], string] {.gcsafe, raises: [].} =
  acquire(journalLock)
  defer: release(journalLock)
  let snapshot = readJournal(store.path)
  if snapshot.isErr:
    return err(snapshot.error)
  var entries: seq[TurnEntry]
  for entry in snapshot.get().entries.values:
    entries.add(entry)
  ok(entries)

proc loadActive*(store: TurnJournalStore): Result[seq[TurnEntry], string] {.gcsafe, raises: [].} =
  ## Turns that still need work: not committed and not abandoned.
  acquire(journalLock)
  defer: release(journalLock)
  let snapshot = readJournal(store.path)
  if snapshot.isErr:
    return err(snapshot.error)
  var entries: seq[TurnEntry]
  for entry in snapshot.get().entries.values:
    if entry.phase notin {tpsCommitted, tpsAbandoned}:
      entries.add(entry)
  ok(entries)

proc loadById*(store: TurnJournalStore;
               turnId: string): Result[Option[TurnEntry], string] {.gcsafe, raises: [].} =
  acquire(journalLock)
  defer: release(journalLock)
  store.loadByIdLocked(turnId)

proc loadByInbound*(store: TurnJournalStore; turnId: string
                   ): Result[Option[TurnEntry], string] {.gcsafe, raises: [].} =
  ## The inbound identity *is* the turn id (`turnIdFor`), so the ingress uses
  ## the computed id directly. Kept as a distinct name so callers state their
  ## intent and a future index can optimize it.
  acquire(journalLock)
  defer: release(journalLock)
  store.loadByIdLocked(turnId)

proc loadByInbound*(store: TurnJournalStore; userId, channel, channelMessageId,
                    chatId, text: string
                   ): Result[Option[TurnEntry], string] {.gcsafe, raises: [].} =
  ## Convenience for callers that still have the raw inbound fields.
  store.loadByInbound(turnIdFor(userId, channel, channelMessageId, chatId, text))

proc compact*(store: TurnJournalStore; nowMs: int64;
              retentionMs: int64 = DefaultTurnJournalRetentionMs
             ): Result[bool, string] {.gcsafe, raises: [].} =
  ## Rewrites the journal with active turns plus terminals seen within the
  ## retention window. Returns `true` when the file was rewritten.
  ##
  ## Refuses to rewrite (returns `false`) when a line has unknown fields, an
  ## unknown version/kind or corruption in the middle: compaction must never
  ## silently discard a newer writer's data. A torn trailing line is the one
  ## safe case, because it was never a complete frame.
  ##
  ## A directory entry left pending by an earlier rename is confirmed here even
  ## when this pass rewrites nothing: the rename is the only thing that made
  ## the new file reachable, so waiting for the next append could wait forever.
  acquire(journalLock)
  defer: release(journalLock)
  var pending = loadPending(store.path)
  if pending.directory:
    let synced = syncJournalDirs(store.path)
    if synced.isErr:
      return err(synced.error)
    pending.directory = false
    savePending(store.path, pending)
  let snapshot = readJournal(store.path)
  if snapshot.isErr:
    return err(snapshot.error)
  let current = snapshot.get()
  if current.unknownFields or current.unknownKind or current.corruptMiddle:
    return ok(false)

  let now = if nowMs > 0: nowMs else: epochMs()
  let retention = if retentionMs > 0: retentionMs
                  else: DefaultTurnJournalRetentionMs
  let cutoff = now - retention
  var kept = 0
  var payload = ""
  for item in current.rawLines:
    if item.turnId notin current.entries:
      continue  # Orphan event without an inbound; not a turn.
    let entry = current.entries.getOrDefault(item.turnId)
    var keep = entry.phase notin {tpsCommitted, tpsAbandoned}
    if not keep:
      var seen = current.lastTs.getOrDefault(item.turnId, 0'i64)
      if seen <= 0:
        seen = entry.createdAtMs
      # Unknown age is kept: dropping it would lose a terminal silently.
      keep = seen <= 0 or seen >= cutoff
    if keep:
      payload.add("\n" & item.line & "\n")
      inc kept
  if kept == current.rawLines.len:
    return ok(false)

  var suffix = $getCurrentProcessId() & "-" & $now
  var attempt = 0
  while fileExists(store.path & ".tmp." & suffix):
    inc attempt
    suffix = $getCurrentProcessId() & "-" & $now & "-" & $attempt
  let written = atomicWriteText(store.path, payload, suffix, pending)
  savePending(store.path, pending)
  if written.isErr:
    return err(written.error)
  ok(true)

proc turnJournalPort*(store: TurnJournalStore): TurnJournalPort =
  ## Adapter-to-port binding, mirroring `runtime_store`'s port accessors.
  TurnJournalPort(
    append: proc(turnId: string; event: TurnEvent;
                 nowMs: int64): Result[void, string] {.gcsafe, raises: [].} =
      store.append(turnId, event, nowMs),
    loadAll: proc(): Result[seq[TurnEntry], string] {.gcsafe, raises: [].} =
      store.loadAll(),
    loadActive: proc(): Result[seq[TurnEntry], string] {.gcsafe, raises: [].} =
      store.loadActive(),
    loadById: proc(turnId: string): Result[Option[TurnEntry], string] {.gcsafe, raises: [].} =
      store.loadById(turnId),
    loadByInbound: proc(turnId: string): Result[Option[TurnEntry], string] {.gcsafe, raises: [].} =
      store.loadByInbound(turnId),
    commitIfTerminal: proc(turnId: string;
                           nowMs: int64): Result[bool, string] {.gcsafe, raises: [].} =
      store.commitIfTerminal(turnId, nowMs),
    compact: proc(nowMs: int64): Result[bool, string] {.gcsafe, raises: [].} =
      store.compact(nowMs),
  )

proc hasTurnJournal*(port: TurnJournalPort): bool =
  port.append != nil and port.loadAll != nil and port.loadById != nil and
    port.commitIfTerminal != nil
