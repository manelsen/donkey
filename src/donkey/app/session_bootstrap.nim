## Session bootstrap helpers.
##
## Concentrates provider selection, fallback composition, per-user skill merge
## and native tool exposure so the daemon entrypoint only coordinates lifecycle.

import std/[algorithm, json, os, strutils]
import chronos
import ../config/skills_registry
import ../config/clawhub_registry
import ../core/pipeops
import ../core/providers/smart_routing
import ./channel_prefs_parse
import ../core/providers/credential_pool
import ../domain/providers/descriptors
import ./credential_runtime
export credential_runtime.detectProviderAvailability
import ../domain/agent_message
import ../domain/message
import ../domain/channels/telegram_pure
import ../domain/builtin_tools
import ../domain/more_tools
import ../domain/providers/media_pure
import ../domain/reminder
import ../ports/attachment_store
import ../ports/memory
import ../ports/provider
import ../ports/subagent_workspace
import ../ports/tool
import ./metrics
import ./provider_executor
export provider

const
  RecentContextMessageLimit* = 5

type
  CredentialResultHook* = proc(providerName, key: string; ok: bool;
                               error: string) {.gcsafe.}
  CredentialNextHook* = proc(providerName, currentKey: string): string {.gcsafe.}

type
  ProviderDefaults* = object
    providerName*: string
    modelName*: string

  SessionToolBundle* = object
    clients*: seq[ToolRuntimePort]
    tools*:   seq[ToolDescription]

  SessionBootstrap* = object
    completeFn*:    CompleteFn
    asyncCompleteFn*: AsyncCompleteFn
    errorExplainFn*: CompleteFn
    paddockDir*:    string
    clients*:       seq[ToolRuntimePort]
    tools*:         seq[ToolDescription]
    providerLabel*: string
    skillPrompt*:   string
    subagentWorkspace*: SubagentWorkspacePort

  SessionBootstrapPlan* = object
    preferencesMd*: string
    paddockDir*:    string
    completeFn*:    CompleteFn
    asyncCompleteFn*: AsyncCompleteFn
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
  ## Identity and credential come from the descriptor table; routing names and
  ## aliases are normalized there. Unknown providers keep the zai-coding
  ## fallback.
  let descriptor = descriptorOr(prefs.providerName)
  ProviderSpec(
    providerName: descriptor.id,
    modelName: if prefs.modelName.len > 0: prefs.modelName
               else: descriptor.defaultModel,
    apiKey: descriptorApiKey(descriptor),
    baseUrl: descriptorBaseUrl(descriptor),
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

func availableProviderNames*(av: ProviderAvailability): seq[string] =
  ## Names of providers that currently have credentials/endpoints configured.
  ## Kept pure so the daemon can report status without leaking secrets.
  if av.openrouter: result.add("openrouter")
  if av.anthropic: result.add("anthropic")
  if av.openai: result.add("openai")
  if av.deepseek: result.add("deepseek")
  if av.zaiAnthropic: result.add("zai-anthropic")
  if av.gemini: result.add("gemini")
  if av.minimax: result.add("minimax")
  if av.zai: result.add("zai")
  if av.zaiCoding: result.add("zai-coding")
  if av.groq: result.add("groq")
  if av.ollama: result.add("ollama")
  if av.nvidia: result.add("nvidia")
  if av.alibaba: result.add("alibaba")
  if av.fireworks: result.add("fireworks")

proc toProviderSpec*(selection: ProviderSelection): ProviderSpec =
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
    var attemptReq = req
    # The single image retry lives in runToolLoop; do not enable it again here.
    var retriedWithoutImages = true
    while true:
      var lastErr = "no provider available"
      var attempted = false
      var allImageRejections = true
      for selection in costAwareSelections:
        if routingHook != nil:
          try: routingHook(selection, prefs, attemptReq)
          except CatchableError: discard
        let startedAt = nowMs()
        let bundle = providerRuntimeBuilder(selection.toProviderSpec)
        if bundle.completeFn == nil:
          continue
        attempted = true
        let response = bundle.completeFn(attemptReq)
        let elapsedMs = nowMs() - startedAt
        recordLatency(selection.providerName, float(elapsedMs))
        if response.isErr:
          recordError(selection.providerName)
        if routingResultHook != nil:
          try: routingResultHook(selection, elapsedMs, response.isOk)
          except CatchableError: discard
        if response.isOk:
          return response
        lastErr = response.error
        if not isImageRejection(response.error):
          allImageRejections = false
      ## A provider without vision refuses the inline image: retry the same
      ## selections once as text instead of failing the turn.
      if not retriedWithoutImages and attempted and allImageRejections and
         hasInlineImages(attemptReq):
        retriedWithoutImages = true
        attemptReq = withoutInlineImages(attemptReq)
        continue
      return err(lastErr)

func asyncCompleteErr(msg: string): Result[CompletionResponse, string] {.gcsafe.} =
  err(msg)

proc buildAsyncCompleteFn*(preferencesMd: string;
                             providerRuntimeBuilder: ProviderRuntimeBuilder;
                             routingHook: RoutingTelemetryHook = nil;
                             routingResultHook: RoutingResultHook = nil;
                             routingFeedbackHook: RoutingFeedbackHook = nil;
                             routingCostHook: RoutingCostHook = nil;
                             routingProviderCooldownHook: RoutingProviderCooldownHook = nil;
                             credentialResultHook: CredentialResultHook = nil;
                             credentialNextHook: CredentialNextHook = nil;
                             fallbackCompleteFn: CompleteFn = nil
                            ): AsyncCompleteFn {.gcsafe.} =
  ## Async twin of buildCompleteFn: selection/hooks run on the event loop,
  ## while only the provider call itself runs on a worker.
  let prefs = parseSmartRoutingPrefs(preferencesMd)
  let availability = detectProviderAvailability()
  result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
    let baseSelections = smartRouteSelections(prefs, req, availability)
    var feedback: seq[RouteFeedback] = @[]
    if routingFeedbackHook != nil:
      try: feedback = routingFeedbackHook()
      except Exception: feedback = @[]  ## effect boundary: callee raises are unannotated
    let rankedSelections =
      if routingFeedbackHook != nil:
        reorderSelectionsWithFeedback(baseSelections, feedback)
      else:
        baseSelections
    let selections =
      if routingFeedbackHook != nil:
        applyCircuitBreaker(rankedSelections, feedback)
      else:
        rankedSelections
    let providerHealthySelections =
      if routingFeedbackHook != nil:
        applyProviderCircuitBreaker(selections, feedback)
      else:
        selections
    var cooldowns: seq[ProviderCooldown] = @[]
    if routingProviderCooldownHook != nil:
      try: cooldowns = routingProviderCooldownHook()
      except Exception: cooldowns = @[]  ## effect boundary: callee raises are unannotated
    let cooldownFilteredSelections =
      if routingProviderCooldownHook != nil:
        applyProviderCooldowns(providerHealthySelections, cooldowns, nowMs() div 1000)
      else:
        providerHealthySelections
    var costs: seq[RouteCostHint] = @[]
    if routingCostHook != nil:
      try: costs = routingCostHook()
      except Exception: costs = @[]  ## effect boundary: callee raises are unannotated
    let costAwareSelections =
      if routingCostHook != nil:
        reorderSelectionsWithCost(cooldownFilteredSelections, costs, prefs.budgetPolicy)
      else:
        cooldownFilteredSelections
    var attemptReq = req
    # The single image retry lives in runToolLoop; do not enable it again here.
    var retriedWithoutImages = true
    while true:
      var lastErr = "no provider available"
      var attempted = false
      var allImageRejections = true
      for selection in costAwareSelections:
        var spec = selection.toProviderSpec
        var tried: seq[string] = @[]
        while true:
          tried.add(spec.apiKey)
          if routingHook != nil:
            try: routingHook(selection, prefs, attemptReq)
            except Exception: discard  ## effect boundary: callee raises are unannotated
          let startedAt = nowMs()
          var response: Result[CompletionResponse, string]
          try:
            response = await asyncProviderComplete(
              providerRuntimeBuilder, spec, attemptReq)
          except CancelledError:
            raise
          except CatchableError as e:
            response = asyncCompleteErr(e.msg)
          attempted = true
          let elapsedMs = nowMs() - startedAt
          recordLatency(selection.providerName, float(elapsedMs))
          if response.isErr:
            recordError(selection.providerName)
          if routingResultHook != nil:
            try: routingResultHook(selection, elapsedMs, response.isOk)
            except Exception: discard  ## effect boundary: callee raises are unannotated
          if credentialResultHook != nil and spec.apiKey.len > 0:
            try:
              credentialResultHook(selection.providerName, spec.apiKey,
                                   response.isOk,
                                   (if response.isErr: response.error else: ""))
            except Exception: discard  ## effect boundary: callee raises are unannotated
          if response.isOk:
            return response
          lastErr = response.error
          if not isImageRejection(response.error):
            allImageRejections = false
          ## Another key can fix auth/rate/quota failures; transport and payload
          ## errors must not burn through the pool.
          if credentialNextHook == nil or
             not isRetryableCredentialError(response.error):
            break
          let nextKey =
            try: credentialNextHook(selection.providerName, spec.apiKey)
            except Exception: ""  ## effect boundary: callee raises are unannotated
          if nextKey.len == 0 or nextKey in tried:
            break
          spec = spec.withApiKey(nextKey)
      ## Same one-shot text retry as the sync path: the channel, the API and
      ## subagents all reach the provider through here.
      if not retriedWithoutImages and attempted and allImageRejections and
         hasInlineImages(attemptReq):
        retriedWithoutImages = true
        attemptReq = withoutInlineImages(attemptReq)
        continue
      if fallbackCompleteFn != nil:
        ## If every selection refused the inline image, do not hand that same
        ## image to the fallback: its error (a 503, say) would not look like an
        ## image rejection, and the turn-level retry would never run. Surface
        ## the rejection so the turn retries once in text — and only then may
        ## the fallback be used.
        if allImageRejections and hasInlineImages(attemptReq):
          return err(lastErr)
        try:
          return fallbackCompleteFn(attemptReq)
        except Exception as e:  ## effect boundary: callee raises are unannotated
          return asyncCompleteErr(e.msg)
      return err(lastErr)

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
  ## `mediaPaths` stays index-aligned with `mediaUrl`/`mediaUrls`: the turn
  ## builder needs the disk path of every inline image so it can present the
  ## ones beyond the inline cap as path-only attachments instead of dropping
  ## them. Payloads without `mediaPaths` are legacy and keep their text marker.
  var mediaPaths: seq[string] = @[]
  if msg.mediaUrl.len > 0 and msg.mediaFileName.startsWith(AttachmentDirName & "/"):
    mediaPaths.add(msg.mediaFileName)
  if msg.mediaUrl.len == 0 and recentContext.len == 0:
    return msg.text
  $(%* {"text": msg.text, "mediaUrl": msg.mediaUrl,
        "mediaPaths": mediaPaths,
        "mediaGroupId": msg.mediaGroupId, "recentContext": recentContext})

func sessionReplyTo*(msg: InboundMessage): string =
  case msg.channel
  of ckTelegram:
    telegramReplyTarget(msg.chatId, msg.channelId, msg.threadId)
  of ckDiscord:
    if msg.channelId.len > 0: "channel:" & msg.channelId else: ""
  of ckLine:
    msg.chatId
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

proc nativeSessionTools*(): seq[ToolDescription] {.gcsafe, raises: [].} =
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
    (ExecuteCodeToolName,   ExecuteCodeToolDescription,   ExecuteCodeToolSchema),
    (FetchToolName,         FetchToolDescription,         FetchToolSchema),
    (CalcToolName,          CalcToolDescription,          CalcToolSchema),
    (RenderMermaidToolName, RenderMermaidToolDescription, RenderMermaidToolSchema),
    (InspectImageToolName,  InspectImageToolDescription,  InspectImageToolSchema),
    (TranscribeAudioToolName, TranscribeAudioToolDescription, TranscribeAudioToolSchema),
    (TextToSpeechToolName,  TextToSpeechToolDescription,  TextToSpeechToolSchema),
    (AskToolName,           AskToolDescription,           AskToolSchema),
    (TodoWriteToolName,     TodoWriteToolDescription,     TodoWriteToolSchema),
    (CheckpointToolName,    CheckpointToolDescription,    CheckpointToolSchema),
    (RewindToolName,        RewindToolDescription,        RewindToolSchema),
    (ManageSkillsToolName,  ManageSkillsToolDescription,  ManageSkillsToolSchema),
    (SessionSearchToolName, SessionSearchToolDescription, SessionSearchToolSchema),
    (MemoryIngestToolName,  MemoryIngestToolDescription,  MemoryIngestToolSchema),
    (TaskToolName,          TaskToolDescription,          TaskToolSchema),
    (SubmitResultToolName,  SubmitResultToolDescription,  SubmitResultToolSchema),
    (ReportFindingToolName, ReportFindingToolDescription, ReportFindingToolSchema),
    (CancelJobToolName,     CancelJobToolDescription,     CancelJobToolSchema),
    (AwaitToolName,         AwaitToolDescription,         AwaitToolSchema),
    (SpawnSubagentToolName, SpawnSubagentToolDescription, SpawnSubagentToolSchema),
    (AwaitSubagentToolName, AwaitSubagentToolDescription, AwaitSubagentToolSchema),
    (ListSubagentsToolName, ListSubagentsToolDescription, ListSubagentsToolSchema),
    (CancelSubagentToolName, CancelSubagentToolDescription, CancelSubagentToolSchema),
  ]:
    result.add(ToolDescription(name: n, description: d, schemaJson: s))
  if webSearchKey().len > 0:
    result.add(ToolDescription(
      name: WebSearchToolName,
      description: WebSearchToolDescription,
      schemaJson: WebSearchToolSchema,
    ))

