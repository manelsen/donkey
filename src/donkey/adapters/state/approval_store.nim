## approval_store.nim — JSON-backed pending tool approvals.
##
## The daemon writes requests and polls decisions; `ctl approval` reads and
## decides from another process. Writes are atomic (tmp + rename).

import std/[json, options, os, random]
when defined(posix):
  import std/posix
import ../../core/pipeops
import ../../core/security/approval
import ../../ports/approval

type
  ApprovalStore* = ref object
    path*: string
    ## Optional instrumentation hook, called under the lock after the temp
    ## file is written and before the atomic rename.
    onAfterTempWrite*: proc() {.gcsafe, raises: [].}

const
  MaxPendingPerUser* = 8

when defined(posix):
  proc cFlock(fd: cint; operation: cint): cint {.
    importc: "flock", header: "<sys/file.h>".}
  const
    ApprovalLockExclusive = cint(2)
    ApprovalLockUnlock    = cint(8)

func newApprovalStore*(path: string): ApprovalStore =
  ApprovalStore(path: path)

proc withApprovalLock*[T](store: ApprovalStore;
                          body: proc(): Result[T, string] {.gcsafe, raises: [].}): Result[T, string] {.gcsafe, raises: [].} =
  ## Serializes read-modify-write cycles between the daemon and `ctl`.
  when defined(posix):
    let lockPath = store.path & ".lock"
    try:
      createDir(parentDir(lockPath))
      var lockFile = open(lockPath, fmReadWrite)
      let fd = cint(lockFile.getFileHandle())
      if cFlock(fd, ApprovalLockExclusive) != 0:
        lockFile.close()
        return err("approval store lock failed")
      try:
        result = body()
      finally:
        discard cFlock(fd, ApprovalLockUnlock)
        lockFile.close()
    except CatchableError as e:
      result = err("approval store lock failed: " & e.msg)
  else:
    result = body()

proc newApprovalId(): string =
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
  randomize()
  for _ in 0 ..< ApprovalIdLength:
    result.add(alphabet[rand(alphabet.high)])

func requestToJson(request: ApprovalRequest): JsonNode =
  %* {
    "id":            request.id,
    "user_id":       request.userId,
    "channel":       request.channel,
    "tool":          request.toolName,
    "summary":       request.summary,
    "created_at_ms": request.createdAtMs,
    "expires_at_ms": request.expiresAtMs,
    "status":        $request.status,
  }

func requestFromJson(node: JsonNode): Option[ApprovalRequest] =
  if node == nil or node.kind != JObject:
    return none(ApprovalRequest)
  let id = node.getOrDefault("id").getStr("")
  if not isValidApprovalId(id):
    return none(ApprovalRequest)
  let status = parseStatus(node.getOrDefault("status").getStr("pending"))
  if status.isNone:
    return none(ApprovalRequest)
  some(ApprovalRequest(
    id:          id,
    userId:      node.getOrDefault("user_id").getStr(""),
    channel:     node.getOrDefault("channel").getStr(""),
    toolName:    node.getOrDefault("tool").getStr(""),
    summary:     node.getOrDefault("summary").getStr(""),
    createdAtMs: node.getOrDefault("created_at_ms").getBiggestInt(0),
    expiresAtMs: node.getOrDefault("expires_at_ms").getBiggestInt(0),
    status:      status.get,
  ))

proc load*(store: ApprovalStore;
           nowMs = epochMs()): Result[seq[ApprovalRequest], string] {.raises: [].} =
  if store.path.len == 0:
    return err("approval store path is empty")
  if not fileExists(store.path):
    return ok(newSeq[ApprovalRequest]())
  try:
    let root = parseJson(readFile(store.path))
    let items = root.getOrDefault("requests")
    if items == nil:
      return ok(newSeq[ApprovalRequest]())
    if items.kind != JArray:
      return err("approval store is not an array")
    var requests: seq[ApprovalRequest]
    for item in items:
      let parsed = requestFromJson(item)
      if parsed.isNone:
        continue
      let request = parsed.get
      if request.status == apsPending and nowMs >= request.expiresAtMs:
        continue
      if request.status != apsPending and
         nowMs - request.expiresAtMs > ApprovalTerminalRetentionMs:
        continue
      requests.add(request)
    return ok(requests)
  except CatchableError as e:
    return err("approval store read failed: " & e.msg)

