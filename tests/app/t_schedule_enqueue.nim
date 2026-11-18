## Schedule enqueue (automation US-005) — the ingress half of the scheduler.
##
## A schedule firing must become one `tkSchedule` task in the user's inbox.
## Unlike `ensureSessionTask` (void), the enqueue path is fallible: an empty
## user id, a revoked user or a DM policy denial is an `Err` so the runtime can
## persist the run as `failed`, never `sent`.
##
## Where the fired instant lives: `AgentMessage` has no timestamp field, so the
## adapter appends a provenance line to the task **payload**:
##
##   <spec.payload>\n\n[schedule <id> fired at <instantMs> ms]
##
## The payload is what the orchestrator turns into the user turn, so the instant
## is visible both to the model and to any caller holding the queued message.
##
## No real clock, no provider and no daemon loop: the instant is injected and
## the orchestrator actor is only spawned, never driven.

import std/[os, strutils, tables, unittest]
import chronos/asyncsync
import results
import donkey/app/session_ingress
import donkey/adapters/memory/md_file
import donkey/app/session_manager
import donkey/config/types
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/dm_policy
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/automation/schedule_pure
import donkey/domain/message
import donkey/ports/http
import donkey/ports/provider
import donkey/ports/tool

const
  UserIdOk = "u-schedule"
  FiredAtMs = 1_700_000_123_000'i64

func makeSpec(
  userId = UserIdOk;
  channel = "telegram";
  payload = "revise o backlog do sprint";
  id = "sched-1";
): ScheduleSpec =
  ScheduleSpec(
    id: id,
    cronExpr: "0 9 * * *",
    tzOffsetMinutes: 0,
    userId: userId,
    channel: channel,
    payload: payload,
    catchUp: scSkip,
    enabled: true,
    createdAtMs: 0,
  )

proc makeServices(
  baseDir: string;
  outbox: AsyncQueue[OutboundMessage];
  isRevoked: proc(u: UserId): bool {.gcsafe.} = nil;
  isDmAllowed: proc(u: UserId): bool {.gcsafe.} = nil;
  dmPolicy: DmPolicy = DmPolicyOpen;
): SessionIngressServices =
  let memory = MdFileAdapter(paddocksDir: baseDir / "paddocks")
  let stubComplete: CompleteFn =
    proc(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(text: "ok"))
  buildSessionIngressServices(
    memory = memory.toRuntimePort(),
    cfg = DonkeyConfig(defaultProvider: "openai", defaultModel: "gpt-4o"),
    completeFn = stubComplete,
    streamFn = nil,
    toolClients = @[],
    tools = @[],
    globalOutbox = outbox,
    log = newLogger("test-schedule-enqueue"),
    sandboxMode = smNone,
    sandboxRuntimeCmd = "",
    sandboxImage = "",
    typingFn = nil,
    searchFn = nil,
    isRevoked = isRevoked,
    isDmAllowed = isDmAllowed,
    dmPolicy = dmPolicy,
    http = HttpRuntimePort(),
  )

proc tempBase(tag: string): string =
  result = getTempDir() / ("donkey_sched_enqueue_" & tag & "_" & $nowMs())
  removeDir(result)

proc primeSession(sm: var SessionManager; services: SessionIngressServices;
                  msgSeq: var int; uid: string) =
  ## Brings the user's session runtime up with a throwaway turn.
  ##
  ## Without a live session `startSessionIngress` spawns an actor, and that
  ## actor consumes the just-queued task synchronously (the stub provider never
  ## suspends) before the test can inspect it. With the runtime already alive
  ## the scheduled ingress only appends to the inbox; no event loop runs here,
  ## so the task stays queued.
  let msg = InboundMessage(
    userId: UserId(uid),
    channel: ckTelegram,
    channelId: "42",
    text: "prime the session",
  )
  discard startSessionIngress(sm, msg, services, msgSeq)

