## Command services backed by the markdown memory adapter: the effects the
## application command dispatcher reaches through `CommandServicesPort`
## (overview, diagnostics, status, ping, memory view, preference commands,
## skills). `newCommandServices` wraps each one so a failure, including an
## exception from file or provider I/O, comes back as `Result`.
##
## The /models, /think and /budget policy is not here: `app/preference_commands`
## runs it over the store and the catalog this module hands it.

import std/[os, strutils]
import ../../core/pipeops
import ../../core/utf8
import ../../core/commands/command_text
import ../../core/providers/smart_routing
import ../../app/channel_prefs_parse
import ../../adapters/memory/md_file
import ../../adapters/memory/channel_prefs_store
import ../../domain/message
import ../../ports/command_services
import ../../ports/provider
import ../../app/skill_runtime
import ../filesystem/fs_adapter
import ../../app/credential_runtime
import ../../app/preference_commands
import ./model_catalog_ui
import ../../app/task_board

when defined(withPostgres) or defined(withSqlite):
  import ../../adapters/memory/magma_memory_adapter

proc preferenceCommandDeps*(memory: MdFileAdapter;
                            modelCatalogLoader: ModelCatalogLoader = nil): PreferenceCommandDeps =
  ## The store and the catalog the /models, /think and /budget policy needs.
  PreferenceCommandDeps(
    readPreferences: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      memory.readPreferences(userId),
    savePreferences: proc(userId: UserId;
                          entries: seq[(string, string)]): Result[void, string] {.gcsafe.} =
      memory.saveChannelPreferences(userId, entries),
    catalogLoader: modelCatalogLoader,
    menu: currentModelMenu(),
    availability: detectProviderAvailability(),
  )

proc applySkillTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string;
                            homeDir = "";
                            registry = "";
                            searchBackend: skill_runtime.SkillSearchBackend = nil;
                            installBackend: skill_runtime.SkillInstallBackend = nil): Result[string, string] =
  skill_runtime.applySkillCommand(
    newFsAdapter(),
    memory.paddockDir(userId),
    value,
    homeDir = if homeDir.len > 0: homeDir else: memory.donkeyHomeDir(),
    registry = registry,
    searchBackend = searchBackend,
    installBackend = installBackend,
  )

proc buildProviderStatusLine*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  let doc = ? memory.readPreferences(userId).mapErr(preferencesUnreadableText)
  let current = ? tryParseChannelPrefs(doc).mapErr(preferencesUnreadableText)
  let prefs = parseSmartRoutingPrefs(doc)
  let availability = detectProviderAvailability()
  if prefs.usesSmartRouting:
    let preview = formatSelectionPreview(previewSmartRouteSelections(prefs, availability))
    if preview.len > 0:
      ok("Provider: auto [" & prefs.budgetPolicy & "] (" & preview & ")")
    else:
      ok("Provider: auto [" & prefs.budgetPolicy & "]")
  else:
    ok("Provider: " & current.provider & " / " & current.model)

