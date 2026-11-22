## Command services backed by the markdown memory adapter: the effects the
## application command dispatcher reaches through `CommandServicesPort`
## (overview, diagnostics, status, ping, memory view, preference commands,
## skills). `newCommandServices` wraps each one so a failure, including an
## exception from file or provider I/O, comes back as `Result`.

import std/[os, sequtils, strutils]
import ../../core/pipeops
import ../../core/utf8
import ../../core/commands/command_text
import ../../core/providers/smart_routing
import ../../adapters/memory/md_file
import ../../adapters/memory/channel_prefs_store
import ../../domain/message
import ../../ports/command_services
import ../../ports/provider
import ../../app/skill_runtime
import ./model_catalog_ui

when defined(withPostgres) or defined(withSqlite):
  import ../../adapters/memory/magma_memory_adapter

func availableProvidersFromEnv*(): ProviderAvailability =
  ## Credential presence for the channel status line. Exported so the surface
  ## tests can assert it without a message loop.
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
    nvidia: getEnv("NVIDIA_API_KEY").len > 0,
    alibaba: getEnv("DASHSCOPE_API_KEY").len > 0,
    fireworks: getEnv("FIREWORKS_API_KEY").len > 0,
  )

proc buildModelsHelpText*(memory: MdFileAdapter;
                          userId: UserId;
                          modelCatalogLoader: ModelCatalogLoader = nil): string =
  let prefs = parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd)
  let availability = availableProvidersFromEnv()
  let (provider, model) = memory.getCurrentProviderModel(userId)
  let providerText = supportedProviders().join(", ")
  var text =
    if prefs.usesSmartRouting:
      "Provider atual: auto [" & prefs.budgetPolicy & "]"
    else:
      "Provider atual: " & provider
  if model.len > 0 and not prefs.usesSmartRouting:
    text.add(" / " & model)
  if prefs.usesSmartRouting:
    let preview = formatSelectionPreview(previewSmartRouteSelections(prefs, availability))
    if preview.len > 0:
      text.add("\nRota base: " & preview)
  text.add("\n\nProviders: " & providerText)
  var catalogInfo = ""
  let currentModels =
    if modelCatalogLoader != nil:
      let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
      let sorted = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
      catalogInfo = buildCatalogSourceText(catalog)
      if sorted.len > 0: sorted.mapIt(it.modelName) else: supportedModels(provider)
    else:
      supportedModels(provider)
  if currentModels.len > 0:
    text.add("\nModelos para `" & provider & "`: " & currentModels.join(", "))
  if catalogInfo.len > 0:
    text.add("\n" & catalogInfo)
  text.add("\n\nUse `/models <provider> <model>` para trocar.")
  text

proc buildThinkHelpText*(memory: MdFileAdapter; userId: UserId): string =
  "Thinking atual: " & memory.getCurrentThinkLevel(userId) &
  "\nNíveis: " & ThinkLevels.join(", ") &
  "\n\nUse `/think <level>` para trocar."

proc buildBudgetHelpText*(memory: MdFileAdapter; userId: UserId): string =
  "Budget atual: " & memory.getCurrentBudgetPolicy(userId) &
  "\nPolicies: " & BudgetPolicies.join(", ") &
  "\n\nUse `/budget <policy>` para trocar."

proc applyModelsTextCommand*(memory: MdFileAdapter;
                             userId: UserId;
                             value: string;
                             modelCatalogLoader: ModelCatalogLoader = nil): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildModelsHelpText(userId, modelCatalogLoader))
  let parts = value.splitWhitespace()
  if parts.len == 1:
    let provider = parts[0]
    if provider notin supportedProviders():
      return err("Provider inválido: `" & provider & "`.")
    if modelCatalogLoader != nil:
      let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
      return ok(buildProviderCatalogText(provider, catalog))
    let entries = supportedModels(provider).mapIt(
      ModelCatalogEntry(providerName: provider, modelName: it, label: it, isFree: false, available: true))
    return ok(buildProviderCatalogText(
      provider,
      ModelCatalogResult(entries: entries, source: mcsFallback, fetchedAtUnix: 0)))
  ## The selection is checked against the catalog `/models <provider>`
  ## shows; the static list applies only when no catalog was loaded.
  let (provider, model) = ? parseModelsSelection(value)
  var loaded: seq[ModelCatalogEntry]
  if modelCatalogLoader != nil:
    let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
    loaded = normalizeModelCatalog(provider, catalog.entries)
  if loaded.len > 0:
    if loaded.allIt(it.modelName != model):
      return err("Modelo indisponível agora para `" & provider & "`: `" & model & "`.")
  else:
    discard ? parseModelsArgs(value)
  ? memory.saveChannelPreferences(userId, [("provider", provider), ("model", model)])
  ok("Modelo definido: " & provider & " / " & model)

