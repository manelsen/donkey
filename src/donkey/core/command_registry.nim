## command_registry.nim — Data-driven command dispatch.
##
## Each command declares its name, expected arguments, handler proc,
## required context flags, and exit code. The registry resolves an
## argument list to the matching handler and runs it.
##
## Pure module — no adapters, no runtime deps — fully testable.

import std/[tables, options]

type
  CommandContext* = enum
    ccNone          ## no prerequisites
    ccConfigLoaded  ## --config parsed, DonkeyConfig available
    ccDaemonReady   ## bootstrap complete, logger and memory ready

  CommandHandler* = proc(args: seq[string]): int
    ## Handler proc. Receives the full args list (including the command
    ## name at index 0). Returns an exit code: 0 = ok, 1 = error,
    ## 2 = show help (unrecognized subcommand).
    ## NOTE: intentionally NOT {.gcsafe.} — handlers may capture config
    ## objects that live for the duration of main(). The registry stores
    ## the handler reference, so the GC tracks captured values correctly.

  CommandEntry* = object
    name*:         string           ## command name, e.g. "ctl", "service"
    minArgs*:      int              ## minimum args length (including the command name)
    handler*:      CommandHandler   ## the actual handler proc
    context*:      CommandContext   ## required bootstrap level
    description*:  string           ## short help text

  CommandRegistry* = ref object
    entries: Table[string, CommandEntry]

proc newCommandRegistry*(): CommandRegistry =
  CommandRegistry(entries: initTable[string, CommandEntry]())

proc register*(r: CommandRegistry; entry: CommandEntry) =
  r.entries[entry.name] = entry

proc resolve*(r: CommandRegistry; cmdName: string): Option[CommandEntry] =
  if r.entries.hasKey(cmdName): some(r.entries[cmdName]) else: none(CommandEntry)

proc dispatch*(r: CommandRegistry; args: seq[string]): int =
  ## Looks up the command by args[0] and runs its handler.
  ## Returns -1 if no matching command found (caller should show help).
  if args.len == 0: return -1
  let entry = r.resolve(args[0])
  if entry.isNone: return -1
  let e = entry.get()
  if args.len < e.minArgs: return 2  # insufficient args → show help
  e.handler(args)

proc listCommands*(r: CommandRegistry): seq[CommandEntry] =
  for _, e in r.entries.pairs:
    result.add(e)
