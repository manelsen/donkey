## Session bootstrap helpers.
##
## Concentrates provider selection, fallback composition, per-user skill merge
## and native tool exposure so the daemon entrypoint only coordinates lifecycle.

import std/[json, os, strutils]
import ../config/skills_registry
import ../config/clawhub_registry
import ../core/pipeops
import ../core/providers/smart_routing
import ../domain/agent_message
import ../domain/message
import ../domain/builtin_tools
import ../domain/more_tools
import ../domain/reminder
import ../ports/memory
import ../ports/provider
import ../ports/tool
export provider

type
  ProviderDefaults* = object
    providerName*: string
    modelName*: string

  SessionToolBundle* = object
    clients*: seq[ToolRuntimePort]
    tools*:   seq[ToolDescription]

  SessionBootstrap* = object
    completeFn*:    CompleteFn
    errorExplainFn*: CompleteFn
    paddockDir*:    string
    clients*:       seq[ToolRuntimePort]
    tools*:         seq[ToolDescription]
    providerLabel*: string
    skillPrompt*:   string

  SessionBootstrapPlan* = object
    preferencesMd*: string
    paddockDir*:    string
    completeFn*:    CompleteFn
    errorExplainFn*: CompleteFn
    clients*:       seq[ToolRuntimePort]
    tools*:         seq[ToolDescription]
    providerLabel*: string
    skillPrompt*:   string

  SessionContext* = object
    preferencesMd*: string
    paddockDir*:    string
    providerLabel*: string
    skillPrompt*:   string

proc defaultProviderPrefs*(): ProviderPrefs =
  ProviderPrefs(providerName: "zai-coding", modelName: "")

func normalizeProviderDefaults*(providerName, modelName: string): ProviderDefaults =
  ProviderDefaults(
    providerName: providerName.strip(),
    modelName: modelName.strip(),
  )

func applyProviderDefaults*(preferencesMd: string;
                            defaults: ProviderDefaults): string =
  let prefs = parseSmartRoutingPrefs(preferencesMd)
  result = preferencesMd
  if defaults.providerName.len == 0 or prefs.providerExplicit:
    return
  if result.strip.len > 0 and not result.endsWith("\n"):
    result &= "\n"
  result &= "provider = \"" & defaults.providerName & "\"\n"
  if defaults.modelName.len > 0:
    result &= "model = \"" & defaults.modelName & "\"\n"

proc parseProviderPrefs*(preferencesMd: string): ProviderPrefs {.gcsafe, raises: [].} =
  let prefs = parseSmartRoutingPrefs(preferencesMd)
  ProviderPrefs(providerName: prefs.providerName, modelName: prefs.modelName)

proc parseProviderPrefs*(preferencesMd: string;
                         defaults: ProviderDefaults): ProviderPrefs {.gcsafe, raises: [].} =
  parseProviderPrefs(applyProviderDefaults(preferencesMd, defaults))

proc buildProviderSpec*(prefs: ProviderPrefs): ProviderSpec {.gcsafe, raises: [].} =
  case prefs.providerName
  of "openrouter":
    ProviderSpec(
      providerName: "openrouter",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "openai/gpt-4o-mini",
      apiKey: getEnv("OPENROUTER_API_KEY"),
    )
  of "anthropic":
    ProviderSpec(
      providerName: "anthropic",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "claude-opus-4-6",
      apiKey: getEnv("ANTHROPIC_API_KEY"),
    )
  of "zai-anthropic":
    ProviderSpec(
      providerName: "zai-anthropic",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "glm-4.7",
      apiKey: getEnv(
        "ZAI_ANTHROPIC_API_KEY",
        getEnv(
          "ANTHROPIC_AUTH_TOKEN",
          getEnv("ZAI_CODING_API_KEY", getEnv("ZAI_API_KEY", getEnv("ZHIPU_API_KEY")))
        )
      ),
    )
  of "gemini":
    ProviderSpec(
      providerName: "gemini",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "gemini-2.5-flash",
      apiKey: getEnv("GEMINI_API_KEY"),
    )
  of "minimax":
    ProviderSpec(
      providerName: "minimax",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "MiniMax-M2",
      apiKey: getEnv("MINIMAX_API_KEY"),
    )
  of "zai":
    ProviderSpec(
      providerName: "zai",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "glm-4.7",
      apiKey: getEnv("ZAI_API_KEY"),
    )
  else:
    ProviderSpec(
      providerName: "zai-coding",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "glm-4.7",
      apiKey: getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")),
    )

