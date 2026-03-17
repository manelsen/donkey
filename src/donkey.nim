## donkey — AI agent system entry point.

import std/[os, parseopt, strutils]
import donkey/config/loader
import donkey/core/log

const Version* = "0.1.0"

proc printVersion =
  echo "donkey " & Version

proc printHelp =
  echo """donkey """ & Version & """

Usage:
  donkey [options]
  donkey ctl <command>

Options:
  --version    Print version and exit
  --help       Show this help
  --config     Path to donkey.toml  (default: ~/.donkey/donkey.toml)

Commands:
  start        Start the daemon (default)
  ctl          Admin CLI (run `donkey ctl --help`)
"""

proc main =
  var configPath = ""

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "version": printVersion(); quit(0)
      of "help":    printHelp();    quit(0)
      of "config":  configPath = val
      else: discard
    of cmdShortOption:
      case key
      of "v": printVersion(); quit(0)
      of "h": printHelp();    quit(0)
      else: discard
    of cmdArgument:
      discard  # subcommands handled later (ctl, start)
    of cmdEnd:
      break

  if configPath.len == 0:
    let home = resolveHome()
    configPath = home / "donkey.toml"

  let cfg = loadConfig(configPath)
  let log = newLogger("donkey")

  log.info("donkey " & Version & " starting")
  log.info("home: " & cfg.home)
  log.info("paddocks: " & cfg.paddocks)

  # F1: agent loop goes here
  log.warn("no channels configured — nothing to do (F1 not implemented yet)")

when isMainModule:
  main()
