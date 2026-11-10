## Session bootstrap helpers.
##
## Concentrates provider selection, fallback composition, per-user skill merge
## and native tool exposure so the daemon entrypoint only coordinates lifecycle.

import std/[algorithm, json, os, strutils]
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

const
  RecentContextMessageLimit* = 5

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
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "openai/gpt-6.1-sol",
      apiKey: getEnv("OPENROUTER_API_KEY"),
    )
  of "openai":
    ProviderSpec(
      providerName: "openai",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "gpt-6.1-sol",
      apiKey: getEnv("OPENAI_API_KEY"),
    )
  of "deepseek":
    ProviderSpec(
      providerName: "deepseek",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "deepseek-4.1-flash",
      apiKey: getEnv("DEEPSEEK_API_KEY"),
    )
  of "ollama":
    ProviderSpec(
      providerName: "ollama",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "llama3.3",
      apiKey: getEnv("OLLAMA_BASE_URL", ""),
    )
  of "groq":
    ProviderSpec(
      providerName: "groq",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: GroqDefaultModel,
      apiKey: getEnv("GROQ_API_KEY"),
    )
  of "opencode-go", "opencode":
    ProviderSpec(
      providerName: "opencode-go",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: OpenCodeGoDefaultModel,
      apiKey: getEnv("OPENCODE_API_KEY", getEnv("OPENCODE_GO_API_KEY")),
    )
  of "zen", "opencode-zen":
    ProviderSpec(
      providerName: "zen",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: ZenDefaultModel,
      apiKey: getEnv("OPENCODE_API_KEY", getEnv("ZEN_API_KEY")),
    )
  of "anthropic":
    ProviderSpec(
      providerName: "anthropic",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "claude-sonnet-5-5",
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
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "gemini-3.8-flash",
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
    openai: getEnv("OPENAI_API_KEY").len > 0,
    deepseek: getEnv("DEEPSEEK_API_KEY").len > 0,
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
    groq: getEnv("GROQ_API_KEY").len > 0,
    ollama: getEnv("OLLAMA_BASE_URL").len > 0,
    opencodeGo: getEnv("OPENCODE_API_KEY", getEnv("OPENCODE_GO_API_KEY")).len > 0,
    zen: getEnv("OPENCODE_API_KEY", getEnv("ZEN_API_KEY")).len > 0,
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

func encodeSessionPayload*(msg: InboundMessage;
                           recentContext = ""): string =
  if msg.mediaUrl.len == 0 and recentContext.len == 0:
    return msg.text
  $(%* {"text": msg.text, "mediaUrl": msg.mediaUrl, "recentContext": recentContext})

func sessionReplyTo*(msg: InboundMessage): string =
  case msg.channel
  of ckTelegram:
    msg.channelId
  of ckDiscord:
    if msg.channelId.len > 0: "channel:" & msg.channelId else: ""
  else:
    ""

proc buildSessionTaskMsg*(msg: InboundMessage;
                          msgId: string;
                          recentContext = ""): AgentMessage =
  newTaskMsg(msgId, tkUserMsg, $msg.userId, encodeSessionPayload(msg, recentContext),
             msg.channel, sessionReplyTo(msg))

proc loadRecentContext*(memory: MemoryRuntimePort;
                        userId: UserId;
                        limit = RecentContextMessageLimit): string {.gcsafe.} =
  if limit <= 0:
    return ""
  let sessionsDir = memory.paddockDir(userId) / "sessions"
  if not dirExists(sessionsDir):
    return ""
  var sessionIds: seq[string] = @[]
  try:
    for kind, path in walkDir(sessionsDir):
      if kind == pcFile and path.endsWith(".jsonl"):
        sessionIds.add(path.extractFilename().changeFileExt(""))
  except CatchableError:
    return ""
  sessionIds.sort(proc(a, b: string): int = cmp(b, a))
  var lines: seq[string] = @[]
  for sid in sessionIds:
    if lines.len >= limit:
      break
    let path = sessionsDir / (sid & ".jsonl")
    let content = try: readFile(path) except CatchableError: ""
    if content.len == 0:
      continue
    let rawLines = content.splitLines()
    for i in countdown(rawLines.high, 0):
      let raw = rawLines[i].strip()
      if raw.len == 0:
        continue
      try:
        let j = parseJson(raw)
        let role = j.getOrDefault("role").getStr("").toLowerAscii()
        if role notin ["user", "assistant"]:
          continue
        let text = j.getOrDefault("text").getStr("").strip()
        let imageUrl = j.getOrDefault("imageUrl").getStr("").strip()
        if text.len == 0 and imageUrl.len == 0:
          continue
        let label = if role == "user": "User" else: "Assistant"
        let body =
          if text.len > 0 and imageUrl.len > 0:
            text & "\n[image attachment]"
          elif text.len > 0:
            text
          else:
            "[image attachment]"
        lines.add(label & ": " & body)
        if lines.len >= limit:
          break
      except CatchableError:
        discard
  lines.reverse()
  lines.join("\n\n")

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
    (FsListToolName,        FsListToolDescription,        FsListToolSchema),
    (FsReadToolName,        FsReadToolDescription,        FsReadToolSchema),
    (FsWriteToolName,       FsWriteToolDescription,       FsWriteToolSchema),
    (FsMkdirToolName,       FsMkdirToolDescription,       FsMkdirToolSchema),
    (FsCopyToolName,        FsCopyToolDescription,        FsCopyToolSchema),
    (FsMoveToolName,        FsMoveToolDescription,        FsMoveToolSchema),
    (FsRemoveToolName,      FsRemoveToolDescription,      FsRemoveToolSchema),
    (TextSearchToolName,    TextSearchToolDescription,    TextSearchToolSchema),
    (TextReadToolName,      TextReadToolDescription,      TextReadToolSchema),
    (TextReplaceToolName,   TextReplaceToolDescription,   TextReplaceToolSchema),
    (JsonQueryToolName,     JsonQueryToolDescription,     JsonQueryToolSchema),
    (TableQueryToolName,    TableQueryToolDescription,    TableQueryToolSchema),
    (HttpFetchToolName,     HttpFetchToolDescription,     HttpFetchToolSchema),
    (ArchiveExtractToolName, ArchiveExtractToolDescription, ArchiveExtractToolSchema),
    (ArchiveCreateToolName, ArchiveCreateToolDescription, ArchiveCreateToolSchema),
    (FetchToolName,         FetchToolDescription,         FetchToolSchema),
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
  if getEnv("BRAVE_API_KEY").len > 0:
    result.add(ToolDescription(
      name: WebSearchToolName,
      description: WebSearchToolDescription,
      schemaJson: WebSearchToolSchema,
    ))

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
