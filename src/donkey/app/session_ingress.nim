## session_ingress.nim — Session ingress planning and lifecycle orchestration.
##
## Coordinates session planning, context building, task/inbox message routing,
## and orchestrator actor launching for inbound messages.
##
## Strict hexagonal architecture: no direct imports from adapters/.

import chronos
import chronos/asyncsync
import std/strutils
import ../config/types
import ../core/types
import ../core/log
import ../core/pipeops
import ../core/session/session_ingress as coreSessionIngress
import ../core/providers/smart_routing
import ../core/security/dm_policy
import ../domain/agent_message
import ../domain/automation/schedule_pure
import ../domain/message
import ../ports/memory
import ../ports/reminders
import ../ports/process
import ../ports/attachment_store
import ../ports/access
import ../ports/provider
import ../ports/runtime_state
import ../ports/tool
import ../ports/http
import ../ports/fs
import ./automation_runtime
import ./session_manager
import ./session_state
import ../ports/subagent_workspace
import ./session_bootstrap
import ./orchestrator
import ./sandbox

export coreSessionIngress

type
  EnsureSessionPlan* = object
    uid*:                 string
    decision*:            SessionIngressDecision
    injectRecentContext*: bool
    oldInbox*:            AsyncQueue[AgentMessage]
    oldAskInbox*:         AsyncQueue[string]
    entry*:               ptr SessionEntry

  SessionIngressContext* = object
    plan*:  EnsureSessionPlan
    msgId*: string

  SessionIngressServices* = object
    cfg*:                        DonkeyConfig
    memory*:                     MemoryRuntimePort
    reminders*:                  ReminderPort
    process*:                    ProcessRuntimePort
    attachments*:                AttachmentStorePort
    completeFn*:                 CompleteFn
    streamFactory*:                   StreamFactory
    toolClients*:                seq[ToolRuntimePort]
    tools*:                      seq[ToolDescription]
    globalOutbox*:               AsyncQueue[OutboundMessage]
    log*:                        Logger
    sandboxMode*:                SandboxMode
    sandboxRuntimeCmd*:          string
    sandboxImage*:               string
    typingFn*:                   TypingFn
    searchFn*:                   SearchFn
    http*:                       HttpRuntimePort
    fs*:                         FsRuntimePort
    providerRuntimeBuilder*:     ProviderRuntimeBuilder
    skillRuntimeBuilder*:        SkillRuntimeBuilder
    skillRuntimePolicyResolver*: SkillRuntimePolicyResolver
    access*:                     AccessPort
    dmPolicy*:                   DmPolicy
    routeRecordHook*:            proc(selection: ProviderSelection) {.gcsafe, raises: [].}
    routeResultHook*:            proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe, raises: [].}
    routeFeedbackHook*:          proc(): seq[RouteFeedback] {.gcsafe, raises: [].}
    routeCostHook*:              proc(): seq[RouteCostHint] {.gcsafe, raises: [].}
    routeProviderCooldownHook*:  proc(): seq[ProviderCooldown] {.gcsafe, raises: [].}
    subagentWorkspace*:          SubagentWorkspacePort

func buildSkillRuntimePolicy*(cfg: DonkeyConfig;
                             skillName: string): SkillRuntimePolicy =
  ## Builds a skill runtime policy with network hosts allowed for this skill.
  SkillRuntimePolicy(allowNetHosts: cfg.effectiveSkillAllowNetHosts(skillName))

func buildSkillRuntimePolicyResolver*(cfg: DonkeyConfig): SkillRuntimePolicyResolver =
  ## Returns a resolver closure that resolves runtime policy per skill name.
  result = proc(skillName: string): SkillRuntimePolicy =
    buildSkillRuntimePolicy(cfg, skillName)

