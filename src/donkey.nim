## donkey — AI agent system entry point.

import std/[os, parseopt, tables]
import donkey/config/loader
import donkey/config/types
import donkey/core/log
import donkey/adapters/memory/md_file
import donkey/adapters/provider/zhipu
import donkey/adapters/channel/telegram
import donkey/app/agent_runner
import donkey/domain/message

const Version* = "0.1.0"

proc printVersion =
  echo "donkey " & Version

proc printHelp =
  echo """donkey """ & Version & """

Usage:
  donkey [options] [command]

Options:
  --version        Print version and exit
  --help           Show this help
  --config <path>  Path to donkey.toml  (default: ~/.donkey/donkey.toml)

Commands:
  start            Start the daemon (long-poll Telegram → Zhipu)
  ctl user list    List registered users
  ctl user show <uuid>  Show user profile
"""

# ── ctl user commands ──────────────────────────────────────────────────────────

proc ctlUserList(memory: MdFileAdapter) =
  if not dirExists(memory.paddocksDir):
    echo "(no paddocks directory — no users yet)"
    return
  var found = false
  for kind, name in walkDir(memory.paddocksDir):
    if kind == pcDir:
      found = true
      let userMdPath = name / "USER.md"
      if fileExists(userMdPath):
        echo name.extractFilename() & " (profile)"
      else:
        echo name.extractFilename() & " (no profile)"
  if not found:
    echo "(no users registered)"

proc ctlUserShow(memory: MdFileAdapter; uuid: string) =
  let userId = UserId(uuid)
  if not memory.hasProfile(userId):
    echo "User not found: " & uuid
    quit(1)
  let ctx = memory.loadContext(userId)
  echo "=== USER.md ==="
  echo ctx.userMd
  if ctx.preferencesMd.len > 0:
    echo "=== PREFERENCES.md ==="
    echo ctx.preferencesMd
  if ctx.memoryMd.len > 0:
    echo "=== MEMORY.md (first 500 chars) ==="
    echo ctx.memoryMd[0 .. min(500, ctx.memoryMd.len - 1)]

# ── daemon start ───────────────────────────────────────────────────────────────

proc startDaemon(cfg: DonkeyConfig; log: Logger) =
  log.info("daemon starting — Telegram long-polling (F1)")
  let telegramToken = getEnv("TELEGRAM_BOT_TOKEN")
  let zhipuKey      = getEnv("ZHIPU_API_KEY")

  if telegramToken.len == 0:
    log.error("TELEGRAM_BOT_TOKEN not set — set env var and restart")
    quit(1)
  if zhipuKey.len == 0:
    log.error("ZHIPU_API_KEY not set — set env var and restart")
    quit(1)

  let memory   = MdFileAdapter(paddocksDir: cfg.paddocks)
  let provider = newZhipuAdapter(zhipuKey)

  let identityPath = cfg.home / "identities.tsv"
  var channel = newTelegramAdapter(telegramToken, identityPath)

  var runners: Table[string, AgentRunner]
  # Track users in onboarding (not yet profiled)
  var onboarding: Table[string, bool]

  log.info("polling for messages…")
  while true:
    # Receive — if the poll fails (network hiccup) log and retry next iteration.
    var msgs: seq[InboundMessage]
    try:
      msgs = channel.receive()
    except CatchableError as e:
      log.error("receive error: " & e.msg)
      continue

    for msg in msgs:
      let uid = $msg.userId
      if uid notin runners:
        runners[uid] = newAgentRunner(memory, provider, log.child("agent." & uid))

      var runner = runners[uid]

      # Generate reply — if the LLM call fails, send an apology and move on.
      var reply = ""
      try:
        let needsOnboard = needsOnboarding(memory.hasProfile(msg.userId))
        if needsOnboard:
          onboarding[uid] = true
          let (text, done) = runner.runOnboardingTurn(msg.userId, msg.text)
          if done:
            onboarding.del(uid)
          reply = text
        else:
          reply = runner.runTurn(msg.userId, msg.text)
      except CatchableError as e:
        log.error("agent error for " & uid & ": " & e.msg)
        reply = "Desculpe, ocorreu um erro interno. Tente novamente."

      runners[uid] = runner

      # Send — if delivery fails, log and continue (don't crash the daemon).
      try:
        channel.send(OutboundMessage(
          userId:  msg.userId,
          text:    reply,
          replyTo: msg.channelId,
        ))
      except CatchableError as e:
        log.error("send error for " & uid & ": " & e.msg)

# ── main ───────────────────────────────────────────────────────────────────────

proc main =
  var configPath = ""
  var args: seq[string] = @[]

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
      args.add key
    of cmdEnd:
      break

  if configPath.len == 0:
    let home = resolveHome()
    configPath = home / "donkey.toml"

  let cfg = loadConfig(configPath)
  let log = newLogger("donkey")

  # Dispatch subcommands
  if args.len >= 1 and args[0] == "ctl":
    if args.len >= 3 and args[1] == "user" and args[2] == "list":
      ctlUserList(MdFileAdapter(paddocksDir: cfg.paddocks))
      quit(0)
    elif args.len >= 4 and args[1] == "user" and args[2] == "show":
      ctlUserShow(MdFileAdapter(paddocksDir: cfg.paddocks), args[3])
      quit(0)
    else:
      echo "Usage: donkey ctl user list | donkey ctl user show <uuid>"
      quit(1)

  log.info("donkey " & Version & " starting")
  log.info("home: " & cfg.home)

  startDaemon(cfg, log)

when isMainModule:
  main()
