## session_ingress.nim — Session ingress planning and lifecycle orchestration.
##
## Coordinates session planning, context building, task/inbox message routing,
## and orchestrator actor launching for inbound messages.
##
## Strict hexagonal architecture: no direct imports from adapters/.

import chronos
import chronos/asyncsync
import ../config/types
import ../core/types
import ../core/log
import ../core/pipeops
import ../core/session/session_ingress as coreSessionIngress
import ../core/providers/smart_routing
import ../core/security/dm_policy
import ../domain/agent_message
import ../domain/message
import ../ports/memory
import ../ports/provider
import ../ports/tool
import ../ports/http
import ./session_manager
import ./session_state
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
    completeFn*:                 CompleteFn
    streamFn*:                   StreamFn
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
    providerRuntimeBuilder*:     ProviderRuntimeBuilder
    skillRuntimeBuilder*:        SkillRuntimeBuilder
    skillRuntimePolicyResolver*: SkillRuntimePolicyResolver
    isRevoked*:                  proc(userId: UserId): bool {.gcsafe.}
    isDmAllowed*:                proc(userId: UserId): bool {.gcsafe.}
    dmPolicy*:                   DmPolicy
    routeRecordHook*:            proc(selection: ProviderSelection) {.gcsafe.}
    routeResultHook*:            proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.}
    routeFeedbackHook*:          proc(): seq[RouteFeedback] {.gcsafe.}
    routeCostHook*:              proc(): seq[RouteCostHint] {.gcsafe.}
    routeProviderCooldownHook*:  proc(): seq[ProviderCooldown] {.gcsafe.}

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
                             persist: bool = true): EnsureSessionPlan =
  ## Evaluates session ingress state and decides whether to reuse, rebuild, or create a session.
  ## `persist = false` lets the ingress path batch the registry write after
  ## channel bookkeeping.
  const ColdSessionThresholdMs = 60'i64 * 60 * 1000
  let ingressState = sm.snapshot(userId)
  let decision = decideSessionIngress(SessionIngressRequest(
    userId: userId,
    state: ingressState,
    nextSignature: toolCatalogSignature,
  ))
  let now = nowMs()
  let wasCold =
    ingressState.lastInboundAtMs > 0 and
    now - ingressState.lastInboundAtMs >= ColdSessionThresholdMs
  let lease = sm.applyIngressDecision(userId, decision, toolCatalogSignature)
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
                                 msgSeq: var int): SessionIngressContext =
  ## Builds ingress plan, records the channel, and persists the session exactly
  ## once per inbound message.
  result.plan = sm.buildEnsureSessionPlan(msg.userId, toolCatalogSignature, persist = false)
  inc msgSeq
  result.msgId = $msg.userId & "-" & $msgSeq
  if result.plan.decision.shouldRecordChannel:
    sm.recordChannel(msg.userId, msg.channel, msg.channelId, persist = false)
  sm.persistSession(msg.userId)

func buildSessionIngressServices*(memory: MemoryRuntimePort;
                                  cfg: DonkeyConfig;
                                  completeFn: CompleteFn;
                                  streamFn: StreamFn;
                                  toolClients: seq[ToolRuntimePort];
                                  tools: seq[ToolDescription];
                                  globalOutbox: AsyncQueue[OutboundMessage];
                                  log: Logger;
                                  sandboxMode: SandboxMode;
                                  sandboxRuntimeCmd: string;
                                  sandboxImage: string;
                                  typingFn: TypingFn;
                                  searchFn: SearchFn;
                                  isRevoked: proc(userId: UserId): bool {.gcsafe.};
                                  isDmAllowed: proc(userId: UserId): bool {.gcsafe.} = nil;
                                  dmPolicy: DmPolicy = DmPolicyOpen;
                                  http: HttpRuntimePort;
                                  providerRuntimeBuilder: ProviderRuntimeBuilder = nil;
                                  skillRuntimeBuilder: SkillRuntimeBuilder = nil;
                                  skillRuntimePolicyResolver: SkillRuntimePolicyResolver = nil;
                                  routeRecordHook: proc(selection: ProviderSelection) {.gcsafe.} = nil;
                                  routeResultHook: proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.} = nil;
                                  routeFeedbackHook: proc(): seq[RouteFeedback] {.gcsafe.} = nil;
                                  routeCostHook: proc(): seq[RouteCostHint] {.gcsafe.} = nil;
                                  routeProviderCooldownHook: proc(): seq[ProviderCooldown] {.gcsafe.} = nil): SessionIngressServices =
  ## Constructs SessionIngressServices.
  SessionIngressServices(
    cfg: cfg,
    memory: memory,
    completeFn: completeFn,
    streamFn: streamFn,
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
    providerRuntimeBuilder: providerRuntimeBuilder,
    skillRuntimeBuilder: skillRuntimeBuilder,
    skillRuntimePolicyResolver: skillRuntimePolicyResolver,
    isRevoked: isRevoked,
    isDmAllowed: isDmAllowed,
    dmPolicy: dmPolicy,
    routeRecordHook: routeRecordHook,
    routeResultHook: routeResultHook,
    routeFeedbackHook: routeFeedbackHook,
    routeCostHook: routeCostHook,
    routeProviderCooldownHook: routeProviderCooldownHook,
  )

