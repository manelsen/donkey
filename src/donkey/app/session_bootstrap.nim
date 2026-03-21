## Session bootstrap helpers.
##
## Concentrates provider selection, fallback composition, per-user skill merge
## and native tool exposure so the daemon entrypoint only coordinates lifecycle.

import std/[json, os, strutils]
import parsetoml
import ../config/skills_registry
import ../config/clawhub_registry
import ../core/pipeops
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
  SessionToolBundle* = object
    clients*: seq[ToolRuntimePort]
    tools*:   seq[ToolDescription]

  SessionBootstrap* = object
    completeFn*:    CompleteFn
    paddockDir*:    string
    clients*:       seq[ToolRuntimePort]
    tools*:         seq[ToolDescription]
    providerLabel*: string
    skillPrompt*:   string

  SessionBootstrapPlan* = object
    preferencesMd*: string
    paddockDir*:    string
    completeFn*:    CompleteFn
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

proc parseProviderPrefs*(preferencesMd: string): ProviderPrefs {.gcsafe, raises: [].} =
  result = defaultProviderPrefs()
  if preferencesMd.len == 0:
    return
  try:
    {.cast(gcsafe).}:
      let t = parsetoml.parseString(preferencesMd)
      if t.hasKey("provider"):
        result.providerName = t["provider"].getStr()
      if t.hasKey("model"):
        result.modelName = t["model"].getStr()
  except:
    discard

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
  of "gemini":
    ProviderSpec(
      providerName: "gemini",
      modelName: if prefs.modelName.len > 0: prefs.modelName else: "gemini-2.0-flash",
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
  providerRuntimeBuilder(buildProviderSpec(parseProviderPrefs(preferencesMd)))

proc buildCompleteFn*(preferencesMd: string;
                      providerRuntimeBuilder: ProviderRuntimeBuilder): CompleteFn {.gcsafe.} =
  buildProviderBundle(preferencesMd, providerRuntimeBuilder).completeFn

proc buildFallbackFn*(primary: CompleteFn; fallbacks: seq[CompleteFn]): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let r = primary(req)
    if r.isOk: return r
    for fb in fallbacks:
      let r2 = fb(req)
      if r2.isOk: return r2
    r

func providerLabelFromPrefs*(prefs: string): string =
  var prov = "zai-coding"
  var mdl  = ""
  for line in prefs.splitLines():
    let parts = line.split('=', 1)
    if parts.len != 2: continue
    let k = parts[0].strip()
    let v = parts[1].strip().strip(chars = {'"'})
    case k
    of "provider": prov = v
    of "model":    mdl  = v
    else: discard
  if mdl.len > 0: prov & "/" & mdl else: prov

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
    (FetchToolName,         FetchToolDescription,         FetchToolSchema),
    (WebSearchToolName,     WebSearchToolDescription,     WebSearchToolSchema),
    (CalcToolName,          CalcToolDescription,          CalcToolSchema),
    (RenderMermaidToolName, RenderMermaidToolDescription, RenderMermaidToolSchema),
    (InspectImageToolName,  InspectImageToolDescription,  InspectImageToolSchema),
    (AskToolName,           AskToolDescription,           AskToolSchema),
    (TodoWriteToolName,     TodoWriteToolDescription,     TodoWriteToolSchema),
    (CheckpointToolName,    CheckpointToolDescription,    CheckpointToolSchema),
    (RewindToolName,        RewindToolDescription,        RewindToolSchema),
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

proc loadSessionContext*(memory: MemoryRuntimePort; userId: UserId): SessionContext {.gcsafe.} =
  let ctx = memory.loadContext(userId)
  let homeDir = parentDir(parentDir(memory.paddockDir(userId)))
  SessionContext(
    preferencesMd: ctx.preferencesMd,
    paddockDir: memory.paddockDir(userId),
    providerLabel: providerLabelFromPrefs(ctx.preferencesMd),
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
  {.cast(gcsafe).}:
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

proc buildSessionCompleteFn*(preferencesMd: string;
                             fallbackCompleteFn: CompleteFn;
                             providerRuntimeBuilder: ProviderRuntimeBuilder): CompleteFn {.gcsafe.} =
  let primary = buildCompleteFn(preferencesMd, providerRuntimeBuilder)
  buildFallbackFn(primary, @[fallbackCompleteFn])

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
                            plan: SessionBootstrapPlan): SessionBootstrapPlan {.gcsafe.} =
  result = plan
  result.completeFn = buildSessionCompleteFn(
    plan.preferencesMd, fallbackCompleteFn, providerRuntimeBuilder)

func withSessionToolBundle*(toolBundle: SessionToolBundle;
                            plan: SessionBootstrapPlan): SessionBootstrapPlan =
  result = plan
  result.clients = toolBundle.clients
  result.tools = toolBundle.tools

func finalizeSessionBootstrap*(plan: SessionBootstrapPlan): SessionBootstrap =
  SessionBootstrap(
    completeFn: plan.completeFn,
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
                            skillRuntimeBuilder: SkillRuntimeBuilder;
                            skillRuntimePolicyResolver: SkillRuntimePolicyResolver;
                            toolClients: seq[ToolRuntimePort];
                            tools:       seq[ToolDescription]): SessionBootstrap {.gcsafe.} =
  let toolBundle = buildSessionToolBundle(
    memory, userId, skillRuntimeBuilder, skillRuntimePolicyResolver, toolClients, tools)
  result =
    (((loadSessionContext(memory, userId) |>
       loadSessionBootstrapPlan) |>->
       withSessionCompleteFn(completeFn, providerRuntimeBuilder)) |>->
       withSessionToolBundle(toolBundle)) |>
       finalizeSessionBootstrap
