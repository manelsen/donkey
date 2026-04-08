## Unified command catalog with metadata for all command surfaces.

import std/[json, options, sequtils, strutils]
import command_routing

type
  CommandCategory* = enum
    ccNavigation
    ccConfiguration
    ccStatus
    ccMemory
    ccSession
    ccTools
    ccHelp

  CommandSurface* = enum
    csMenu
    csHelp
    csTelegram
    csDiscord

  DiscordOptionMetadata* = object
    name*:        string
    description*: string
    kind*:        int
    required*:    bool

  CommandSection* = object
    title*: string
    categories*: seq[CommandCategory]

  CommandMetadata* = object
    kind*: CommandKind
    name*: string
    description*: string
    usage*: string
    textUsage*: string
    menuSummary*: string
    helpSummary*: string
    helpSummaryInteractive*: string
    telegramDescription*: string
    discordDescription*: string
    discordOptions*: seq[DiscordOptionMetadata]
    menuDetails*: seq[string]
    publishedOn*: set[CommandSurface]
    category*: CommandCategory
    requiresArgs*: bool
    route*: CommandRoute

  CommandCatalog* = object
    commands*: seq[CommandMetadata]

const
  SkillCommandMenuDetails* = @[
    "/skill list — mostra skills habilitadas para você e bundles remotos instalados",
    "/skill search <query> — busca skills remotas no ClawHub",
    "/skill install <slug> — baixa e habilita uma skill remota para você",
    "/skill enable <slug> — habilita para você uma skill remota já instalada",
    "/skill disable <name> — desabilita uma skill do seu runtime",
    "/skill read <slug> — lê o SKILL.md de uma skill instalada",
  ]

  PublishedEverywhere = {csMenu, csHelp, csTelegram, csDiscord}

func categoryNamePt*(cat: CommandCategory): string =
  case cat
  of ccNavigation: "Navegação"
  of ccConfiguration: "Configuração"
  of ccStatus: "Status"
  of ccMemory: "Memória"
  of ccSession: "Sessão"
  of ccTools: "Ferramentas"
  of ccHelp: "Ajuda"

func commandToken*(cmd: CommandMetadata): string =
  if cmd.name.len > 0 and cmd.name[0] == '/':
    cmd.name[1 .. ^1]
  else:
    cmd.name

func usageFor*(cmd: CommandMetadata; interactiveUi: bool): string =
  if interactiveUi or cmd.textUsage.len == 0:
    if cmd.usage.len > 0: cmd.usage else: cmd.name
  else:
    cmd.textUsage

func helpSummaryFor*(cmd: CommandMetadata; interactiveUi: bool): string =
  if interactiveUi and cmd.helpSummaryInteractive.len > 0:
    cmd.helpSummaryInteractive
  elif cmd.helpSummary.len > 0:
    cmd.helpSummary
  else:
    cmd.menuSummary

func isPublishedOn*(cmd: CommandMetadata; surface: CommandSurface): bool =
  surface in cmd.publishedOn

func getBySurface*(catalog: CommandCatalog; surface: CommandSurface): seq[CommandMetadata] =
  result = @[]
  for cmd in catalog.commands:
    if cmd.isPublishedOn(surface):
      result.add(cmd)

func commandsForCategories*(catalog: CommandCatalog;
                            categories: openArray[CommandCategory];
                            surface: CommandSurface): seq[CommandMetadata] =
  result = @[]
  for category in categories:
    for cmd in catalog.commands:
      if cmd.category != category:
        continue
      if cmd.isPublishedOn(surface):
        result.add(cmd)

func commandHelpLine*(cmd: CommandMetadata; interactiveUi: bool): string =
  cmd.usageFor(interactiveUi) & " — " & cmd.helpSummaryFor(interactiveUi)

func defaultMenuCategories*(): seq[CommandCategory] =
  @[ccNavigation, ccConfiguration, ccStatus, ccMemory, ccSession, ccTools]

func defaultHelpSections*(): seq[CommandSection] =
  @[
    CommandSection(title: "Conversa", categories: @[ccNavigation, ccMemory, ccSession]),
    CommandSection(title: "Modelos & Config", categories: @[ccConfiguration]),
    CommandSection(title: "Sistema", categories: @[ccStatus, ccTools]),
  ]

