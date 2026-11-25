## Pure command texts shared by every channel: help, menus, link codes,
## identity, deferred UI commands, ping/uptime formatting. Availability lives
## in `command_surface` and arguments in `command_args` (both re-exported
## here for the channels that present texts). Nothing here reads files, the
## environment or the clock.

import std/strutils
import ../pipeops
import ../types
import ./command_catalog
import ./command_routing
import ./command_surface
import ./command_args

export command_surface, command_args

func savedOrError*(saved: Result[void, string]; confirmation: string): string =
  ## What to tell the user after a preference change: the confirmation only
  ## when the change was saved.
  if saved.isOk: confirmation
  else: "Não foi possível salvar: " & saved.error

func buildDeferredUiCommandText*(kind: CommandKind): string =
  case kind
  of cmdVerbose:
    "Ajuste fino de verbose ainda não foi exposto por slash command. Use `/debug` para alternar o modo de debug."
  of cmdExec:
    "A policy de exec ainda não foi exposta por slash command. Ajuste isso via configuração do runtime."
  of cmdQueue:
    "A policy de fila ainda não foi exposta por slash command."
  of cmdUsage:
    "O modo de rodapé de usage ainda não foi exposto por slash command."
  of cmdTts:
    "TTS ainda não está disponível por slash command neste canal."
  else:
    ""

func buildWhoamiText*(userId: UserId; sessionId, channelId: string): string =
  "🆔 *Identity*\n\n" &
  "*Donkey ID:* `" & $userId & "`\n" &
  "*Session ID:* " & (if sessionId.len > 0: "`" & sessionId & "`" else: "_nenhuma_") & "\n" &
  "*Channel ID:* `" & channelId & "`"

func formatHelpCommandLine(line: string; withBackticks: bool): string =
  if not withBackticks:
    return line
  let sep = line.find(" — ")
  if sep < 0:
    return "`" & line & "`"
  "`" & line[0 ..< sep] & "`" & line[sep .. ^1]

func appendCatalogLines(lines: var seq[string];
                        catalog: CommandCatalog;
                        categories: openArray[CommandCategory];
                        surface: CommandSurface;
                        caps: CommandSurfaceCaps;
                        interactiveUi: bool;
                        withBackticks: bool;
                        indent = "";
                        includeCategoryTitle = false) =
  for category in categories:
    var commands: seq[CommandMetadata]
    for cmd in catalog.commandsForCategories([category], surface):
      if commandAvailable(cmd.kind, caps):
        commands.add(cmd)
    if commands.len == 0:
      continue
    if includeCategoryTitle:
      lines.add(indent & "*" & categoryNamePt(category) & "*")
    for cmd in commands:
      let line = cmd.usageFor(interactiveUi) & " — " & cmd.helpSummaryFor(interactiveUi)
      lines.add(indent & formatHelpCommandLine(line, withBackticks))
      for detail in cmd.menuDetails:
        lines.add(indent & "  " & formatHelpCommandLine(detail, withBackticks))
    if includeCategoryTitle:
      lines.add("")

func buildMenuButtons*(): seq[seq[(string, string)]] =
  ## Main menu buttons grouped by category.
  @[
    @[("🔍 Modelos", "models"), ("🧠 Thinking", "think"), ("💭 Reasoning", "reasoning")],
    @[("💰 Budget", "budget"), ("📖 Ajuda", "help"), ("📊 Status", "status")],
    @[("🩺 Doctor", "doctor"), ("🗑️ Esquecer", "forget"), ("♻️ Reset", "reset")],
    @[("🔗 My Code", "mycode")]
  ]

func buildMenuText*(): string =
  let catalog = newCommandCatalog()
  var lines = @[
    "🫏 *Donkey Menu*",
    "",
    "Selecione uma categoria ou comando abaixo para configurar sua sessão ou obter informações.",
    "",
  ]
  appendCatalogLines(
    lines,
    catalog,
    defaultMenuCategories(),
    csMenu,
    AllCommandSurfaceCaps,
    interactiveUi = true,
    withBackticks = false,
    includeCategoryTitle = true,
  )
  lines.join("\n").strip()