proc buildProviderBundle*(preferencesMd: string;
                          providerRuntimeBuilder: ProviderRuntimeBuilder): ProviderBundle {.gcsafe.} =
  preferencesMd |> parseProviderPrefs |> buildProviderSpec |> providerRuntimeBuilder

proc buildProviderBundle*(preferencesMd: string;
                          defaults: ProviderDefaults;
                          providerRuntimeBuilder: ProviderRuntimeBuilder): ProviderBundle {.gcsafe.} =
  applyProviderDefaults(preferencesMd, defaults) |>
    parseProviderPrefs |>
    buildProviderSpec |>
    providerRuntimeBuilder

func detectProviderAvailability*(): ProviderAvailability =
  ProviderAvailability(
    openrouter: getEnv("OPENROUTER_API_KEY").len > 0,
    anthropic: getEnv("ANTHROPIC_API_KEY").len > 0,
    zaiAnthropic: getEnv(
      "ZAI_ANTHROPIC_API_KEY",
      getEnv(
        "ANTHROPIC_AUTH_TOKEN",
        getEnv("ZAI_CODING_API_KEY", getEnv("ZAI_API_KEY", getEnv("ZHIPU_API_KEY")))
      )
    ).len > 0,
    gemini: getEnv("GEMINI_API_KEY").len > 0,
    minimax: getEnv("MINIMAX_API_KEY").len > 0,
    zai: getEnv("ZAI_API_KEY").len > 0,
    zaiCoding: getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")).len > 0,
  )

func toProviderSpec*(selection: ProviderSelection): ProviderSpec =
  buildProviderSpec(ProviderPrefs(
    providerName: selection.providerName,
    modelName: selection.modelName,
  ))

proc buildCompleteFn*(preferencesMd: string;
                      providerRuntimeBuilder: ProviderRuntimeBuilder;
                      routingHook: RoutingTelemetryHook = nil;
                      routingResultHook: RoutingResultHook = nil;
                      routingFeedbackHook: RoutingFeedbackHook = nil;
                      routingCostHook: RoutingCostHook = nil;
                      routingProviderCooldownHook: RoutingProviderCooldownHook = nil): CompleteFn {.gcsafe.} =
  let prefs = parseSmartRoutingPrefs(preferencesMd)
  let availability = detectProviderAvailability()
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let baseSelections = smartRouteSelections(prefs, req, availability)
    let rankedSelections =
      if routingFeedbackHook != nil:
        reorderSelectionsWithFeedback(baseSelections, routingFeedbackHook())
      else:
        baseSelections
    let selections =
      if routingFeedbackHook != nil:
        applyCircuitBreaker(rankedSelections, routingFeedbackHook())
      else:
        rankedSelections
    let providerHealthySelections =
      if routingFeedbackHook != nil:
        applyProviderCircuitBreaker(selections, routingFeedbackHook())
      else:
        selections
    let cooldownFilteredSelections =
      if routingProviderCooldownHook != nil:
        applyProviderCooldowns(providerHealthySelections, routingProviderCooldownHook(),
                               nowMs() div 1000)
      else:
        providerHealthySelections
    let costAwareSelections =
      if routingCostHook != nil:
        reorderSelectionsWithCost(cooldownFilteredSelections, routingCostHook(),
                                  prefs.budgetPolicy)
      else:
        cooldownFilteredSelections
    var lastErr = "no provider available"
    for selection in costAwareSelections:
      if routingHook != nil:
        routingHook(selection, prefs, req)
      let startedAt = nowMs()
      let bundle = providerRuntimeBuilder(selection.toProviderSpec)
      if bundle.completeFn == nil:
        continue
      let response = bundle.completeFn(req)
      if routingResultHook != nil:
        routingResultHook(selection, nowMs() - startedAt, response.isOk)
      if response.isOk:
        return response
      lastErr = response.error
    err(lastErr)