func toTelegramCommandsJson*(catalog: CommandCatalog): JsonNode =
  result = newJArray()
  for cmd in catalog.getBySurface(csTelegram):
    result.add(%*{
      "command": commandToken(cmd),
      "description": cmd.telegramDescription,
    })

func toDiscordSlashCommandsJson*(catalog: CommandCatalog): JsonNode =
  result = newJArray()
  for cmd in catalog.getBySurface(csDiscord):
    var node = %*{
      "name": commandToken(cmd),
      "type": 1,
      "description": cmd.discordDescription,
    }
    if cmd.discordOptions.len > 0:
      var options = newJArray()
      for opt in cmd.discordOptions:
        options.add(%*{
          "name": opt.name,
          "description": opt.description,
          "type": opt.kind,
          "required": opt.required,
        })
      node["options"] = options
    result.add(node)

func newCommandMetadata(kind: CommandKind;
                        description, summaryPt, telegramDescription,
                        discordDescription: string;
                        category: CommandCategory;
                        usage = "";
                        textUsage = "";
                        helpSummaryInteractive = "";
                        menuSummary = "";
                        menuDetails: seq[string] = @[];
                        requiresArgs = false;
                        publishedOn: set[CommandSurface] = PublishedEverywhere;
                        discordOptions: seq[DiscordOptionMetadata] = @[]): CommandMetadata =
  let name = primaryCommandName(kind)
  CommandMetadata(
    kind: kind,
    name: name,
    description: description,
    usage: if usage.len > 0: usage else: name,
    textUsage: textUsage,
    menuSummary: if menuSummary.len > 0: menuSummary else: summaryPt,
    helpSummary: summaryPt,
    helpSummaryInteractive: helpSummaryInteractive,
    telegramDescription: telegramDescription,
    discordDescription: discordDescription,
    discordOptions: discordOptions,
    menuDetails: menuDetails,
    publishedOn: publishedOn,
    category: category,
    requiresArgs: if requiresArgs: true else: not commandAllowsBare(kind),
    route: decideCommandRoute(kind),
  )