func buildConfigButtons*(): seq[seq[(string, string)]] =
  ## Configuration menu buttons.
  @[
    @[("🔍 Selecionar Provider", "models")],
    @[("🧠 Nível de Thinking", "think"), ("💭 Toggle Reasoning", "reasoning")],
    @[("💰 Policy de Budget", "budget")],
    @[("← voltar ao menu", "menu")]
  ]

func buildConfigText*(prefs: ChannelPrefs; withButtons = true): string =
  ## The /config view. Without buttons it names the commands that change
  ## each setting instead of pointing at buttons that are not there.
  let footer =
    if withButtons: "Use os botões abaixo para alterar as configurações."
    else: "Use /models, /think, /reasoning e /budget para alterar as configurações."
  "⚙️ *Configurações da Sessão*\n\n" &
  "*Provider:* `" & prefs.provider & "`\n" &
  "*Modelo:* `" & prefs.model & "`\n" &
  "*Thinking:* `" & prefs.thinking & "`\n" &
  "*Reasoning:* `" & prefs.reasoning & "`\n" &
  "*Budget:* `" & prefs.budget & "`\n\n" &
  footer

func buildTasksText*(): string =
  ## /tasks where the task board cannot be read (no paddock for this channel).
  "O quadro de tarefas não está disponível aqui. Peça ao agente: " &
    "\"mostre minhas tarefas\"."

func buildAgentsText*(toolsCount, toolClientsCount: int): string =
  "🤖 *Agentes & Ferramentas*\n\n" &
  "*Ferramentas nativas:* " & $toolsCount & " carregadas\n" &
  "*Clientes MCP:* " & $toolClientsCount & " conectados\n\n" &
  "O assistente está pronto para usar as capacidades de navegação, shell e manipulação de arquivos."

func buildPollText*(): string =
  "🗳️ *Aprovações Pendentes*\n\n" &
  "Nenhuma solicitação de aprovação pendente no momento.\n\n" &
  "Quando uma ferramenta exigir sua confirmação (ex: deletar arquivo), ela aparecerá aqui."

func buildStartIntroText*(): string =
  "Olá! Sou o Donkey, seu assistente pessoal.\n\n" &
  "Envie qualquer mensagem para começarmos.\n" &
  "Use /help para ver os comandos disponíveis."

func buildHelpPages*(caps = AllCommandSurfaceCaps): seq[(string, string)] =
  ## Returns (title, body) per page for paginated help embeds (Discord).
  let catalog = newCommandCatalog()
  for section in defaultHelpSections():
    var sectionLines: seq[string]
    appendCatalogLines(sectionLines, catalog,
      section.categories, csHelp, caps, interactiveUi = true, withBackticks = true)
    result.add((section.title, sectionLines.join("\n")))

func buildHelpNavButtons*(page, total: int): seq[seq[(string, string)]] =
  var row: seq[(string, string)]
  if page > 0:
    row.add(("◀ Anterior", "help:page:" & $(page - 1)))
  if page < total - 1:
    row.add(("Próximo ▶", "help:page:" & $(page + 1)))
  if row.len > 0: @[row] else: @[]

func buildHelpText*(caps: CommandSurfaceCaps; interactiveUi: bool): string =
  ## Lists only the commands a channel with `caps` can answer.
  let catalog = newCommandCatalog()
  var lines = @["Donkey — comandos disponíveis:", ""]
  appendCatalogLines(
    lines,
    catalog,
    defaultMenuCategories(),
    csHelp,
    caps,
    interactiveUi,
    withBackticks = false,
    includeCategoryTitle = true,
  )
  lines.join("\n").strip()

func buildLinkCodeText*(code: string): string =
  "Your link code: `" & code & "` (valid 10 minutes)\n" &
  "Use `/continue <code>` on another channel to reconnect."

func buildContinueResultText*(linked: bool): string =
  if linked:
    "Sessão reconectada! Seu histórico foi preservado."
  else:
    "Código inválido ou expirado. Gere um novo com /mycode."

func formatUptime*(uptimeSec: int64): string =
  if uptimeSec < 60: $uptimeSec & "s"
  elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
  else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"

func formatPingText*(provider, model: string; elapsedMs: int64;
                     error = ""): string =
  if error.len == 0:
    "pong — " & provider & " / " & model & " — " & $elapsedMs & "ms"
  else:
    provider & " error: " & error

func reasoningToggleText*(next: string): string =
  if next == "on": "Reasoning ativado." else: "Reasoning desativado."