func toolCatalogSignature*(tools: seq[ToolDescription];
                           providerLabel: string;
                           paddockDir: string;
                           skillPrompt = ""): SessionRuntimeSignature =
  ## Computes a cache signature for the current tool catalog and provider.
  var signature = newStringOfCap(256)
  signature.add(providerLabel)
  signature.add('\n')
  signature.add(paddockDir)
  signature.add('\n')
  signature.add(skillPrompt)
  signature.add('\n')
  for tool in tools:
    signature.add(tool.name)
    signature.add('\t')
    signature.add(tool.description)
    signature.add('\t')
    signature.add(tool.schemaJson)
    signature.add('\n')
  result = SessionRuntimeSignature(signature)

proc buildEnsureSessionPlan*(sm: var SessionManager;
                             userId: UserId;
                             toolCatalogSignature: SessionRuntimeSignature;
                             persist: bool = true;
                             recordActivity: bool = true;
                             answerableAsk: bool = true): EnsureSessionPlan =
  ## Evaluates session ingress state and decides whether to reuse, rebuild, or create a session.
  ## `persist = false` lets the ingress path batch the registry write after
  ## channel bookkeeping.
  const ColdSessionThresholdMs = 60'i64 * 60 * 1000
  let ingressState = sm.snapshot(userId)
  let decision = decideSessionIngress(SessionIngressRequest(
    userId: userId,
    state: ingressState,
    nextSignature: toolCatalogSignature,
  ), answerableAsk = answerableAsk)
  let now = nowMs()
  let wasCold =
    ingressState.lastInboundAtMs > 0 and
    now - ingressState.lastInboundAtMs >= ColdSessionThresholdMs
  let lease = sm.applyIngressDecision(userId, decision, toolCatalogSignature)
  ## A scheduled or heartbeat task is not the user talking: recording it as
  ## inbound activity would show the firing time as "last message" on the
  ## dashboard and skew the cold-session decision.
  if recordActivity:
    lease.entry[].lastInboundAtMs = now
    lease.entry[].lastInboundEpochMs = epochMs()
  if persist:
    sm.persistSession(userId)
  EnsureSessionPlan(
    uid: $userId,
    decision: decision,
    injectRecentContext: decision.startsNewSession or decision.rebuildsSessionRuntime or wasCold,
    oldInbox: lease.oldInbox,
    oldAskInbox: lease.oldAskInbox,
    entry: lease.entry,
  )

proc buildSessionIngressContext*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 toolCatalogSignature: SessionRuntimeSignature;
                                 msgSeq: var int;
                                 recordActivity: bool = true;
                                 answerableAsk: bool = true): SessionIngressContext =
  ## Builds ingress plan, records the channel, and persists the session exactly
  ## once per inbound message.
  result.plan = sm.buildEnsureSessionPlan(msg.userId, toolCatalogSignature,
                                          persist = false,
                                          recordActivity = recordActivity,
                                          answerableAsk = answerableAsk)
  inc msgSeq
  result.msgId = $msg.userId & "-" & $msgSeq
  if result.plan.decision.shouldRecordChannel:
    sm.recordChannel(msg.userId, msg.channel, msg.channelId, persist = false)
  sm.persistSession(msg.userId)