suite "schedule enqueue — success path":

  test "a valid spec enqueues exactly one tkSchedule task":
    let base = tempBase("ok")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let spec = makeSpec()
    primeSession(sm, services, msgSeq, UserIdOk)
    check msgSeq == 1

    let res = enqueueScheduledTask(sm, services, msgSeq, spec, FiredAtMs)

    check res.isOk
    let uid = UserId(UserIdOk)
    check sm.hasSession(uid)
    var entry = sm.entries[UserIdOk]
    check entry.inbox.len == 1
    let task = entry.inbox.popFirstNoWait()
    check task.kind == amkTask
    check task.taskKind == tkSchedule
    check task.userId == UserIdOk
    check task.channel == ckTelegram
    ## The spec's own payload reaches the turn unchanged (prefixed prose)...
    check task.payload.startsWith(spec.payload)
    ## ...and the fired instant is recorded in the payload, not dropped.
    check ("[schedule sched-1 fired at " & $FiredAtMs & " ms]") in task.payload
    ## Exactly one ingress context was consumed.
    check msgSeq == 2

  test "the recorded channel follows the spec, not a session default":
    let base = tempBase("channel")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let spec = makeSpec(userId = "u-slack", channel = "slack")
    primeSession(sm, services, msgSeq, "u-slack")
    check msgSeq == 1

    check enqueueScheduledTask(sm, services, msgSeq, spec, FiredAtMs).isOk

    var entry = sm.entries["u-slack"]
    check entry.inbox.len == 1
    let task = entry.inbox.popFirstNoWait()
    check task.taskKind == tkSchedule
    check task.channel == ckSlack
    check task.userId == "u-slack"

  test "the ScheduleEnqueueFn adapter reports Ok and forwards the instant":
    let base = tempBase("adapter")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let spec = makeSpec(id = "sched-adapter")
    primeSession(sm, services, msgSeq, UserIdOk)
    let enqueue = scheduleEnqueueFn(addr sm, services, addr msgSeq)

    let res = enqueue(spec, FiredAtMs)

    check res.isOk
    var entry = sm.entries[UserIdOk]
    check entry.inbox.len == 1
    let task = entry.inbox.popFirstNoWait()
    check task.taskKind == tkSchedule
    check ("[schedule sched-adapter fired at " & $FiredAtMs & " ms]") in
      task.payload

suite "schedule enqueue — dropped firings are errors":

  test "empty user id is Err and nothing is enqueued":
    let base = tempBase("empty")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0

    let res = enqueueScheduledTask(
      sm, services, msgSeq, makeSpec(userId = ""), FiredAtMs)

    check res.isErr
    check res.error == "scheduled task dropped: empty user id"
    check msgSeq == 0
    check sm.entries.len == 0

  test "whitespace-only user id is Err and nothing is enqueued":
    let base = tempBase("blank")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0

    let res = enqueueScheduledTask(
      sm, services, msgSeq, makeSpec(userId = "   "), FiredAtMs)

    check res.isErr
    check msgSeq == 0
    check sm.entries.len == 0

  test "revoked user is Err and nothing is enqueued":
    let base = tempBase("revoked")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(
      base, outbox,
      isRevoked = proc(u: UserId): bool {.gcsafe.} = u == UserId(UserIdOk),
    )
    var sm: SessionManager
    sm.init()
    var msgSeq = 0

    let res = enqueueScheduledTask(sm, services, msgSeq, makeSpec(), FiredAtMs)

    check res.isErr
    check res.error == "scheduled task dropped: user revoked"
    check msgSeq == 0
    check sm.entries.len == 0

  test "DM policy denial on the spec channel is Err, with no unauthorized reply":
    let base = tempBase("denied")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(
      base, outbox,
      isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false,
      dmPolicy = DmPolicyAllowlist,
    )
    var sm: SessionManager
    sm.init()
    var msgSeq = 0

    let res = enqueueScheduledTask(sm, services, msgSeq, makeSpec(), FiredAtMs)

    check res.isErr
    check res.error == "scheduled task dropped: denied or revoked"
    check msgSeq == 0
    check sm.entries.len == 0
    ## A background task must not emit the "não autorizado" user-facing reply.
    check outbox.len == 0

  test "the ScheduleEnqueueFn adapter propagates the denial as Err":
    let base = tempBase("adapter-denied")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(
      base, outbox,
      isRevoked = proc(u: UserId): bool {.gcsafe.} = true,
    )
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let enqueue = scheduleEnqueueFn(addr sm, services, addr msgSeq)

    let res = enqueue(makeSpec(), FiredAtMs)

    check res.isErr
    check res.error == "scheduled task dropped: user revoked"
    check msgSeq == 0
    check sm.entries.len == 0

  test "unknown channel is Err and nothing is enqueued":
    let base = tempBase("channel-unknown")
    defer: removeDir(base)
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeServices(base, outbox)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0

    let res = enqueueScheduledTask(
      sm, services, msgSeq, makeSpec(channel = "carrier-pigeon"), FiredAtMs)

    check res.isErr
    check msgSeq == 0
    check sm.entries.len == 0

suite "TaskKind — tkSchedule is additive":

  test "tkSchedule does not move the existing ordinals":
    ## `TaskKind` ordinals are part of the message contract: the new member is
    ## appended after `tkHeartbeat`.
    check ord(tkUserMsg) == 0
    check ord(tkHeartbeat) == 15
    check ord(tkSchedule) == ord(tkHeartbeat) + 1

  test "tkSchedule stringifies by name":
    check $tkSchedule == "tkSchedule"