proc buildTextStatusText*(memory: MdFileAdapter;
                          userId: UserId;
                          toolsCount: int;
                          sessionCount: int;
                          daemonStartMs: int64): Result[string, string] =
  ## Preferences first, so an unreadable PREFERENCES.md is reported as such;
  ## a memory file that cannot be read is an error too, never an exception.
  let providerLine = ? buildProviderStatusLine(memory, userId)
  let prefs = ? memory.loadChannelPrefs(userId).mapErr(preferencesUnreadableText)
  let memLines =
    try: memory.loadContext(userId).memoryMd.countLines()
    except CatchableError as e:
      return err("Não foi possível ler a memória: " & e.msg)
  let uptimeStr = formatUptime((nowMs() - daemonStartMs) div 1_000)
  ok "Status\n\n" &
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
                     sessionCount: int): Result[string, string] =
  let (prov, mdl) = ? memory.getCurrentProviderModel(userId).mapErr(preferencesUnreadableText)
  let storage =
    if credentialSet("DONKEY_PG_DSN") or memory.magmaDsn.len > 0:
      "PostgreSQL-backed MAGMA"
    elif memory.magmaSqlitePath.len > 0:
      "SQLite-first MAGMA (" & memory.magmaSqlitePath & ")"
    else:
      "Markdown paddocks"
  let webSearch =
    if credentialSet("BRAVE_API_KEY"): "enabled"
    else: "disabled"
  var channels: seq[string] = @[]
  if credentialSet("TELEGRAM_BOT_TOKEN"): channels.add("Telegram")
  if credentialSet("DISCORD_BOT_TOKEN"): channels.add("Discord")
  if credentialSet("WECOM_CORP_ID"): channels.add("WeCom")
  if credentialSet("WECHAT_APP_ID") or credentialSet("WECHAT_CALLBACK_TOKEN"): channels.add("WeChat")
  if credentialSet("FEISHU_APP_ID"): channels.add("Feishu")
  if credentialSet("QQ_ONEBOT_URL") or credentialSet("QQ_OFFICIAL_APP_ID"): channels.add("QQ")
  ok "🫏 *Donkey*\n\n" &
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
  
  ## Teste do provider ativo do usuário (não o default da instância). Sem
  ## as preferências não se sabe qual é: o relatório diz isso e segue.
  let userPrefs = memory.readPreferences(userId)
  let current = userPrefs.flatMap(tryParseChannelPrefs)
  if current.isErr:
    report.add("❌ Preferências: " & clipUtf8(current.error.strip, 300) & "\n")
  else:
    let t0 = nowMs()
    let testFn = completeBuilder(userPrefs.get)
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
    report.add("📦 Modelo: " & current.get.provider & " / " & current.get.model & "\n")

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
  if credentialSet("TELEGRAM_BOT_TOKEN"): channels.add("Telegram")
  if credentialSet("DISCORD_BOT_TOKEN"): channels.add("Discord")
  if credentialSet("FEISHU_APP_ID"): channels.add("Feishu")
  if credentialSet("WECOM_CORP_ID"): channels.add("WeCom")
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
    ("MISTRAL_API_KEY", "Mistral AI"),
    ("AWS_BEARER_TOKEN_BEDROCK", "AWS Bedrock"),
    ("DASHSCOPE_API_KEY", "Alibaba DashScope"),
    ("FIREWORKS_API_KEY", "Fireworks AI"),
    ("AZURE_OPENAI_API_KEY", "Azure OpenAI"),
  ]
  var configuredProviders: seq[string] = @[]
  for (envVar, name) in envVars:
    if credentialSet(envVar):
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
  let (prov, mdl) = ? memory.getCurrentProviderModel(userId).mapErr(preferencesUnreadableText)
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

proc taskBoardText*(memory: MdFileAdapter; userId: UserId): Result[string, string] =
  ## /tasks: the board in the person's paddock, as the agent keeps it.
  let board = ? loadBoard(newFsAdapter(), memory.paddockDir(userId))
  ok(renderMarkdown(board))

proc newCommandServices*(memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount, toolClientsCount: int;
                         daemonStartMs: int64;
                         skillRegistry = "";
                         editor: CommandArgFn = nil): CommandServicesPort =
  ## `skillRegistry` is where `/skill` searches and installs ("" is the
  ## public registry); the daemon passes `CLAWHUB_REGISTRY` from the snapshot.
  CommandServicesPort(
    about: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: buildAboutText(memory, userId, toolsCount, toolClientsCount, sessionCount),
    doctor: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: ok(buildDoctorReport(memory, completeBuilder, userId, toolsCount,
                                    toolClientsCount, sessionCount)),
    status: proc(userId: UserId; sessionCount: int): Result[string, string] {.gcsafe.} =
      guarded: buildTextStatusText(memory, userId, toolsCount, sessionCount,
                                   daemonStartMs),
    ping: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      guarded: pingProvider(memory, userId, completeBuilder),
    memoryView: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      guarded: buildMemoryViewText(memory, userId),
    taskBoard: proc(userId: UserId): Result[string, string] {.gcsafe.} =
      guarded: taskBoardText(memory, userId),
    editor: editor,
    clearMemory: proc(userId: UserId): Result[void, string] {.gcsafe.} =
      try:
        memory.clearMemory(userId)
      except CatchableError as e:
        err(e.msg),
    skill: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: applySkillTextCommand(memory, userId, value, registry = skillRegistry,
                                     homeDir = memory.donkeyHomeDir()),
    models: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: preferenceCommandDeps(memory, modelCatalogLoader)
                 .runModelsCommand(userId, value),
    think: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: preferenceCommandDeps(memory).runThinkCommand(userId, value),
    budget: proc(userId: UserId; value: string): Result[string, string] {.gcsafe.} =
      guarded: preferenceCommandDeps(memory).runBudgetCommand(userId, value),
    channelPrefs: proc(userId: UserId): Result[ChannelPrefs, string] {.gcsafe.} =
      guarded: memory.loadChannelPrefs(userId),
    savePreference: proc(userId: UserId; key, value: string): Result[void, string] {.gcsafe.} =
      try:
        memory.saveChannelPreference(userId, key, value)
      except CatchableError as e:
        err(e.msg),
    toolCounts: proc(): ToolCounts {.gcsafe.} =
      ToolCounts(tools: toolsCount, clients: toolClientsCount),
  )