func commandCatalogItems(): seq[CommandMetadata] =
  @[
    # Navigation
    newCommandMetadata(cmdStart, "Start a conversation",
      "apresentação", "Inicia ou recomeça a conversa", "Show the intro text",
      ccNavigation),
    newCommandMetadata(cmdMenu, "Show grouped command menu",
      "mostra menu agrupado de comandos", "Mostra o menu principal", "Show grouped command menu",
      ccNavigation),
    newCommandMetadata(cmdNew, "Archive current session and start fresh",
      "arquiva a conversa atual e começa outra", "Arquiva a conversa atual e começa outra",
      "Archive current session and start fresh", ccNavigation),
    newCommandMetadata(cmdWhoami, "Show current session id",
      "mostra a identidade da sessão atual", "Mostra a identidade da sessão",
      "Show current session identity", ccNavigation),

    # Configuration
    newCommandMetadata(cmdConfig, "Manage runtime configuration",
      "abre o menu de configuração", "Abre o menu de configuração",
      "Open runtime configuration", ccConfiguration),
    newCommandMetadata(cmdModels, "Switch model",
      "vê ou troca o modelo de IA", "Seleciona o modelo de IA",
      "Show or change the active provider/model", ccConfiguration,
      textUsage = "/models [provider model]",
      helpSummaryInteractive = "seleciona o modelo de IA",
      discordOptions = @[
        DiscordOptionMetadata(name: "provider", description: "Provider name", kind: 3, required: false),
        DiscordOptionMetadata(name: "model", description: "Model name", kind: 3, required: false),
      ]),
    newCommandMetadata(cmdThink, "Set thinking level",
      "vê ou troca o nível de raciocínio", "Controla o nível de raciocínio",
      "Show or change the reasoning level", ccConfiguration,
      textUsage = "/think [level]",
      helpSummaryInteractive = "controla o nível de raciocínio",
      discordOptions = @[
        DiscordOptionMetadata(name: "level", description: "off, low, medium, or high", kind: 3, required: false),
      ]),
    newCommandMetadata(cmdBudget, "Set budget policy",
      "vê ou troca a policy de custo/qualidade", "Controla a policy de custo/qualidade",
      "Show or change the cost/quality policy", ccConfiguration,
      textUsage = "/budget [policy]",
      helpSummaryInteractive = "controla a policy de custo/qualidade",
      discordOptions = @[
        DiscordOptionMetadata(name: "policy", description: "cheap-first, balanced, or quality-first", kind: 3, required: false),
      ]),
    newCommandMetadata(cmdVerbose, "Set verbose level",
      "ajusta o nível de verbose", "Ajusta o nível de verbose",
      "Set verbose level", ccConfiguration,
      publishedOn = {}),
    newCommandMetadata(cmdReasoning, "Set reasoning output",
      "ativa ou desativa a exibição do pensamento", "Ativa ou desativa a exibição do pensamento",
      "Toggle reasoning visibility", ccConfiguration),
    newCommandMetadata(cmdExec, "Set exec policy",
      "ajusta a policy de exec", "Ajusta a policy de exec",
      "Set exec policy", ccConfiguration,
      publishedOn = {}),
    newCommandMetadata(cmdAllowlist, "Show allowlist",
      "mostra a allowlist efetiva", "Mostra a allowlist efetiva",
      "Show the effective allowlist", ccConfiguration,
      publishedOn = {}),
    newCommandMetadata(cmdQueue, "Set queue policy",
      "ajusta a policy de fila", "Ajusta a policy de fila",
      "Set queue policy", ccConfiguration,
      publishedOn = {}),
    newCommandMetadata(cmdUsage, "Set usage footer mode",
      "ajusta o modo do rodapé de usage", "Ajusta o modo do rodapé de usage",
      "Set usage footer mode", ccConfiguration,
      publishedOn = {}),
    newCommandMetadata(cmdTts, "Configure text-to-speech mode",
      "configura TTS", "Configura TTS",
      "Configure text-to-speech mode", ccConfiguration,
      publishedOn = {}),

    # Status
    newCommandMetadata(cmdStatus, "Show model and stats",
      "snapshot da sessão atual", "Snapshot da sessão atual",
      "Show session/runtime status", ccStatus),
    newCommandMetadata(cmdTasks, "List background tasks",
      "lista tarefas em background", "Lista tarefas em background",
      "List background tasks", ccStatus),
    newCommandMetadata(cmdAgents, "Show active agents",
      "mostra agentes e ferramentas carregadas", "Mostra agentes e ferramentas carregadas",
      "Show active agents and tools", ccStatus),
    newCommandMetadata(cmdPoll, "Show pending approvals",
      "mostra aprovações pendentes", "Mostra aprovações pendentes",
      "Show pending approvals", ccStatus),

    # Memory
    newCommandMetadata(cmdForget, "Clear memory",
      "apaga as memórias salvas", "Apaga as memórias salvas",
      "Clear saved memories", ccMemory),
    newCommandMetadata(cmdMemory, "Memory tools",
      "exibe memórias salvas", "Exibe memórias salvas",
      "Show saved memories", ccMemory),
    newCommandMetadata(cmdDoctor, "Memory diagnostics",
      "diagnóstico do sistema", "Diagnóstico do sistema",
      "Run a runtime diagnostic", ccMemory),

    # Session
    newCommandMetadata(cmdReset, "Reset bootstrap and rerun onboarding",
      "reinicia o bootstrap e roda onboarding de novo", "Reinicia o bootstrap e roda onboarding de novo",
      "Reset the active session", ccSession),
    newCommandMetadata(cmdCompact, "Compact context now",
      "compacta o contexto agora", "Compacta o contexto agora",
      "Compact the current context", ccSession),
    newCommandMetadata(cmdRestart, "Restart session",
      "reinicia a sessão", "Reinicia a sessão",
      "Restart the active session", ccSession),
    newCommandMetadata(cmdStop, "Stop active task",
      "interrompe a tarefa ativa", "Interrompe a tarefa ativa",
      "Stop the active task", ccSession),
    newCommandMetadata(cmdBind, "/bind chat to agent",
      "vincula este chat a um agente", "Vincula este chat a um agente",
      "Bind this chat to an agent", ccSession),
    newCommandMetadata(cmdCallback, "Handle callback",
      "callback interno", "Callback interno",
      "Handle internal callback", ccSession,
      publishedOn = {}),

    # Tools
    newCommandMetadata(cmdHelp, "Show help",
      "esta mensagem", "Ajuda e lista de comandos",
      "Show available commands", ccTools),
    newCommandMetadata(cmdSkill, "Search, install, and enable skills",
      "busca, instala e habilita skills", "Busca e instala skills",
      "Search, install, and enable skills", ccTools,
      menuDetails = SkillCommandMenuDetails),
    newCommandMetadata(cmdDebug, "Toggle debug mode",
      "ativa ou desativa modo verbose", "Ativa ou desativa modo verbose",
      "Toggle verbose tool/debug mode", ccTools),
    newCommandMetadata(cmdMyCode, "Generate link code",
      "gera código de linkagem cross-channel", "Gera código de linkagem cross-channel",
      "Generate a link code to reconnect from another channel", ccTools),
    newCommandMetadata(cmdContinue, "Continue link",
      "conecta este canal a outra sessão", "Continua sessão de outro canal",
      "Continue your session from another channel", ccTools,
      usage = "/continue <code>",
      textUsage = "/continue <code>",
      discordOptions = @[
        DiscordOptionMetadata(name: "code", description: "Link code from /mycode on another channel", kind: 3, required: false),
      ]),
    newCommandMetadata(cmdPing, "Ping",
      "testa latência do provider", "Testa latência do provider",
      "Measure provider latency", ccTools),
  ]

