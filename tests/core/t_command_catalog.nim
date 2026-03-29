## Tests for command catalog.

import std/[unittest, options, strutils]
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

  test "all direct commands from routing are in catalog":
    let catalog = newCommandCatalog()
    # Direct commands from parseCommandText (without prefix variants like /models xxx)
    let expectedCmds = @["/start", "/forget", "/doctor", "/help", "/memory",
                         "/debug", "/reset", "/mycode", "/continue",
                         "/ping", "/status", "/compact", "/new"]
    for cmd in expectedCmds:
      check catalog.isValidCommand(cmd) == true

  test "new commands exist in catalog":
    let catalog = newCommandCatalog()
    let newCmds = @["/menu", "/whoami", "/config", "/verbose", "/reasoning",
                   "/exec", "/allowlist", "/queue", "/usage", "/tasks",
                   "/agents", "/poll", "/stop", "/restart", "/bind"]
    for cmd in newCmds:
      check catalog.isValidCommand(cmd) == true

  test "categoryIcon returns emoji":
    check categoryIcon(ccNavigation) == "📍"
    check categoryIcon(ccConfiguration) == "⚙️"
    check categoryIcon(ccStatus) == "📊"
    check categoryIcon(ccMemory) == "🧠"

  test "categoryName returns readable name":
    check categoryName(ccNavigation) == "Navigation"
    check categoryName(ccConfiguration) == "Configuration"