func buildSessionIngressServices*(memory: MemoryRuntimePort;
                                  cfg: DonkeyConfig;
                                  completeFn: CompleteFn;
                                  streamFactory: StreamFactory;
                                  toolClients: seq[ToolRuntimePort];
                                  tools: seq[ToolDescription];
                                  globalOutbox: AsyncQueue[OutboundMessage];
                                  log: Logger;
                                  sandboxMode: SandboxMode;
                                  sandboxRuntimeCmd: string;
                                  sandboxImage: string;
                                  typingFn: TypingFn;
                                  searchFn: SearchFn;
                                  access: AccessPort;
                                  dmPolicy: DmPolicy = DmPolicyOpen;
                                  http: HttpRuntimePort;
                                  providerRuntimeBuilder: ProviderRuntimeBuilder = nil;
                                  skillRuntimeBuilder: SkillRuntimeBuilder = nil;
                                  skillRuntimePolicyResolver: SkillRuntimePolicyResolver = nil;
                                  routeRecordHook: proc(selection: ProviderSelection) {.gcsafe, raises: [].} = nil;
                                  routeResultHook: proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe, raises: [].} = nil;
                                  routeFeedbackHook: proc(): seq[RouteFeedback] {.gcsafe, raises: [].} = nil;
                                  routeCostHook: proc(): seq[RouteCostHint] {.gcsafe, raises: [].} = nil;
                                  routeProviderCooldownHook: proc(): seq[ProviderCooldown] {.gcsafe, raises: [].} = nil;
                                  subagentWorkspace: SubagentWorkspacePort = SubagentWorkspacePort();
                                  fs: FsRuntimePort = unavailableFs();
                                  reminders: ReminderPort = ReminderPort();
                                  process: ProcessRuntimePort = unavailableProcess();
                                  attachments: AttachmentStorePort = unavailableAttachments()): SessionIngressServices =
  ## Constructs SessionIngressServices.
  SessionIngressServices(
    cfg: cfg,
    memory: memory,
    reminders: reminders,
    process: process,
    attachments: attachments,
    completeFn: completeFn,
    streamFactory: streamFactory,
    toolClients: toolClients,
    tools: tools,
    globalOutbox: globalOutbox,
    log: log,
    sandboxMode: sandboxMode,
    sandboxRuntimeCmd: sandboxRuntimeCmd,
    sandboxImage: sandboxImage,
    typingFn: typingFn,
    searchFn: searchFn,
    http: http,
    fs: fs,
    providerRuntimeBuilder: providerRuntimeBuilder,
    skillRuntimeBuilder: skillRuntimeBuilder,
    skillRuntimePolicyResolver: skillRuntimePolicyResolver,
    access: access,
    dmPolicy: dmPolicy,
    routeRecordHook: routeRecordHook,
    routeResultHook: routeResultHook,
    routeFeedbackHook: routeFeedbackHook,
    routeCostHook: routeCostHook,
    routeProviderCooldownHook: routeProviderCooldownHook,
    subagentWorkspace: subagentWorkspace,
  )

func withTypingFn*(typingFn: TypingFn;
                   services: SessionIngressServices): SessionIngressServices =
  ## Returns services with typingFn replaced.
  result = services
  result.typingFn = typingFn

proc startSessionOrchestrator*(plan: EnsureSessionPlan;
                               cfg: DonkeyConfig;
                               memory: MemoryRuntimePort;
                               streamFactory: StreamFactory;
                               bootstrap: SessionBootstrap;
                               globalOutbox: AsyncQueue[OutboundMessage];
                               log: Logger;
                               sandboxMode: SandboxMode;
                               sandboxRuntimeCmd: string;
                               sandboxImage: string;
                               typingFn: TypingFn;
                               searchFn: SearchFn;
                               http: HttpRuntimePort;
                               fs: FsRuntimePort = unavailableFs();
                               reminders: ReminderPort = ReminderPort();
                               process: ProcessRuntimePort = unavailableProcess();
                               attachments: AttachmentStorePort = unavailableAttachments()) {.gcsafe.} =
  ## Spawns an orchestrator actor if the ingress decision requires starting a session runtime.
  if not plan.decision.startsSessionRuntime:
    return
  let state = newSessionState()
  if plan.decision.rebuildsSessionRuntime and not plan.oldAskInbox.isNil:
    plan.oldAskInbox.addLastNoWait("__DONKEY_ASK_CANCELLED__")
  if plan.decision.rebuildsSessionRuntime and not plan.oldInbox.isNil:
    plan.oldInbox.addLastNoWait(newCancelMsg())
  asyncSpawn runOrchestrator(plan.entry[].inbox, plan.entry, globalOutbox, memory,
                             bootstrap.completeFn,
                             http, streamFactory,
                             bootstrap.clients, bootstrap.tools,
                             bootstrap.paddockDir, state,
                             typingFn, searchFn, log.child("orch"), bootstrap.providerLabel,
                             bootstrap.skillPrompt,
                             sandboxMode, sandboxRuntimeCmd, sandboxImage,
                             cfg.webAllowlist, cfg.toolWebPolicy,
                             errorExplainFn = bootstrap.errorExplainFn,
                             asyncCompleteFn = bootstrap.asyncCompleteFn,
                             subagentWorkspace = bootstrap.subagentWorkspace,
                             fs = fs, env = cfg.env, reminders = reminders,
                             process = process, attachments = attachments)