proc buildFallbackFn*(primary: CompleteFn; fallbacks: seq[CompleteFn]): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let r = primary(req)
    if r.isOk: return r
    for fb in fallbacks:
      let r2 = fb(req)
      if r2.isOk: return r2
    r

func providerLabelFromPrefs*(prefs: string): string =
  parseSmartRoutingPrefs(prefs).routingLabel

func providerLabelFromPrefs*(prefs: string;
                             defaults: ProviderDefaults): string =
  parseSmartRoutingPrefs(applyProviderDefaults(prefs, defaults)).routingLabel

func encodeSessionPayload*(msg: InboundMessage): string =
  if msg.mediaUrl.len == 0:
    return msg.text
  $(%* {"text": msg.text, "mediaUrl": msg.mediaUrl})

func sessionReplyTo*(msg: InboundMessage): string =
  if msg.channel == ckTelegram: msg.channelId else: ""

proc buildSessionTaskMsg*(msg: InboundMessage; msgId: string): AgentMessage =
  newTaskMsg(msgId, tkUserMsg, $msg.userId, encodeSessionPayload(msg),
             msg.channel, sessionReplyTo(msg))

proc userSkillsDir*(memory: MemoryRuntimePort; userId: UserId): string {.gcsafe.} =
  memory.paddockDir(userId) / "skills"

func nativeSessionTools*(): seq[ToolDescription] =
  result = @[
    ToolDescription(name: ReminderToolName, description: ReminderToolDescription, schemaJson: ReminderToolSchema),
    ToolDescription(name: CurrentTimeToolName, description: CurrentTimeToolDescription, schemaJson: CurrentTimeToolSchema),
    ToolDescription(name: WebFetchToolName, description: WebFetchToolDescription, schemaJson: WebFetchToolSchema),
  ]
  for (n, d, s) in [
    (BashToolName,          BashToolDescription,          BashToolSchema),
    (ReadFileToolName,      ReadFileToolDescription,      ReadFileToolSchema),
    (EditFileToolName,      EditFileToolDescription,      EditFileToolSchema),
    (FindToolName,          FindToolDescription,          FindToolSchema),
    (GrepToolName,          GrepToolDescription,          GrepToolSchema),
    (SedToolName,           SedToolDescription,           SedToolSchema),
    (WcToolName,            WcToolDescription,            WcToolSchema),
    (HeadToolName,          HeadToolDescription,          HeadToolSchema),
    (TailToolName,          TailToolDescription,          TailToolSchema),
    (SortToolName,          SortToolDescription,          SortToolSchema),
    (CpToolName,            CpToolDescription,            CpToolSchema),
    (MvToolName,            MvToolDescription,            MvToolSchema),
    (RmToolName,            RmToolDescription,            RmToolSchema),
    (MkdirToolName,         MkdirToolDescription,         MkdirToolSchema),
    (FetchToolName,         FetchToolDescription,         FetchToolSchema),
    (WebSearchToolName,     WebSearchToolDescription,     WebSearchToolSchema),
    (CalcToolName,          CalcToolDescription,          CalcToolSchema),
    (RenderMermaidToolName, RenderMermaidToolDescription, RenderMermaidToolSchema),
    (InspectImageToolName,  InspectImageToolDescription,  InspectImageToolSchema),
    (AskToolName,           AskToolDescription,           AskToolSchema),
    (TodoWriteToolName,     TodoWriteToolDescription,     TodoWriteToolSchema),
    (CheckpointToolName,    CheckpointToolDescription,    CheckpointToolSchema),
    (RewindToolName,        RewindToolDescription,        RewindToolSchema),
    (ManageSkillsToolName,  ManageSkillsToolDescription,  ManageSkillsToolSchema),
    (TaskToolName,          TaskToolDescription,          TaskToolSchema),
    (SubmitResultToolName,  SubmitResultToolDescription,  SubmitResultToolSchema),
    (ReportFindingToolName, ReportFindingToolDescription, ReportFindingToolSchema),
    (CancelJobToolName,     CancelJobToolDescription,     CancelJobToolSchema),
    (AwaitToolName,         AwaitToolDescription,         AwaitToolSchema),
  ]:
    result.add(ToolDescription(name: n, description: d, schemaJson: s))