proc applyThinkTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildThinkHelpText(userId))
  let level = ? parseThinkArgs(value)
  ? memory.saveChannelPreference(userId, "thinking", level)
  ok("Thinking definido: " & level)

proc applyBudgetTextCommand*(memory: MdFileAdapter;
                             userId: UserId;
                             value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildBudgetHelpText(userId))
  let policy = ? parseBudgetArgs(value)
  ? memory.saveChannelPreference(userId, "budget", policy)
  ok("Budget definido: " & policy)

proc applySkillTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string;
                            homeDir = "";
                            registry = "";
                            searchBackend: skill_runtime.SkillSearchBackend = nil;
                            installBackend: skill_runtime.SkillInstallBackend = nil): Result[string, string] =
  skill_runtime.applySkillCommand(
    memory.paddockDir(userId),
    value,
    homeDir = if homeDir.len > 0: homeDir else: memory.donkeyHomeDir(),
    registry = registry,
    searchBackend = searchBackend,
    installBackend = installBackend,
  )

proc buildProviderStatusLine*(memory: MdFileAdapter; userId: UserId): string =
  let prefs = parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd)
  let availability = availableProvidersFromEnv()
  let (provider, model) = memory.getCurrentProviderModel(userId)
  if prefs.usesSmartRouting:
    let preview = formatSelectionPreview(previewSmartRouteSelections(prefs, availability))
    if preview.len > 0:
      "Provider: auto [" & prefs.budgetPolicy & "] (" & preview & ")"
    else:
      "Provider: auto [" & prefs.budgetPolicy & "]"
  else:
    "Provider: " & provider & " / " & model

proc buildTextStatusText*(memory: MdFileAdapter;
                          userId: UserId;
                          toolsCount: int;
                          sessionCount: int;
                          daemonStartMs: int64): string =
  let ctx = memory.loadContext(userId)
  let memLines = ctx.memoryMd.countLines()
  let uptimeStr = formatUptime((nowMs() - daemonStartMs) div 1_000)
  let providerLine = buildProviderStatusLine(memory, userId)
  let prefs = memory.loadChannelPrefs(userId)
  "Status\n\n" &
    providerLine & "\n" &
    "Thinking: " & prefs.thinking & "\n" &
    "Reasoning: " & prefs.reasoning & "\n" &
    "Tools: " & $toolsCount & "\n" &
    "Sessões ativas: " & $sessionCount & "\n" &
    "Memórias: " & $memLines & " linhas\n" &
    "Uptime: " & uptimeStr

proc buildAboutText*(memory: MdFileAdapter;
                     userId: UserId;
                     toolsCount: int;
                     toolClientsCount: int;
                     sessionCount: int): string =
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  let storage =
    if getEnv("DONKEY_PG_DSN").strip.len > 0 or memory.magmaDsn.len > 0:
      "PostgreSQL-backed MAGMA"
    elif memory.magmaSqlitePath.len > 0:
      "SQLite-first MAGMA (" & memory.magmaSqlitePath & ")"
    else:
      "Markdown paddocks"
  let webSearch =
    if getEnv("BRAVE_API_KEY").len > 0: "enabled"
    else: "disabled"
  var channels: seq[string] = @[]
  if getEnv("TELEGRAM_BOT_TOKEN").len > 0: channels.add("Telegram")
  if getEnv("DISCORD_BOT_TOKEN").len > 0: channels.add("Discord")
  if getEnv("WECOM_CORP_ID").len > 0: channels.add("WeCom")
  if getEnv("WECHAT_APP_ID").len > 0 or getEnv("WECHAT_CALLBACK_TOKEN").len > 0: channels.add("WeChat")
  if getEnv("FEISHU_APP_ID").len > 0: channels.add("Feishu")
  if getEnv("QQ_ONEBOT_URL").len > 0 or getEnv("QQ_OFFICIAL_APP_ID").len > 0: channels.add("QQ")
  "🫏 *Donkey*\n\n" &
    "*Provider atual:* `" & prov & " / " & mdl & "`\n" &
    "*Storage:* " & storage & "\n" &
    "*Web search:* " & webSearch & "\n" &
    "*Channels ativos:* " & (if channels.len > 0: channels.join(", ") else: "nenhum") & "\n" &
    "*Ferramentas:* " & $toolsCount & " nativas, " & $toolClientsCount & " clientes MCP\n" &
    "*Sessões ativas:* " & $sessionCount & "\n\n" &
    "Use `/doctor` para checagem completa, `/status` para a sessão atual e `/memory` para ver memória."