func sessionTaskMsg(msg: InboundMessage; msgId: string;
                     recentContext = ""): AgentMessage =
  ## Session task carrying the inbound message, including the API turn
  ## generation: every reply of this turn is correlated to it downstream.
  result = buildSessionTaskMsg(msg, msgId, recentContext)
  result.bridgeToken = msg.bridgeToken

proc enqueueSessionMessage*(entry: var SessionEntry;
                            msg: InboundMessage;
                            msgId: string;
                            target: SessionIngressTarget) =
  ## Enqueues an inbound message to the appropriate queue (askInbox or inbox).
  case target
  of sitAskInbox:
    entry.awaitingAsk = false
    entry.askInbox.addLastNoWait(msg.text)
  of sitActorInbox:
    entry.inbox.addLastNoWait(sessionTaskMsg(msg, msgId))

proc startSessionIngress*(sm: var SessionManager;
                          msg: InboundMessage;
                          services: SessionIngressServices;
                          msgSeq: var int;
                          taskKind: TaskKind = tkUserMsg;
                          taskPayload: string = ""): SessionIngressContext {.gcsafe.} =
  ## Full session ingress flow: builds bootstrap, plan, context, enqueues message, and spawns orchestrator.
  if ($msg.userId).len == 0:
    ## Identity resolution failed (e.g. unreadable identities.tsv); deny.
    return
  if services.dmPolicy != DmPolicyOpen:
    let allowed =
      services.access.dmAllowed(msg.userId)
    if not allowed:
      if taskKind == tkUserMsg and services.globalOutbox != nil:
        services.globalOutbox.putNoWait(OutboundMessage(
          userId: msg.userId,
          channel: msg.channel,
          replyTo: sessionReplyTo(msg),
          text: "Acesso não autorizado. Peça ao administrador para incluir seu usuário na allowlist.",
        ))
      return

  let routingHook: RoutingTelemetryHook =
    proc(selection: ProviderSelection;
         prefs: SmartRoutingPrefs;
         req: CompletionRequest) {.gcsafe, raises: [].} =
      if prefs.usesSmartRouting:
        if services.routeRecordHook != nil:
          services.routeRecordHook(selection)
        var hasImage = false
        for turn in req.messages:
          if turn.imageUrl.len > 0:
            hasImage = true
            break
        services.log.info("[route] " & $msg.userId & " -> " &
                          selection.formatSelection &
                          " | thinking=" & prefs.thinking &
                          " tools=" & $req.tools.len &
                          " image=" & $hasImage &
                          " chars=" & $requestApproxChars(req))
  let bootstrap = buildSessionBootstrap(
    services.memory, msg.userId, services.completeFn, services.providerRuntimeBuilder,
    normalizeProviderDefaults(services.cfg.defaultProvider, services.cfg.defaultModel),
    services.skillRuntimeBuilder, services.skillRuntimePolicyResolver,
    services.toolClients, services.tools,
    routingHook, services.routeResultHook, services.routeFeedbackHook,
    services.routeCostHook, services.routeProviderCooldownHook,
    subagentWorkspace = services.subagentWorkspace)
  let signature = toolCatalogSignature(
    bootstrap.tools, bootstrap.providerLabel, bootstrap.paddockDir, bootstrap.skillPrompt)
  ## An API turn carries no text the user typed in the conversation, so it can
  ## never answer an open ask; delivering it there would hand the question to
  ## the wrong turn and drop this one.
  let answersAsk = msg.bridgeToken == 0
  result = sm.buildSessionIngressContext(
    msg, signature, msgSeq,
    recordActivity = taskKind notin {tkSchedule, tkHeartbeat},
    answerableAsk = answersAsk)
  let recentContext =
    if result.plan.injectRecentContext:
      loadRecentContext(services.memory, services.fs, msg.userId)
    else:
      ""
  ## Enqueue task message BEFORE starting the new orchestrator.
  ## This prevents the orchestrator from receiving a cancel message
  ## (from the old orchestrator's inbox) before the task.
  if result.plan.decision.cancelsAsk and not result.plan.entry[].askInbox.isNil:
    result.plan.entry[].askInbox.addLastNoWait("__DONKEY_ASK_CANCELLED__")
    result.plan.entry[].awaitingAsk = false
  case result.plan.decision.target
  of sitActorInbox:
    if taskKind == tkUserMsg:
      result.plan.entry[].inbox.addLastNoWait(sessionTaskMsg(msg, result.msgId, recentContext))
    else:
      result.plan.entry[].inbox.addLastNoWait(newTaskMsg(
        result.msgId, taskKind, $msg.userId, taskPayload,
        msg.channel, sessionReplyTo(msg)))
  of sitAskInbox:
    if taskKind == tkUserMsg:
      result.plan.entry[].awaitingAsk = false
      result.plan.entry[].askInbox.addLastNoWait(msg.text)
    else:
      result.plan.entry[].inbox.addLastNoWait(newTaskMsg(
        result.msgId, taskKind, $msg.userId, taskPayload,
        msg.channel, sessionReplyTo(msg)))
  startSessionOrchestrator(result.plan, services.cfg,
                           services.memory,
                           services.streamFactory, bootstrap,
                           services.globalOutbox, services.log,
                           services.sandboxMode, services.sandboxRuntimeCmd, services.sandboxImage,
                           services.typingFn, services.searchFn,
                           services.http, services.fs, services.reminders,
                           services.process, services.attachments)
  if result.plan.decision.startsNewSession:
    services.log.info("new session: " & result.plan.uid)
  elif result.plan.decision.rebuildsSessionRuntime:
    services.log.info("rebuilt session runtime after tool catalog change: " & result.plan.uid)

