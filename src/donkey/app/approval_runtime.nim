## approval_runtime — approval policy, request/wait loop and chat/CLI helpers.
##
## The application layer owns the decision flow. Channel adapters only call
## `tryHandleApprovalInput` with message text or inline callback data; the
## file-backed store is injected through `ApprovalStorePort`.

import ../config/environment
import std/[options, os, parseutils, strutils]
import chronos
import chronos/asyncsync
import ../core/log
import ../core/pipeops
import ../core/security/approval
import ../core/types
import ../domain/message
import ../domain/text_format
import ../ports/approval

export options

type
  ApprovalService* = ref object
    store:     ApprovalStorePort
    tools:     seq[string]
    timeoutMs: int64
    standing:  StandingApprovalPort   ## approvals that stand (E5.2)

var gApprovalService* {.threadvar.}: ApprovalService
  ## Configured at startup on the main thread, which then runs the daemon loop
  ## where turns read it: thread-local to that loop, gcsafe without a cast.

func defaultApprovalTools*(): seq[string] =
  ## High-risk tools that ask for confirmation by default. Set
  ## DONKEY_APPROVAL_TOOLS=none to disable the gate.
  @["bash", "edit_file", "fs_write", "fs_mkdir", "fs_copy", "fs_move",
    "fs_remove", "text_replace", "cp", "mv", "rm", "mkdir",
    "archive_extract", "archive_create", "execute_code",
    "editor_read_file"]   ## E10.5: what the person has open in their editor

proc parseApprovalTools*(raw: string): seq[string] =
  let value = raw.strip.toLowerAscii()
  if value.len == 0:
    return defaultApprovalTools()
  if value in ["none", "off", "disabled"]:
    return @[]
  for part in value.split(','):
    let item = part.strip
    if item.len > 0 and item notin result:
      result.add(item)

proc configureApprovalService*(store: ApprovalStorePort;
                               tools: seq[string];
                               timeoutSec = 300.0;
                               standing = StandingApprovalPort()) =
  gApprovalService = ApprovalService(
    store:     store,
    tools:     tools,
    timeoutMs: int64(max(10.0, timeoutSec) * 1000.0),
    standing:  standing,
  )

proc standingApprovals*(service: ApprovalService): StandingApprovalPort =
  if service.isNil: StandingApprovalPort() else: service.standing

proc configureApprovalServiceFromEnv*(store: ApprovalStorePort; env: Environment;
                                      standing = StandingApprovalPort()) =
  var timeoutSec = 300.0
  let rawTimeout = env.stripped("DONKEY_APPROVAL_TIMEOUT_SEC")
  if rawTimeout.len > 0:
    var parsed: float
    let consumed = parseutils.parseFloat(rawTimeout, parsed)
    if consumed > 0 and consumed == rawTimeout.len:
      timeoutSec = parsed
  configureApprovalService(store, parseApprovalTools(env.get("DONKEY_APPROVAL_TOOLS")),
                           timeoutSec, standing)

proc resetApprovalService*() =
  gApprovalService = nil

proc currentApprovalService*(): ApprovalService {.gcsafe.} =
  gApprovalService

proc requiresApproval*(toolName: string): bool =
  gApprovalService != nil and
    ("*" in gApprovalService.tools or toolName in gApprovalService.tools)

proc requiresApproval*(service: ApprovalService; toolName: string): bool =
  service != nil and ("*" in service.tools or toolName in service.tools)

func approvalInputSummary*(inputJson: string): string =
  ## Full JSON input for an MCP/external tool; empty means it is too large to
  ## display safely for approval.
  const MaxApprovalSummaryChars = 1500
  result = inputJson.replace("\r\n", "\\n")
                    .replace("\n", "\\n")
                    .replace("\r", "\\r")
                    .strip
  if result.len == 0:
    result = "(sem detalhes)"
  if result.len > MaxApprovalSummaryChars:
    result = ""