proc buildDoctorReport*(memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        userId: UserId;
                        toolsCount: int;
                        toolClientsCount: int;
                        sessionCount: int): string =
  var report = "🩺 Donkey Doctor\n\n"
  
  ## Teste do provider ativo do usuário (não o default da instância)
  let t0 = nowMs()
  let userPrefs = memory.loadContext(userId).preferencesMd
  let testFn = completeBuilder(userPrefs)
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = testFn(req)
  let delta = nowMs() - t0
  if resp.isOk:
    report.add("✅ Provider: OK (" & $delta & "ms)\n")
  else:
    let clipped = clipUtf8(resp.error.strip, 300)
    report.add("❌ Provider: " & clipped & "\n")
  
  ## Modelo atual
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  report.add("📦 Modelo: " & prov & " / " & mdl & "\n")

  when defined(withPostgres) or defined(withSqlite):
    if memory.hasMagmaBackend:
      try:
        let magma = memory.newMagmaAdapter()
        let stats = magma.stats()
        report.add(
          "🧠 Multigraph Memory: nodes=" & $stats.totalNodes &
          " memory=" & $stats.memoryNodes &
          " profiles=" & $stats.profileNodes &
          " prefs=" & $stats.preferenceNodes &
          " entities=" & $stats.entityNodes &
          " embeddings=" & $stats.embeddingNodes &
          " edges=" & $stats.totalEdges & "\n"
        )
      except CatchableError:
        report.add("❌ Multigraph Memory: failed to read graph stats\n")
  
  ## Diretório de memória
  let mpath = memory.paddocksDir
  if dirExists(mpath):
    var size = 0
    try:
      for kind, path in walkDir(mpath):
        inc size
    except OSError:
      discard
    report.add("📁 Memory dir (debug): " & mpath & " (" & $size & " arquivos)\n")
  else:
    report.add("❌ Memory dir missing (debug): " & mpath & "\n")
  
  ## Tools e MCP
  report.add("🔧 Tools loaded: " & $toolsCount & "\n")
  report.add("🔌 MCP clients: " & $toolClientsCount & "\n")
  
  ## Sessões ativas
  report.add("👥 Active sessions: " & $sessionCount & "\n")
  
  ## Canais ativos (verifica identidade)
  var channels: seq[string] = @[]
  if getEnv("TELEGRAM_BOT_TOKEN").len > 0: channels.add("Telegram")
  if getEnv("DISCORD_BOT_TOKEN").len > 0: channels.add("Discord")
  if getEnv("FEISHU_APP_ID").len > 0: channels.add("Feishu")
  if getEnv("WECOM_CORP_ID").len > 0: channels.add("WeCom")
  if channels.len > 0:
    report.add("📡 Active channels: " & channels.join(", ") & "\n")
  else:
    report.add("📡 Active channels: nenhum\n")
  
  ## Environment checks
  let envVars = [
    ("OPENROUTER_API_KEY", "OpenRouter"),
    ("ZAI_API_KEY", "Zhipu"),
    ("ANTHROPIC_API_KEY", "Anthropic"),
    ("OPENAI_API_KEY", "OpenAI"),
    ("DEEPSEEK_API_KEY", "DeepSeek"),
    ("GROQ_API_KEY", "Groq"),
    ("GEMINI_API_KEY", "Gemini"),
    ("MINIMAX_API_KEY", "MiniMax"),
    ("NVIDIA_API_KEY", "NVIDIA NIM"),
    ("DASHSCOPE_API_KEY", "Alibaba DashScope"),
    ("FIREWORKS_API_KEY", "Fireworks AI"),
  ]
  var configuredProviders: seq[string] = @[]
  for (envVar, name) in envVars:
    if getEnv(envVar).len > 0:
      configuredProviders.add(name)
  if configuredProviders.len > 0:
    report.add("🔑 API keys: " & configuredProviders.join(", ") & "\n")
  else:
    report.add("🔑 API keys: nenhuma configurada\n")
  
  report

proc buildMemoryBootstrapSnapshot(userMd, preferencesMd, sourceLabel: string): string =
  var sections: seq[string]
  if sourceLabel.len > 0:
    sections.add(sourceLabel)
  if userMd.strip.len > 0:
    sections.add("👤 Perfil\n" & userMd.strip)
  if preferencesMd.strip.len > 0:
    sections.add("⚙️ Preferências\n" & preferencesMd.strip)
  sections.add("📝 Memória episódica\nNenhuma memória salva ainda.")
  sections.join("\n\n")

proc clearMemoryReply*(memory: MdFileAdapter; userId: UserId;
                       cleared = "Memórias apagadas."): string =
  ## Clears the user's memory and returns what to tell them. The reply only
  ## confirms what happened: when nothing was cleared it says so.
  let res = memory.clearMemory(userId)
  if res.isOk: cleared
  else: "Não foi possível apagar as memórias: " & res.error