proc ensureSession*(sm:       var SessionManager;
                    msg:      InboundMessage;
                    services: SessionIngressServices;
                    msgSeq:   var int) {.gcsafe.} =
  ## Helper to ensure session ingress for standard user message.
  discard startSessionIngress(sm, msg, services, msgSeq)

proc ensureSessionTask*(sm:       var SessionManager;
                        msg:      InboundMessage;
                        services: SessionIngressServices;
                        msgSeq:   var int;
                        taskKind: TaskKind;
                        payload:  string) {.gcsafe.} =
  ## Helper to ensure session ingress for background or system task.
  discard startSessionIngress(sm, msg, services, msgSeq, taskKind, payload)

# ── Scheduled task enqueue (automation US-005) ───────────────────────────────
#
# The scheduler fires at most once per occurrence and must know whether the
# firing reached the inbox. `ensureSessionTask` cannot answer that: it discards
# the ingress context, so an empty user id or a DM denial silently drops the
# task. `enqueueScheduledTask` applies the same gates *before* touching the
# session and surfaces each drop as `Err` for `ScheduleTickResult.enqueueError`.

const
  ScheduledTaskDroppedError* = "scheduled task dropped: denied or revoked"
    ## US-005 contract text: a dropped firing is an error, never `sent`.
  ScheduledTaskEmptyUserError* = "scheduled task dropped: empty user id"
  ScheduledTaskRevokedError* = "scheduled task dropped: user revoked"

