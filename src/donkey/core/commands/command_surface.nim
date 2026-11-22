## What a channel's command surface can answer: the capabilities that decide
## whether a command gets a real answer or "unsupported", and which commands
## /help lists. No texts here: ports read this module, and texts live in
## `command_text`.

import ./command_catalog
import ./command_routing

type
  CommandSurfaceCaps* = object
    ## What a channel's command surface can answer beyond plain text.
    configUi*:         bool  ## a /config view with buttons
    interactiveMenus*: bool  ## a /menu with buttons

const AllCommandSurfaceCaps* = CommandSurfaceCaps(configUi: true, interactiveMenus: true)

func commandAvailable*(kind: CommandKind; caps: CommandSurfaceCaps): bool =
  ## Whether a channel with `caps` answers `kind` with something other than
  ## "unsupported". /config and /menu only exist as button views.
  case kind
  of cmdConfig: caps.configUi
  of cmdMenu:   caps.interactiveMenus
  of cmdNone, cmdCallback, cmdPair: false
  else: true

func helpCommandKinds*(caps: CommandSurfaceCaps): seq[CommandKind] =
  ## Every command `/help` lists for a channel with `caps`.
  let catalog = newCommandCatalog()
  for cmd in catalog.commandsForCategories(defaultMenuCategories(), csHelp):
    if commandAvailable(cmd.kind, caps) and cmd.kind notin result:
      result.add(cmd.kind)