func approvalMessage*(request: ApprovalRequest): string =
  "⚠️ *Aprovação necessária*\n\n" &
  "*Ferramenta:* `" & codeSpanText(request.toolName) & "`\n" &
  "*ID:* `" & codeSpanText(request.id) & "`\n\n" &
  escapeMarkdownInline(request.summary) & "\n\n" &
  "Use `/approve " & request.id & "` ou `/deny " & request.id & "`.\n" &
  "Expira em " & $((request.expiresAtMs - request.createdAtMs) div 1000) & "s."

func approvalKeyboard*(request: ApprovalRequest): seq[seq[(string, string)]] =
  @[@[
    ("✅ Aprovar", approvalCallbackData(request.id, true)),
    ("❌ Negar", approvalCallbackData(request.id, false)),
  ]]

proc listPendingText*(userId = ""): string {.gcsafe.} =
  let service = currentApprovalService()
  if service == nil:
    return "Aprovações não configuradas."
  let pending = service.store.listPending(userId)
  if pending.isErr:
    return "Erro ao ler aprovações: " & pending.error
  if pending.get().len == 0:
    return "Nenhuma aprovação pendente."
  result = "🗳️ *Aprovações pendentes*\n"
  for request in pending.get():
    result.add("\n`" & codeSpanText(request.id) & "` — `" &
               codeSpanText(request.toolName) & "` — " &
               escapeMarkdownInline(request.summary))
  result.add("\n\nUse `/approve <id>` ou `/deny <id>`.")

proc cancelPendingApprovals*(userId: UserId) {.gcsafe, raises: [].} =
  ## Denies every pending request for a user. Used by /stop and /new so an
  ## approval cannot revive a turn that the user just aborted.
  let service = currentApprovalService()
  if service == nil:
    return
  let pending = service.store.listPending($userId)
  if pending.isOk:
    for request in pending.get():
      discard service.store.decide(request.id, $userId, false, admin = true)

proc awaitDecision(service: ApprovalService; request: ApprovalRequest;
                   userId: UserId; log: Logger;
                   shouldStop: proc(): bool {.gcsafe, raises: [].}):
                   Future[ApprovalDecision] {.async.} =
  ## Polls the store until the request is decided, expires or the turn stops.
  let deadline = epochMs() + service.timeoutMs
  while epochMs() < deadline:
    if shouldStop != nil and shouldStop():
      log.info("approval cancelled by stop id=" & request.id)
      discard service.store.decide(request.id, $userId, approved = false,
                                   admin = true)
      return adDenied
    let status = service.store.status(request.id)
    if status.isOk:
      case status.get()
      of apsApproved:
        log.info("approval approved id=" & request.id)
        return adApproved
      of apsDenied:
        log.info("approval denied id=" & request.id)
        return adDenied
      of apsExpired:
        return adTimeout
      of apsPending:
        discard
    elif status.error.contains("not found"):
      return adTimeout
    else:
      log.warn("approval status failed: " & status.error)
    await sleepAsync(chronos.milliseconds(500))

  discard service.store.decide(request.id, "", false, admin = true)
  log.warn("approval timed out id=" & request.id)
  return adTimeout


proc requestAndWait*(service: ApprovalService;
                     userId: UserId;
                     channel: ChannelKind;
                     outbox: AsyncQueue[OutboundMessage];
                     toolName, summary: string;
                     log: Logger;
                     shouldStop: proc(): bool {.gcsafe, raises: [].} = nil;
                     bridgeToken: uint64 = 0):
                     Future[ApprovalDecision] {.async.} =
  ## Creates a pending request, notifies the user and polls until a decision
  ## or timeout. Only channel adapters and `ctl` can decide; the requester can
  ## approve through `/approve` or an inline callback.
  if service == nil or not requiresApproval(service, toolName):
    return adApproved
  if shouldStop != nil and shouldStop():
    return adDenied
  let created = service.store.create(
    $userId, $channel, toolName, summary, service.timeoutMs)
  if created.isErr:
    log.warn("approval create failed: " & created.error)
    return adDenied
  let request = created.get()
  log.info("approval requested id=" & request.id & " tool=" & toolName &
           " user=" & $userId)
  await outbox.put(OutboundMessage(
    userId: userId,
    channel: channel,
    text: approvalMessage(request),
    keyboard: approvalKeyboard(request),
    bridgeToken: bridgeToken,   ## an editor's turn: asked in its stream (E10.4)
  ))

  return await awaitDecision(service, request, userId, log, shouldStop)

