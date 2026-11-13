## approval_runtime — approval policy, request/wait loop and chat/CLI helpers.
##
## The application layer owns the decision flow. Channel adapters only call
## `tryHandleApprovalInput` with message text or inline callback data; the
## file-backed store is injected through `ApprovalStorePort`.

import std/[options, os, parseutils, strutils]
import chronos
import chronos/asyncsync
import ../core/log
import ../core/pipeops
import ../core/security/approval
import ../core/types
import ../domain/message
import ../ports/approval

export options

type
  ApprovalService* = ref object
    store:     ApprovalStorePort
    tools:     seq[string]
    timeoutMs: int64

var gApprovalService*: ApprovalService

func defaultApprovalTools*(): seq[string] =
  ## High-risk tools that ask for confirmation by default. Set
  ## DONKEY_APPROVAL_TOOLS=none to disable the gate.
  @["bash", "edit_file", "fs_write", "fs_mkdir", "fs_copy", "fs_move",
    "fs_remove", "text_replace", "cp", "mv", "rm", "mkdir",
    "archive_extract", "archive_create", "execute_code"]

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
                               timeoutSec = 300.0) =
  gApprovalService = ApprovalService(
    store:     store,
    tools:     tools,
    timeoutMs: int64(max(10.0, timeoutSec) * 1000.0),
  )

proc configureApprovalServiceFromEnv*(store: ApprovalStorePort) =
  var timeoutSec = 300.0
  let rawTimeout = getEnv("DONKEY_APPROVAL_TIMEOUT_SEC").strip()
  if rawTimeout.len > 0:
    var parsed: float
    let consumed = parseutils.parseFloat(rawTimeout, parsed)
    if consumed > 0 and consumed == rawTimeout.len:
      timeoutSec = parsed
  configureApprovalService(store, parseApprovalTools(getEnv("DONKEY_APPROVAL_TOOLS")),
                           timeoutSec)

proc resetApprovalService*() =
  gApprovalService = nil

proc currentApprovalService*(): ApprovalService {.gcsafe.} =
  {.cast(gcsafe).}:
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
  "*Ferramenta:* `" & request.toolName & "`\n" &
  "*ID:* `" & request.id & "`\n\n" &
  request.summary & "\n\n" &
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
    result.add("\n`" & request.id & "` — `" & request.toolName & "` — " &
               request.summary)
  result.add("\n\nUse `/approve <id>` ou `/deny <id>`.")

proc requestAndWait*(service: ApprovalService;
                     userId: UserId;
                     channel: ChannelKind;
                     outbox: AsyncQueue[OutboundMessage];
                     toolName, summary: string;
                     log: Logger): Future[ApprovalDecision] {.async.} =
  ## Creates a pending request, notifies the user and polls until a decision
  ## or timeout. Only channel adapters and `ctl` can decide; the requester can
  ## approve through `/approve` or an inline callback.
  if service == nil or not requiresApproval(service, toolName):
    return adApproved
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
  ))

  let deadline = epochMs() + service.timeoutMs
  while epochMs() < deadline:
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
  adTimeout

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
  let callback = parseApprovalCallback(value)
  if callback.isSome:
    let (id, approved) = callback.get
    let res = service.store.decide(id, $userId, approved, admin = false)
    if res.isErr:
      return some("Erro: " & res.error)
    return some(if approved: "✅ Aprovado." else: "❌ Negado.")
  none(string)