func newCommandCatalog*(): CommandCatalog =
  CommandCatalog(commands: commandCatalogItems())

func getByCategory*(catalog: CommandCatalog; category: CommandCategory): seq[CommandMetadata] =
  result = @[]
  for cmd in catalog.commands:
    if cmd.category == category:
      result.add(cmd)

func getByRoute*(catalog: CommandCatalog; route: CommandRoute): seq[CommandMetadata] =
  result = @[]
  for cmd in catalog.commands:
    if cmd.route == route:
      result.add(cmd)

func toJsonArray*(catalog: CommandCatalog): string =
  var parts: seq[string] = @[]
  for cmd in catalog.commands:
    let item = """{"command":"""" & cmd.name & """","description":"""" & cmd.description & """","category":"""" & $cmd.category & """"}"""
    parts.add(item)
  "[" & parts.join(",") & "]"

func categoryIcon*(cat: CommandCategory): string =
  case cat
  of ccNavigation: "📍"
  of ccConfiguration: "⚙️"
  of ccStatus: "📊"
  of ccMemory: "🧠"
  of ccSession: "🔄"
  of ccTools: "🛠️"
  of ccHelp: "❓"

func categoryName*(cat: CommandCategory): string =
  case cat
  of ccNavigation: "Navigation"
  of ccConfiguration: "Configuration"
  of ccStatus: "Status"
  of ccMemory: "Memory"
  of ccSession: "Session"
  of ccTools: "Tools"
  of ccHelp: "Help"

func getMenuText*(catalog: CommandCatalog): string =
  var lines: seq[string] = @["*Available Commands:*", ""]

  let categories = @[ccNavigation, ccConfiguration, ccStatus, ccMemory, ccSession, ccTools]
  for cat in categories:
    let cmds = catalog.getByCategory(cat).filterIt(it.isPublishedOn(csMenu))
    if cmds.len > 0:
      lines.add(categoryIcon(cat) & " *" & categoryName(cat) & "*")
      for cmd in cmds:
        lines.add("  " & cmd.usageFor(true) & " - " & cmd.description)
        for detail in cmd.menuDetails:
          lines.add("    " & detail)
      lines.add("")

  lines.join("\n")

func findCommand*(catalog: CommandCatalog; name: string): Option[CommandMetadata] =
  for cmd in catalog.commands:
    if cmd.name == name:
      return some(cmd)
  return none(CommandMetadata)

func isValidCommand*(catalog: CommandCatalog; name: string): bool =
  catalog.findCommand(name).isSome()