func withTypingFn*(typingFn: TypingFn;
                   services: SessionIngressServices): SessionIngressServices =
  ## Returns services with typingFn replaced.
  result = services
  result.typingFn = typingFn

proc startSessionOrchestrator*(plan: EnsureSessionPlan;
                               cfg: DonkeyConfig;
                               memory: MemoryRuntimePort;
                               streamFn: StreamFn;
                               bootstrap: SessionBootstrap;
                               globalOutbox: AsyncQueue[OutboundMessage];
                               log: Logger;
                               sandboxMode: SandboxMode;
                               sandboxRuntimeCmd: string;
                               sandboxImage: string;
                               typingFn: TypingFn;
                               searchFn: SearchFn;
                               http: HttpRuntimePort) {.gcsafe.} =
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
                             http, streamFn,
                             bootstrap.clients, bootstrap.tools,
                             bootstrap.paddockDir, state,
                             typingFn, searchFn, log.child("orch"), bootstrap.providerLabel,
                             bootstrap.skillPrompt,
                             sandboxMode, sandboxRuntimeCmd, sandboxImage,
                             cfg.webAllowlist, cfg.toolWebPolicy,
                             errorExplainFn = bootstrap.errorExplainFn,
                             asyncCompleteFn = bootstrap.asyncCompleteFn)

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
    entry.inbox.addLastNoWait(buildSessionTaskMsg(msg, msgId))

proc startSessionIngress*(sm: var SessionManager;
                          msg: InboundMessage;
                          services: SessionIngressServices;
                          msgSeq: var int;
                          taskKind: TaskKind = tkUserMsg;
                          taskPayload: string = ""): SessionIngressContext {.gcsafe.} =
  ## Full session ingress flow: builds bootstrap, plan, context, enqueues message, and spawns orchestrator.
  if services.dmPolicy != DmPolicyOpen:
    let allowed =
      services.isDmAllowed != nil and services.isDmAllowed(msg.userId)
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
         req: CompletionRequest) {.gcsafe.} =
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
    services.routeCostHook, services.routeProviderCooldownHook)
  let signature = toolCatalogSignature(
    bootstrap.tools, bootstrap.providerLabel, bootstrap.paddockDir, bootstrap.skillPrompt)
  result = sm.buildSessionIngressContext(msg, signature, msgSeq)
  let recentContext =
    if result.plan.injectRecentContext:
      loadRecentContext(services.memory, msg.userId)
    else:
      ""
  ## Enqueue task message BEFORE starting the new orchestrator.
  ## This prevents the orchestrator from receiving a cancel message
  ## (from the old orchestrator's inbox) before the task.
  case result.plan.decision.target
  of sitActorInbox:
    if taskKind == tkUserMsg:
      result.plan.entry[].inbox.addLastNoWait(buildSessionTaskMsg(msg, result.msgId, recentContext))
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
                           services.streamFn, bootstrap,
                           services.globalOutbox, services.log,
                           services.sandboxMode, services.sandboxRuntimeCmd, services.sandboxImage,
                           services.typingFn, services.searchFn,
                           services.http)
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

proc handleSessionFallback*(sm:           var SessionManager;
                           msgSeq:       var int;
                           msg:          InboundMessage;
                           services:     SessionIngressServices) {.gcsafe.} =
  ## Handles fallback message dispatch; rejects if user is revoked.
  if services.isRevoked != nil and services.isRevoked(msg.userId):
    if services.globalOutbox != nil:
      services.globalOutbox.putNoWait(OutboundMessage(
        userId: msg.userId,
        channel: msg.channel,
        replyTo: sessionReplyTo(msg),
        text: "Acesso revogado pelo administrador.",
      ))
    return
  ensureSession(sm, msg, services, msgSeq)
