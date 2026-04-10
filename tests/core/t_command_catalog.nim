## Tests for command catalog.

import std/[json, options, sequtils, strutils, unittest]
import donkey/core/commands/command_catalog
import donkey/core/commands/command_routing

suite "Command Catalog":

  test "catalog has expected number of commands":
    let catalog = newCommandCatalog()
    check catalog.commands.len >= 30

  test "findCommand returns command metadata":
    let catalog = newCommandCatalog()
    let result = catalog.findCommand("/start")
    check result.isSome()
    check result.get().description == "Start a conversation"
    check result.get().category == ccNavigation

  test "findCommand returns none for unknown":
    let catalog = newCommandCatalog()
    let result = catalog.findCommand("/unknown")
    check result.isNone()

  test "isValidCommand validates existing":
    let catalog = newCommandCatalog()
    check catalog.isValidCommand("/start") == true
    check catalog.isValidCommand("/help") == true
    check catalog.isValidCommand("/menu") == true

  test "isValidCommand rejects unknown":
    let catalog = newCommandCatalog()
    check catalog.isValidCommand("/invalid") == false

  test "getByCategory filters correctly":
    let catalog = newCommandCatalog()
    let nav = catalog.getByCategory(ccNavigation)
    check nav.len >= 4
    for cmd in nav:
      check cmd.category == ccNavigation

  test "getByRoute filters correctly":
    let catalog = newCommandCatalog()
    let local = catalog.getByRoute(crLocal)
    check local.len >= 5
    for cmd in local:
      check cmd.route == crLocal

  test "toJsonArray generates valid JSON":
    let catalog = newCommandCatalog()
    let json = catalog.toJsonArray()
    check json.startsWith("[")
    check json.endsWith("]")
    check "\"command\"" in json
    check "\"/start\"" in json

  test "getMenuText generates formatted output":
    let catalog = newCommandCatalog()
    let text = catalog.getMenuText()
    check "Available Commands" in text
    check "/start" in text
    check "/menu" in text
    check "Navigation" in text
    check "/skill" in text
    check "/skill list" in text
    check "/skill install <slug>" in text

  test "all direct commands from routing are in catalog":
    let catalog = newCommandCatalog()
    # Direct commands from parseCommandText (without prefix variants like /models xxx)
    let expectedCmds = @["/about", "/start", "/forget", "/doctor", "/help", "/memory",
                         "/debug", "/reset", "/mycode", "/continue",
                         "/ping", "/status", "/compact", "/new"]
    for cmd in expectedCmds:
      check catalog.isValidCommand(cmd) == true

  test "new commands exist in catalog":
    let catalog = newCommandCatalog()
    let newCmds = @["/menu", "/whoami", "/config", "/models", "/verbose", "/reasoning",
                   "/exec", "/allowlist", "/queue", "/usage", "/tts", "/tasks",
                   "/agents", "/poll", "/stop", "/restart", "/bind"]
    for cmd in newCmds:
      check catalog.isValidCommand(cmd) == true
    check catalog.isValidCommand("/model") == false

  test "/skill exists in catalog as a local tools command":
    let catalog = newCommandCatalog()
    let cmd = catalog.findCommand("/skill")
    check cmd.isSome()
    check cmd.get().route == crLocal
    check cmd.get().category == ccTools
    check cmd.get().menuDetails.len >= 5

  test "deferred config commands use UI route metadata":
    let catalog = newCommandCatalog()
    for name in ["/verbose", "/exec", "/queue", "/usage", "/tts"]:
      let cmd = catalog.findCommand(name)
      check cmd.isSome()
      check cmd.get().route == crUi

  test "catalog route metadata follows command routing":
    let catalog = newCommandCatalog()
    for cmd in catalog.commands:
      check cmd.name == primaryCommandName(cmd.kind)
      check cmd.route == decideCommandRoute(cmd.kind)

  test "catalog argument metadata follows command syntax":
    let catalog = newCommandCatalog()
    check catalog.findCommand("/continue").get().requiresArgs
    check catalog.findCommand("/callback").get().requiresArgs
    check not catalog.findCommand("/models").get().requiresArgs
    check not catalog.findCommand("/skill").get().requiresArgs

  test "telegram projection is derived from published catalog commands":
    let commands = newCommandCatalog().toTelegramCommandsJson()
    check commands.kind == JArray
    check commands.elems.anyIt(it["command"].getStr("") == "skill")
    check commands.elems.anyIt(it["command"].getStr("") == "menu")
    check commands.elems.anyIt(it["command"].getStr("") == "whoami")
    check commands.elems.allIt(it["command"].getStr("") != "callback")

  test "discord projection is derived from published catalog commands":
    let commands = newCommandCatalog().toDiscordSlashCommandsJson()
    check commands.kind == JArray
    let models = commands.elems.filterIt(it["name"].getStr("") == "models")
    check models.len == 1
    check models[0]["options"].len == 2
    check commands.elems.anyIt(it["name"].getStr("") == "skill")
    check commands.elems.allIt(it["name"].getStr("") != "callback")

  test "categoryIcon returns emoji":
    check categoryIcon(ccNavigation) == "📍"
    check categoryIcon(ccConfiguration) == "⚙️"
    check categoryIcon(ccStatus) == "📊"
    check categoryIcon(ccMemory) == "🧠"

  test "categoryName returns readable name":
    check categoryName(ccNavigation) == "Navigation"
    check categoryName(ccConfiguration) == "Configuration"