func addNativeSessionTools*(tools: seq[ToolDescription]): seq[ToolDescription] =
  result = tools
  result.add(nativeSessionTools())

proc mergeUserSkillsIntoSession*(skillsDir: string;
                                 skillRuntimeBuilder: SkillRuntimeBuilder;
                                 skillRuntimePolicyResolver: SkillRuntimePolicyResolver;
                                 sessionClients: var seq[ToolRuntimePort];
                                 sessionTools:   var seq[ToolDescription]) {.gcsafe.}

proc loadSessionContext*(memory: MemoryRuntimePort;
                         userId: UserId;
                         defaults = ProviderDefaults()): SessionContext {.gcsafe.} =
  let ctx = memory.loadContext(userId)
  let homeDir = parentDir(parentDir(memory.paddockDir(userId)))
  SessionContext(
    preferencesMd: ctx.preferencesMd,
    paddockDir: memory.paddockDir(userId),
    providerLabel: providerLabelFromPrefs(ctx.preferencesMd, defaults),
    skillPrompt: buildInstalledRemoteSkillPrompt(loadInstalledRemoteSkills(homeDir)),
  )

proc startSessionToolBundle*(toolClients: seq[ToolRuntimePort];
                             tools: seq[ToolDescription]): SessionToolBundle =
  SessionToolBundle(clients: toolClients, tools: tools)

proc withUserSkills*(input: (string, SkillRuntimeBuilder, SkillRuntimePolicyResolver, SessionToolBundle)): SessionToolBundle {.gcsafe.} =
  let (skillsDir, skillRuntimeBuilder, skillRuntimePolicyResolver, toolBundle) = input
  result = toolBundle
  mergeUserSkillsIntoSession(
    skillsDir, skillRuntimeBuilder, skillRuntimePolicyResolver, result.clients, result.tools)

func withNativeTools*(toolBundle: SessionToolBundle): SessionToolBundle =
  result = toolBundle
  result.tools = result.tools |> addNativeSessionTools

proc mergeUserSkillsIntoSession*(skillsDir: string;
                                 skillRuntimeBuilder: SkillRuntimeBuilder;
                                 skillRuntimePolicyResolver: SkillRuntimePolicyResolver;
                                 sessionClients: var seq[ToolRuntimePort];
                                 sessionTools:   var seq[ToolDescription]) {.gcsafe.} =
  let userSkills = mergeSkills(@[], loadUserSkills(skillsDir))
  for m in userSkills:
    let res = skillRuntimeBuilder(m.script, m.permissions, skillRuntimePolicyResolver(m.name))
    if res.isOk:
      for s in res.value.schemas:
        sessionTools.add(ToolDescription(
          name:        s.name,
          description: s.description,
          schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
        ))
      sessionClients.add(res.value.port)

proc buildSessionCompleteFn*(memory: MemoryRuntimePort;
                             userId: UserId;
                             fallbackCompleteFn: CompleteFn;
                             providerRuntimeBuilder: ProviderRuntimeBuilder;
                             providerDefaults = ProviderDefaults();
                             routingHook: RoutingTelemetryHook = nil;
                             routingResultHook: RoutingResultHook = nil;
                             routingFeedbackHook: RoutingFeedbackHook = nil;
                             routingCostHook: RoutingCostHook = nil;
                             routingProviderCooldownHook: RoutingProviderCooldownHook = nil): CompleteFn {.gcsafe.} =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let preferencesMd = memory.loadContext(userId).preferencesMd
    let primary = buildCompleteFn(
      applyProviderDefaults(preferencesMd, providerDefaults),
      providerRuntimeBuilder, routingHook, routingResultHook,
      routingFeedbackHook, routingCostHook, routingProviderCooldownHook)
    let fallbacks = if fallbackCompleteFn != nil: @[fallbackCompleteFn] else: @[]
    buildFallbackFn(primary, fallbacks)(req)