proc readMemoryFile(path: string): Result[string, string] =
  ## "" for a file that does not exist; an error for one that cannot be read.
  if not fileExists(path):
    return ok("")
  try:
    ok(readFile(path).strip)
  except IOError, OSError:
    err("não foi possível ler " & path.extractFilename & ": " & getCurrentExceptionMsg())

proc buildMemoryViewText*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  ## With MAGMA the graph is read first; the Markdown files are read only
  ## when the view falls back to them, so an unreadable export does not
  ## fail /memory while the graph holds the memory.
  template readMarkdown() {.dirty.} =
    let markdownText = ? readMemoryFile(memory.memoryMdPath(userId))
    let markdownUserText = ? readMemoryFile(memory.userMdPath(userId))
    let markdownPrefsText = ? readMemoryFile(memory.preferencesMdPath(userId))
  when defined(withPostgres) or defined(withSqlite):
    if memory.hasMagmaBackend:
      try:
        let magma = memory.newMagmaAdapter()
        let graphCtx = magma.loadContext(userId)
        let graphText = graphCtx.memoryMd.strip
        if graphText.len > 0:
          return ok("🧠 Multigraph Memory\n" & graphText)
        if graphCtx.userMd.strip.len > 0 or graphCtx.preferencesMd.strip.len > 0:
          return ok(buildMemoryBootstrapSnapshot(
            graphCtx.userMd,
            graphCtx.preferencesMd,
            "🧠 Multigraph Memory",
          ))
      except CatchableError:
        discard
      readMarkdown()
      if markdownText.len > 0:
        return ok("📄 Markdown fallback\n" & markdownText)
      if markdownUserText.len > 0 or markdownPrefsText.len > 0:
        return ok(buildMemoryBootstrapSnapshot(
          markdownUserText,
          markdownPrefsText,
          "📄 Markdown fallback",
        ))
      return ok("Nenhuma memória salva ainda.")
  readMarkdown()
  if markdownText.len > 0:
    return ok(markdownText)
  if markdownUserText.len > 0 or markdownPrefsText.len > 0:
    return ok(buildMemoryBootstrapSnapshot(markdownUserText, markdownPrefsText, ""))
  ok("Nenhuma memória salva ainda.")

proc pingProvider*(memory: MdFileAdapter;
                   userId: UserId;
                   completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}):
                   Result[string, string] =
  ## Round-trip to the user's provider: the pong line, or the error line.
  let t0 = nowMs()
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  let pingFn = completeBuilder("provider = \"" & prov & "\"\nmodel = \"" & mdl & "\"")
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = pingFn(req)
  let delta = nowMs() - t0
  if resp.isOk: ok(formatPingText(prov, mdl, delta))
  else: err(formatPingText(prov, mdl, delta, resp.error))

proc buildPingText*(memory: MdFileAdapter;
                    userId: UserId;
                    completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}): string =
  let res = pingProvider(memory, userId, completeBuilder)
  if res.isOk: res.get else: res.error

template guarded(body: untyped): untyped =
  ## Port calls never raise: file and provider I/O failures become `err`.
  try:
    body
  except CatchableError as e:
    err(e.msg)

proc newCommandServices*(memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount, toolClientsCount: int;
                         daemonStartMs: int64): CommandServicesPort =
  CommandServicesPort(
    about: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: ok(buildAboutText(memory, userId, toolsCount, toolClientsCount, sessionCount)),
    doctor: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: ok(buildDoctorReport(memory, completeBuilder, userId, toolsCount,
                                    toolClientsCount, sessionCount)),
    status: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: ok(buildTextStatusText(memory, userId, toolsCount, sessionCount,
                                      daemonStartMs)),
    ping: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      guarded: pingProvider(memory, userId, completeBuilder),
    memoryView: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      guarded: buildMemoryViewText(memory, userId),
    clearMemory: proc(userId: UserId): Result[void, string] {.gcsafe.} =
      try:
        memory.clearMemory(userId)
      except CatchableError as e:
        err(e.msg),
    skill: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: applySkillTextCommand(memory, userId, value,
                                     homeDir = memory.donkeyHomeDir()),
    models: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: applyModelsTextCommand(memory, userId, value, modelCatalogLoader),
    think: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: applyThinkTextCommand(memory, userId, value),
    budget: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: applyBudgetTextCommand(memory, userId, value),
    channelPrefs: proc(userId: UserId): Result[ChannelPrefs, string] {.gcsafe.} =
      try:
        ok(memory.loadChannelPrefs(userId))
      except CatchableError as e:
        err(e.msg),
    savePreference: proc(userId: UserId; key, value: string): Result[void, string] {.gcsafe.} =
      try:
        memory.saveChannelPreference(userId, key, value)
      except CatchableError as e:
        err(e.msg),
    toolsCount: toolsCount,
    toolClientsCount: toolClientsCount,
  )