func standingApprovalMessage(title: string; request: ApprovalRequest): string =
  "⚠️ *Aprovação necessária: " & escapeMarkdownInline(title) & "*\n\n" &
  escapeMarkdownInline(request.summary) & "\n\n" &
  "*Sempre* deixa de perguntar para este caso; revogue com " &
  "`donkey ctl approval standing revoke`.\n" &
  "Expira em " & $((request.expiresAtMs - request.createdAtMs) div 1000) & "s."

func standingApprovalKeyboard(request: ApprovalRequest): seq[seq[(string, string)]] =
  @[@[
    ("✅ Desta vez", approvalCallbackData(request.id, true)),
    ("♾️ Sempre", approvalAlwaysCallbackData(request.id)),
    ("❌ Negar", approvalCallbackData(request.id, false)),
  ]]

proc requestStandingApproval*(service: ApprovalService;
                              userId: UserId;
                              channel: ChannelKind;
                              outbox: AsyncQueue[OutboundMessage];
                              key, title, summary: string;
                              log: Logger;
                              shouldStop: proc(): bool {.gcsafe, raises: [].} = nil):
                              Future[ApprovalDecision] {.async.} =
  ## Always asks, whatever the tool list, unless an approval stands for this
  ## person and `key`: once, always (it then stands) or deny. Without an
  ## approval service there is nobody to ask, so it is denied.
  if service == nil:
    return adDenied
  if service.standing.hasStanding and service.standing.has($userId, key):
    log.info("approval stands user=" & $userId & " key=" & key)
    return adApproved
  let created = service.store.create($userId, $channel, key, summary, service.timeoutMs)
  if created.isErr:
    log.warn("approval create failed: " & created.error)
    return adDenied
  let request = created.get()
  log.info("approval requested id=" & request.id & " key=" & key & " user=" & $userId)
  await outbox.put(OutboundMessage(userId: userId, channel: channel,
    text: standingApprovalMessage(title, request),
    keyboard: standingApprovalKeyboard(request)))
  return await awaitDecision(service, request, userId, log, shouldStop)

proc tryHandleApprovalInput*(userId: UserId; text: string): Option[string] {.gcsafe.} =
  ## Handles `/approve`, `/deny`, `/poll` and inline callback data. Returns
  ## none when the input is not an approval command.
  let service = currentApprovalService()
  if service == nil:
    return none(string)
  let value = text.strip
  if isPollCommand(value):
    return some(listPendingText($userId))
  let command = parseApprovalCommand(value)
  if command.isSome:
    let (id, approved) = command.get
    let res = service.store.decide(id, $userId, approved, admin = false)
    if res.isErr:
      return some("Erro: " & res.error)
    return some(if approved: "✅ Aprovado." else: "❌ Negado.")
  let always = parseAlwaysCallback(value)
  if always.isSome:
    let id = always.get
    let res = service.store.decide(id, $userId, true, admin = false)
    if res.isErr:
      return some("Erro: " & res.error)
    if not service.standing.hasStanding or service.store.lookup == nil:
      return some("✅ Aprovado desta vez; aprovações permanentes não estão disponíveis.")
    let request = service.store.lookup(id).valueOr:
      return some("✅ Aprovado desta vez; não foi possível guardar para sempre: " & error)
    service.standing.grant($userId, request.toolName).isOkOr:
      return some("✅ Aprovado desta vez; não foi possível guardar para sempre: " & error)
    return some("✅ Aprovado, e não pergunto mais neste caso.")
  let callback = parseApprovalCallback(value)
  if callback.isSome:
    let (id, approved) = callback.get
    let res = service.store.decide(id, $userId, approved, admin = false)
    if res.isErr:
      return some("Erro: " & res.error)
    return some(if approved: "✅ Aprovado." else: "❌ Negado.")
  none(string)