proc loadSessionBootstrapPlan*(input: SessionContext): SessionBootstrapPlan {.gcsafe.} =
  let ctx = input
  SessionBootstrapPlan(
    preferencesMd: ctx.preferencesMd,
    paddockDir: ctx.paddockDir,
    providerLabel: ctx.providerLabel,
    skillPrompt: ctx.skillPrompt,
  )

proc withSessionCompleteFn*(fallbackCompleteFn: CompleteFn;
                            providerRuntimeBuilder: ProviderRuntimeBuilder;
                            memory: MemoryRuntimePort;
                            userId: UserId;
                            providerDefaults: ProviderDefaults;
                            routingHook: RoutingTelemetryHook;
                            routingResultHook: RoutingResultHook;
                            routingFeedbackHook: RoutingFeedbackHook;
                            routingCostHook: RoutingCostHook;
                            routingProviderCooldownHook: RoutingProviderCooldownHook;
                            plan: SessionBootstrapPlan): SessionBootstrapPlan {.gcsafe.} =
  result = plan
  result.completeFn = buildSessionCompleteFn(
    memory, userId, fallbackCompleteFn, providerRuntimeBuilder, providerDefaults,
    routingHook, routingResultHook, routingFeedbackHook, routingCostHook,
    routingProviderCooldownHook)
  result.errorExplainFn = fallbackCompleteFn

func withSessionToolBundle*(toolBundle: SessionToolBundle;
                            plan: SessionBootstrapPlan): SessionBootstrapPlan =
  result = plan
  result.clients = toolBundle.clients
  result.tools = toolBundle.tools

func finalizeSessionBootstrap*(plan: SessionBootstrapPlan): SessionBootstrap =
  SessionBootstrap(
    completeFn: plan.completeFn,
    errorExplainFn: plan.errorExplainFn,
    paddockDir: plan.paddockDir,
    clients: plan.clients,
    tools: plan.tools,
    providerLabel: plan.providerLabel,
    skillPrompt: plan.skillPrompt,
  )

proc buildSessionToolBundle*(memory:      MemoryRuntimePort;
                             userId:      UserId;
                             skillRuntimeBuilder: SkillRuntimeBuilder;
                             skillRuntimePolicyResolver: SkillRuntimePolicyResolver;
                             toolClients: seq[ToolRuntimePort];
                             tools:       seq[ToolDescription]): SessionToolBundle {.gcsafe.} =
  let skillsDir = userSkillsDir(memory, userId)
  ((skillsDir, skillRuntimeBuilder, skillRuntimePolicyResolver,
    startSessionToolBundle(toolClients, tools)) |>
    withUserSkills) |>
    withNativeTools

proc buildSessionBootstrap*(memory:      MemoryRuntimePort;
                            userId:      UserId;
                            completeFn:  CompleteFn;
                            providerRuntimeBuilder: ProviderRuntimeBuilder;
                            providerDefaults = ProviderDefaults();
                            skillRuntimeBuilder: SkillRuntimeBuilder;
                            skillRuntimePolicyResolver: SkillRuntimePolicyResolver;
                            toolClients: seq[ToolRuntimePort];
                            tools:       seq[ToolDescription];
                            routingHook: RoutingTelemetryHook = nil;
                            routingResultHook: RoutingResultHook = nil;
                            routingFeedbackHook: RoutingFeedbackHook = nil;
                            routingCostHook: RoutingCostHook = nil;
                            routingProviderCooldownHook: RoutingProviderCooldownHook = nil): SessionBootstrap {.gcsafe.} =
  let toolBundle = buildSessionToolBundle(
    memory, userId, skillRuntimeBuilder, skillRuntimePolicyResolver, toolClients, tools)
  result =
    (((loadSessionContext(memory, userId, providerDefaults) |>
       loadSessionBootstrapPlan) |>->
       withSessionCompleteFn(
         completeFn, providerRuntimeBuilder, memory, userId, providerDefaults,
         routingHook, routingResultHook, routingFeedbackHook, routingCostHook,
         routingProviderCooldownHook)) |>->
       withSessionToolBundle(toolBundle)) |>
       finalizeSessionBootstrap
