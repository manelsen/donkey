## Unified command catalog with metadata for all slash commands.

import std/[strutils, options]
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

  CommandMetadata* = object
    name*: string
    description*: string
    category*: CommandCategory
    requiresArgs*: bool
    route*: CommandRoute

  CommandCatalog* = object
    commands*: seq[CommandMetadata]

const
  CommandCatalogItems*: seq[CommandMetadata] = @[
    # Navigation
    CommandMetadata(name: "/start", description: "Start a conversation", category: ccNavigation, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/menu", description: "Show grouped command menu", category: ccNavigation, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/new", description: "Archive current session and start fresh", category: ccNavigation, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/whoami", description: "Show current session id", category: ccNavigation, requiresArgs: false, route: crLocal),

    # Configuration
    CommandMetadata(name: "/config", description: "Manage runtime configuration", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/model", description: "Switch model", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/think", description: "Set thinking level", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/budget", description: "Set budget policy", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/verbose", description: "Set verbose level", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/reasoning", description: "Set reasoning output", category: ccConfiguration, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/exec", description: "Set exec policy", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/allowlist", description: "Show allowlist", category: ccConfiguration, requiresArgs: false, route: crStatus),
    CommandMetadata(name: "/queue", description: "Set queue policy", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/usage", description: "Set usage footer mode", category: ccConfiguration, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/tts", description: "Configure text-to-speech mode", category: ccConfiguration, requiresArgs: false, route: crUi),

    # Status
    CommandMetadata(name: "/status", description: "Show model and stats", category: ccStatus, requiresArgs: false, route: crStatus),
    CommandMetadata(name: "/tasks", description: "List background tasks", category: ccStatus, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/agents", description: "Show active agents", category: ccStatus, requiresArgs: false, route: crUi),
    CommandMetadata(name: "/poll", description: "Show pending approvals", category: ccStatus, requiresArgs: false, route: crUi),

    # Memory
    CommandMetadata(name: "/forget", description: "Clear memory", category: ccMemory, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/memory", description: "Memory tools", category: ccMemory, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/doctor", description: "Memory diagnostics", category: ccMemory, requiresArgs: false, route: crLocal),

    # Session
    CommandMetadata(name: "/reset", description: "Reset bootstrap and rerun onboarding", category: ccSession, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/compact", description: "Compact context now", category: ccSession, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/restart", description: "Restart session", category: ccSession, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/stop", description: "Stop active task", category: ccSession, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/bind", description: "/bind chat to agent", category: ccSession, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/callback", description: "Handle callback", category: ccSession, requiresArgs: false, route: crCallback),

    # Tools
    CommandMetadata(name: "/help", description: "Show help", category: ccTools, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/skill", description: "Search, install, and enable skills", category: ccTools, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/debug", description: "Toggle debug mode", category: ccTools, requiresArgs: false, route: crSessionTask),
    CommandMetadata(name: "/mycode", description: "Generate link code", category: ccTools, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/continue", description: "Continue link", category: ccTools, requiresArgs: false, route: crLocal),
    CommandMetadata(name: "/ping", description: "Ping", category: ccTools, requiresArgs: false, route: crPing),
  ]

func newCommandCatalog*(): CommandCatalog =
  CommandCatalog(commands: CommandCatalogItems)

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
    let cmds = catalog.getByCategory(cat)
    if cmds.len > 0:
      lines.add(categoryIcon(cat) & " *" & categoryName(cat) & "*")
      for cmd in cmds:
        lines.add("  " & cmd.name & " - " & cmd.description)
      lines.add("")

  lines.join("\n")

func findCommand*(catalog: CommandCatalog; name: string): Option[CommandMetadata] =
  for cmd in catalog.commands:
    if cmd.name == name:
      return some(cmd)
  return none(CommandMetadata)

func isValidCommand*(catalog: CommandCatalog; name: string): bool =
  catalog.findCommand(name).isSome()