func formatScheduledTaskPayload*(spec: ScheduleSpec; instantMs: int64): string =
  ## Payload handed to the inbox for one firing.
  ##
  ## `AgentMessage` carries no timestamp, so the fired instant is appended to
  ## the payload as a provenance line. The payload is what the orchestrator
  ## turns into the user turn, so the instant reaches the model and the user;
  ## the schedule's own payload stays a prefix of the text.
  spec.payload & "\n\n[schedule " & spec.id & " fired at " & $instantMs & " ms]"

func channelKindForSpec(spec: ScheduleSpec; channel: var ChannelKind): bool =
  ## Accepts every `ChannelKind` spelling (the parser in `domain/identity` only
  ## knows the legacy subset). Unknown names are rejected by the caller.
  parseChannelKindName(spec.channel, channel)

proc enqueueScheduledTask*(sm: var SessionManager;
                           services: SessionIngressServices;
                           msgSeq: var int;
                           spec: ScheduleSpec;
                           instantMs: int64): Result[void, string] {.gcsafe.} =
  ## Enqueues one schedule firing as a `tkSchedule` task.
  ##
  ## Reuses the normal ingress path (one session, one inbox, no second
  ## orchestrator) but fails closed: every gate below returns `Err` *before*
  ## `startSessionIngress` runs, so a denied firing leaves the session
  ## untouched and the runtime can record it as `failed`.
  let uidText = spec.userId.strip()
  if uidText.len == 0:
    return err(ScheduledTaskEmptyUserError)
  if uidText.startsWith("api:"):
    ## `api:` identities are request-scoped: their replies are intercepted by
    ## the HTTP bridge, and a scheduled firing has no turn token to match.
    return err("scheduled task dropped: api: users are request-scoped")
  let uid = UserId(uidText)
  if services.access.revoked(uid):
    return err(ScheduledTaskRevokedError)
  if services.dmPolicy != DmPolicyOpen:
    let allowed = services.access.dmAllowed(uid)
    if not allowed:
      return err(ScheduledTaskDroppedError)

  var channel: ChannelKind
  if not channelKindForSpec(spec, channel):
    return err("scheduled task dropped: unknown channel '" & spec.channel & "'")

  let msg = InboundMessage(
    userId: uid,
    channelId: "",
    text: "",
    channel: channel,
  )
  let ctx = startSessionIngress(
    sm, msg, services, msgSeq, tkSchedule,
    formatScheduledTaskPayload(spec, instantMs))
  if ctx.msgId.len == 0:
    ## Defensive backstop: the gates above mirror `startSessionIngress`, but an
    ## empty context still means the task never reached the inbox.
    return err(ScheduledTaskDroppedError)
  ok()

proc scheduleEnqueueFn*(sm: ptr SessionManager;
                        services: SessionIngressServices;
                        msgSeq: ptr int): ScheduleEnqueueFn =
  ## Adapts `enqueueScheduledTask` to the runtime's `ScheduleEnqueueFn`.
  ##
  ## The runtime owns the watermark; this closure only reports whether the
  ## occurrence reached the inbox. The session manager and the message
  ## sequence counter are passed by pointer because the runtime callback
  ## outlives the composition-root stack frame (same pattern as the daemon).
  result = proc(spec: ScheduleSpec; instantMs: int64): Result[void, string]
      {.gcsafe, raises: [].} =
    try:
      enqueueScheduledTask(sm[], services, msgSeq[], spec, instantMs)
    except Exception as e:  ## effect boundary: callee raises are unannotated
      err("scheduled task dropped: " & e.msg)

proc handleSessionFallback*(sm:           var SessionManager;
                           msgSeq:       var int;
                           msg:          InboundMessage;
                           services:     SessionIngressServices) {.gcsafe.} =
  ## Handles fallback message dispatch; rejects if user is revoked.
  if services.access.revoked(msg.userId):
    if services.globalOutbox != nil:
      services.globalOutbox.putNoWait(OutboundMessage(
        userId: msg.userId,
        channel: msg.channel,
        replyTo: sessionReplyTo(msg),
        text: "Acesso revogado pelo administrador.",
      ))
    return
  ensureSession(sm, msg, services, msgSeq)