proc save*(store: ApprovalStore;
           requests: seq[ApprovalRequest]): Result[void, string] {.raises: [].} =
  if store.path.len == 0:
    return err("approval store path is empty")
  var items = newJArray()
  for request in requests:
    items.add(requestToJson(request))
  try:
    let dir = parentDir(store.path)
    createDir(dir)
    when defined(posix):
      discard posix.chmod(dir.cstring, posix.Mode(0o700))
    let tmp = store.path & ".tmp." & $getCurrentProcessId() & "-" & $epochMs()
    writeFile(tmp, $(%* {"requests": items}))
    when defined(posix):
      discard posix.chmod(tmp.cstring, posix.Mode(0o600))
    if store.onAfterTempWrite != nil:
      store.onAfterTempWrite()
    {.cast(raises: []).}:
      moveFile(tmp, store.path)
    ok()
  except CatchableError as e:
    err("approval store write failed: " & e.msg)

proc createLocked(store: ApprovalStore;
                  userId: string;
                  channel: string;
                  toolName, summary: string;
                  ttlMs: int64;
                  nowMs: int64): Result[ApprovalRequest, string] {.raises: [].} =
  if userId.len == 0:
    return err("approval request requires a user")
  var requests = ? store.load(nowMs)
  var pendingForUser = 0
  for request in requests:
    if request.userId == userId and request.status == apsPending:
      inc pendingForUser
  if pendingForUser >= MaxPendingPerUser:
    return err("too many pending approvals for this user")

  var id = ""
  var unique = false
  for _ in 0 ..< 10:
    id = newApprovalId()
    unique = true
    for request in requests:
      if request.id == id:
        unique = false
        break
    if unique:
      break
  if not unique:
    return err("could not generate a unique approval id")

  let request = ApprovalRequest(
    id:          id,
    userId:      userId,
    channel:     channel,
    toolName:    toolName,
    summary:     summary,
    createdAtMs: nowMs,
    expiresAtMs: nowMs + max(1_000'i64, ttlMs),
    status:      apsPending,
  )
  requests.add(request)
  ? store.save(requests)
  ok(request)

proc create*(store: ApprovalStore;
             userId: string;
             channel: string;
             toolName, summary: string;
             ttlMs: int64;
             nowMs = epochMs()): Result[ApprovalRequest, string] {.raises: [].} =
  store.withApprovalLock(proc(): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
    store.createLocked(userId, channel, toolName, summary, ttlMs, nowMs))

proc decideLocked(store: ApprovalStore;
                  id, userId: string;
                  approved: bool;
                  admin: bool;
                  nowMs: int64): Result[void, string] {.raises: [].} =
  var requests = ? store.load(nowMs)
  for i in 0 ..< requests.len:
    if requests[i].id != id:
      continue
    if not admin and requests[i].userId != userId:
      return err("approval belongs to another user")
    if requests[i].status != apsPending:
      return err("approval is already " & $requests[i].status)
    if nowMs >= requests[i].expiresAtMs:
      requests[i].status = apsExpired
      discard store.save(requests)
      return err("approval expired")
    requests[i].status = if approved: apsApproved else: apsDenied
    ? store.save(requests)
    return ok()
  err("approval not found: " & id)

proc decide*(store: ApprovalStore;
              id, userId: string;
              approved: bool;
              admin = false;
              nowMs = epochMs()): Result[void, string] {.raises: [].} =
  store.withApprovalLock(proc(): Result[void, string] {.gcsafe, raises: [].} =
    store.decideLocked(id, userId, approved, admin, nowMs))

proc status*(store: ApprovalStore;
             id: string;
             nowMs = epochMs()): Result[ApprovalStatus, string] {.raises: [].} =
  var requests = ? store.load(nowMs)
  for i in 0 ..< requests.len:
    if requests[i].id != id:
      continue
    if requests[i].status == apsPending and nowMs >= requests[i].expiresAtMs:
      return ok(apsExpired)
    return ok(requests[i].status)
  err("approval not found: " & id)

proc listPending*(store: ApprovalStore;
                  userId = "";
                  nowMs = epochMs()): Result[seq[ApprovalRequest], string] {.raises: [].} =
  let requests = ? store.load(nowMs)
  var pending: seq[ApprovalRequest]
  for request in requests:
    if request.status != apsPending:
      continue
    if userId.len > 0 and request.userId != userId:
      continue
    pending.add(request)
  ok(pending)

proc toApprovalPort*(store: ApprovalStore): ApprovalStorePort =
  ApprovalStorePort(
    create: proc(userId: string; channel: string; toolName, summary: string;
                 ttlMs: int64): Result[ApprovalRequest, string] {.gcsafe, raises: [].} =
      store.create(userId, channel, toolName, summary, ttlMs),
    decide: proc(id, userId: string; approved: bool;
                 admin: bool): Result[void, string] {.gcsafe, raises: [].} =
      store.decide(id, userId, approved, admin),
    status: proc(id: string): Result[ApprovalStatus, string] {.gcsafe, raises: [].} =
      store.status(id),
    listPending: proc(userId: string): Result[seq[ApprovalRequest], string] {.gcsafe, raises: [].} =
      store.listPending(userId),
  )