proc addNativeSessionTools*(tools: seq[ToolDescription]): seq[ToolDescription] {.gcsafe, raises: [].} =
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

proc withNativeTools*(toolBundle: SessionToolBundle): SessionToolBundle {.gcsafe, raises: [].} =
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
  if providerRuntimeBuilder != nil:
    result.asyncCompleteFn = buildAsyncCompleteFn(
      applyProviderDefaults(memory.loadContext(userId).preferencesMd, providerDefaults),
      providerRuntimeBuilder, routingHook, routingResultHook,
      routingFeedbackHook, routingCostHook, routingProviderCooldownHook,
      credentialResultHook = proc(providerName, key: string; ok: bool;
                                  error: string) {.gcsafe.} =
        noteCredentialResult(providerName, key, ok, error),
      credentialNextHook = proc(providerName, currentKey: string): string {.gcsafe.} =
        nextCredentialKey(providerName, currentKey),
      fallbackCompleteFn = fallbackCompleteFn)
  result.errorExplainFn = fallbackCompleteFn

func withSessionToolBundle*(toolBundle: SessionToolBundle;
                            plan: SessionBootstrapPlan): SessionBootstrapPlan =
  result = plan
  result.clients = toolBundle.clients
  result.tools = toolBundle.tools

func finalizeSessionBootstrap*(plan: SessionBootstrapPlan): SessionBootstrap =
  SessionBootstrap(
    completeFn: plan.completeFn,
    asyncCompleteFn: plan.asyncCompleteFn,
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
                            routingProviderCooldownHook: RoutingProviderCooldownHook = nil;
                            subagentWorkspace: SubagentWorkspacePort = SubagentWorkspacePort()): SessionBootstrap {.gcsafe.} =
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
  result.subagentWorkspace = subagentWorkspace
