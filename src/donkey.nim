## donkey — AI agent system entry point.

import std/[json, os, parseopt, strutils, tables]
import chronos
import chronos/asyncsync
import parsetoml
import donkey/config/loader
import donkey/config/types
import donkey/config/tools_registry
import donkey/config/skills_registry
import donkey/adapters/tool/deno_skill
import donkey/core/log
import donkey/core/pipeops
import donkey/adapters/memory/md_file
when defined(withPostgres):
  import donkey/adapters/memory/postgres_memory
  import donkey/adapters/embedding/openrouter_embed
import donkey/adapters/identity/identity_resolver
import donkey/adapters/provider/zhipu
import donkey/adapters/provider/openrouter
import donkey/adapters/provider/anthropic
import donkey/adapters/provider/gemini
import donkey/adapters/provider/minimax
import donkey/adapters/channel/telegram
import donkey/adapters/channel/discord
import donkey/adapters/channel/wecom
import donkey/adapters/channel/feishu
import donkey/adapters/tool/mcp_client
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/provider
import donkey/app/orchestrator
import donkey/app/session_manager

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
  start                          Start the daemon
  ctl user list                  List registered users
  ctl user show <uuid>           Show user profile
  ctl session list <uuid>        List active sessions for a user
  ctl tool install <command>            Register an MCP server
  ctl skill install <name> <script>     Register a Deno/Clawhub skill
  ctl skill list                        List registered skills
  ctl skill update <name> <script>      Update an existing skill path
  ctl provider test <name>              Test provider connectivity
  ctl memory search <uuid> <q>   Semantic search in user memory  (-d:withPostgres)
  ctl memory import <uuid>       Import .md paddock into Postgres (-d:withPostgres)
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

# ── ctl session commands ───────────────────────────────────────────────────────

proc ctlSessionList(sm: SessionManager; uuid: string) =
  ## Lists channels recorded for the user's active session.
  ## Sessions are in-memory only — this shows data from a running daemon
  ## by reading the sessions table (useful if called within the same process).
  ## For a separate CLI invocation, this shows nothing (daemon runs separately).
  let uid = UserId(uuid)
  var found = false
  for (userId, channels) in sm.listSessions():
    if userId == uid:
      found = true
      echo "Session for " & uuid & ":"
      for (kind, rawId) in channels:
        echo "  " & $kind & " : " & rawId
  if not found:
    echo "No active session for " & uuid

# ── ctl memory commands ────────────────────────────────────────────────────────

when defined(withPostgres):
  proc ctlMemorySearch(pgDsn: string; uuid, query: string; limit = 10) =
    let embedKey = getEnv("OPENROUTER_API_KEY")
    let embedAdapter = newOpenRouterEmbeddingAdapter(embedKey)
    let embedFn: EmbedFn = proc(text: string): seq[float32] =
      embedAdapter.embed(text)
    let pg = newPostgresMemoryAdapter(pgDsn, embedFn)
    pg.migrate()
    let uid = UserId(uuid)
    let hits = pg.search(uid, query, limit)
    if hits.len == 0:
      echo "(no results)"
      return
    for h in hits:
      echo "score=" & $h.score & " kind=" & h.kind
      echo h.content
      echo "---"

  proc ctlMemoryImport(pgDsn, paddocksDir: string; uuid: string) =
    let embedKey = getEnv("OPENROUTER_API_KEY")
    let embedAdapter = newOpenRouterEmbeddingAdapter(embedKey)
    let embedFn: EmbedFn = proc(text: string): seq[float32] =
      embedAdapter.embed(text)
    let pg = newPostgresMemoryAdapter(pgDsn, embedFn)
    pg.migrate()
    pg.importFromMd(paddocksDir, UserId(uuid))
    echo "Imported " & uuid & " from .md files"

# ── ctl tool/skill commands ────────────────────────────────────────────────────

proc ctlToolInstall(registryPath: string; command: string; args: seq[string]) =
  let entry = ToolEntry(kind: tkMcp, command: command, args: args)
  saveToolEntry(registryPath, entry)
  echo "Registered MCP server: " & command

proc ctlSkillInstall(skillsPath: string; name, scriptPath: string;
                     permissions: seq[string]) =
  saveSkillEntry(skillsPath, SkillManifest(
    name:        name,
    version:     "0.1.0",
    script:      scriptPath,
    permissions: permissions,
  ))
  echo "Registered skill: " & name & " (" & scriptPath & ")"

proc ctlSkillList(skillsPath: string) =
  let skills = loadSkillRegistry(skillsPath)
  if skills.len == 0:
    echo "(no skills registered)"
    return
  for s in skills:
    echo s.name & " v" & s.version & "  " & s.script
    if s.tools.len > 0:       echo "  tools:       " & s.tools.join(", ")
    if s.permissions.len > 0: echo "  permissions: " & s.permissions.join(", ")

proc ctlSkillUpdate(skillsPath, name, scriptPath: string;
                    permissions: seq[string]) =
  ## Replaces the named skill entry in the registry (re-writes the file).
  var skills = loadSkillRegistry(skillsPath)
  var found  = false
  for i in 0 ..< skills.len:
    if skills[i].name == name:
      skills[i].script      = scriptPath
      skills[i].permissions = permissions
      found = true; break
  if not found:
    skills.add(SkillManifest(name: name, script: scriptPath,
                             permissions: permissions))
  if fileExists(skillsPath): removeFile(skillsPath)
  for s in skills: saveSkillEntry(skillsPath, s)
  echo "Updated skill: " & name

# ── provider selection + fallback ──────────────────────────────────────────────

proc makeFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

type ProviderBundle = object
  completeFn: CompleteFn
  streamFn:   StreamFn   ## nil when provider has no streaming support

proc buildProviderBundle(preferencesMd: string): ProviderBundle {.gcsafe.} =
  var providerName = "zhipu"
  var modelName    = ""

  if preferencesMd.len > 0:
    try:
      {.cast(gcsafe).}:
        let t = parsetoml.parseString(preferencesMd)
        if t.hasKey("provider"): providerName = t["provider"].getStr()
        if t.hasKey("model"):    modelName    = t["model"].getStr()
    except: discard

  case providerName
  of "openrouter":
    let key     = getEnv("OPENROUTER_API_KEY")
    let model   = if modelName.len > 0: modelName else: "openai/gpt-4o-mini"
    let adapter = newOpenRouterAdapter(key, model = model)
    result = ProviderBundle(completeFn: makeFn(adapter),
                            streamFn:   adapter.makeStreamFn())
  of "anthropic":
    let key   = getEnv("ANTHROPIC_API_KEY")
    let model = if modelName.len > 0: modelName else: "claude-opus-4-6"
    result = ProviderBundle(completeFn: makeFn(newAnthropicAdapter(key, model = model)))
  of "gemini":
    let key   = getEnv("GEMINI_API_KEY")
    let model = if modelName.len > 0: modelName else: "gemini-2.0-flash"
    result = ProviderBundle(completeFn: makeFn(newGeminiAdapter(key, model = model)))
  of "minimax":
    let key   = getEnv("MINIMAX_API_KEY")
    let model = if modelName.len > 0: modelName else: "MiniMax-M2"
    result = ProviderBundle(completeFn: makeFn(newMiniMaxAdapter(key, model = model)))
  else:
    let key   = getEnv("ZHIPU_API_KEY")
    let model = if modelName.len > 0: modelName else: "glm-4.7"
    result = ProviderBundle(completeFn: makeFn(newZhipuAdapter(key, model = model)))

## Backwards-compat alias used by ctlProviderTest.
proc buildCompleteFn(preferencesMd: string): CompleteFn {.gcsafe.} =
  buildProviderBundle(preferencesMd).completeFn

proc buildFallbackFn(primary: CompleteFn; fallbacks: seq[CompleteFn]): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let r = primary(req)
    if r.isOk: return r
    for fb in fallbacks:
      let r2 = fb(req)
      if r2.isOk: return r2
    r

# ── ctl provider test ──────────────────────────────────────────────────────────

proc ctlProviderTest(name: string) =
  let fn = buildCompleteFn("provider = \"" & name & "\"")
  var h = newHistory()
  h.addUser("ping")
  let req  = buildPrompt("Reply with one word: pong", h, "")
  let resp = fn(req)
  if resp.isOk:
    echo "OK — " & name & " responded: " & resp.value.text
  else:
    echo "FAIL — " & name & ": " & resp.error
    quit(1)

# ── daemon ─────────────────────────────────────────────────────────────────────
##
## Architecture (post-refactor):
##
##   globalOutbox: AsyncQueue[OutboundMessage] — all orchestrators write here.
##   Daemon loop is async; Telegram uses pollTimeout=0 (non-blocking per iter).
##   Each iteration: drain globalOutbox → drain Discord → poll Telegram → yield.
##   Orchestrators are asyncSpawn tasks; debounce lives in collectWithDebounce
##   (withTimeout, timer-exact). Streaming uses an OS thread + Channel[string].
##
## Stream routing:
##   OutboundMessage.streamId non-empty → streaming turn.
##   streamMsgIds[streamId] = (channel, channelMsgId):
##     - first partial: send new message, store id
##     - subsequent partials: editMessage
##     - isPartial=false: editMessage + delete from streamMsgIds

proc ensureSession(sm:           var SessionManager;
                   msg:          InboundMessage;
                   memory:       MdFileAdapter;
                   completeFn:   CompleteFn;
                   streamFn:     StreamFn;
                   toolClients:  seq[McpClientAdapter];
                   tools:        seq[ToolDescription];
                   globalOutbox: AsyncQueue[OutboundMessage];
                   log:          Logger;
                   msgSeq:       var int) {.gcsafe.} =
  ## Creates session + orchestrator on first contact; then enqueues message.
  ## Fire-and-forget: does NOT wait for reply.
  let uid   = $msg.userId
  let isNew = not sm.hasSession(msg.userId)
  let entry = sm.getOrCreate(msg.userId)

  if isNew:
    let ctx        = memory.loadContext(msg.userId)
    let primary    = buildCompleteFn(ctx.preferencesMd)
    let fallbackFn = buildFallbackFn(primary, @[completeFn])
    ## Merge global tools with per-user skill overrides.
    var sessionClients = toolClients
    var sessionTools   = tools
    {.cast(gcsafe).}:
      let userSkillsDir = memory.paddocksDir / $msg.userId / "skills"
      let userSkills    = mergeSkills(@[], loadUserSkills(userSkillsDir))
      for m in userSkills:
        var client = newDenoSkillAdapter(m.script, m.permissions)
        let res = client.listTools()
        if res.isOk:
          for s in res.value:
            sessionTools.add(ToolDescription(
              name:        s.name,
              description: s.description,
              schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
            ))
        sessionClients.add(client)
    asyncSpawn runOrchestrator(entry.inbox, globalOutbox, memory,
                               fallbackFn, streamFn, sessionClients, sessionTools)
    log.info("new session: " & uid)

  sm.recordChannel(msg.userId, msg.channel, msg.channelId)
  inc msgSeq
  let msgId   = uid & "-" & $msgSeq
  let replyTo = if msg.channel == ckTelegram: msg.channelId else: ""
  ## Encode attachment URL in payload when present (orchestrator will decode).
  let payload = if msg.mediaUrl.len > 0:
                  $(%* {"text": msg.text, "mediaUrl": msg.mediaUrl})
                else:
                  msg.text
  entry.inbox.addLastNoWait(
    newTaskMsg(msgId, tkUserMsg, uid, payload, msg.channel, replyTo))

proc routeOutbound(msg:          OutboundMessage;
                   tgAdapter:    var TelegramAdapter;
                   dcAdapter:    DiscordAdapter;
                   wcAdapter:    var WeComAdapter;
                   fsAdapter:    var FeishuAdapter;
                   log:          Logger;
                   streamMsgIds: var Table[string, string]) {.gcsafe.} =
  ## Routes one outbound message to the correct channel adapter.
  ## Handles stream id → channel message id mapping for in-place edits.
  if msg.streamId.len == 0:
    ## Regular (non-streaming) message.
    case msg.channel
    of ckTelegram:
      tgAdapter.send(msg).isOkOr: log.error("tg send: " & error)
    of ckDiscord:
      dcAdapter.send(msg).isOkOr: log.error("dc send: " & error)
    of ckWeCom:
      wcAdapter.send(msg).isOkOr: log.error("wc send: " & error)
    of ckFeishu:
      fsAdapter.send(msg).isOkOr: log.error("fs send: " & error)
    of ckWeChat, ckQQ:
      log.warn("routeOutbound: channel not yet implemented: " & $msg.channel)
    return

  ## Streaming message — send first, then edit in place.
  if msg.streamId in streamMsgIds:
    let chMsgId = streamMsgIds[msg.streamId]
    case msg.channel
    of ckTelegram:
      tgAdapter.editMessage(msg.userId, chMsgId, msg.text).isOkOr:
        log.warn("tg editMessage: " & error)
    of ckDiscord:
      dcAdapter.editMessage(msg.userId, chMsgId, msg.text).isOkOr:
        log.warn("dc editMessage: " & error)
    of ckWeCom, ckWeChat, ckQQ, ckFeishu:
      discard  ## no in-place edit support
  else:
    ## First partial — send new message, record id.
    var chMsgId = ""
    case msg.channel
    of ckTelegram:
      chMsgId = tgAdapter.sendReturnId(msg).valueOr:
        log.error("tg sendReturnId: " & error); ""
    of ckDiscord:
      chMsgId = dcAdapter.sendReturnId(msg).valueOr:
        log.error("dc sendReturnId: " & error); ""
    of ckWeCom, ckWeChat, ckQQ, ckFeishu:
      discard  ## no streaming support
    if chMsgId.len > 0:
      streamMsgIds[msg.streamId] = chMsgId

  if not msg.isPartial:
    streamMsgIds.del(msg.streamId)

proc startDaemon(cfg: DonkeyConfig; log: Logger) {.async: (raises: [Exception]).} =
  ## Async daemon: Telegram (pollTimeout=0) + Discord (gateway thread) + WeCom (webhook thread).
  ## Loop: drain globalOutbox → drain Discord → drain WeCom → poll Telegram → sleepAsync(100ms)
  log.info("daemon starting — Telegram + Discord + WeCom")

  let telegramToken = getEnv("TELEGRAM_BOT_TOKEN")
  if telegramToken.len == 0:
    log.error("TELEGRAM_BOT_TOKEN not set"); quit(1)

  let discordToken  = getEnv("DISCORD_BOT_TOKEN")
  let wecomCorpId   = getEnv("WECOM_CORP_ID")
  let feishuAppId   = getEnv("FEISHU_APP_ID")
  let memory        = MdFileAdapter(paddocksDir: cfg.paddocks)
  let identityPath  = cfg.home / "identities.tsv"

  ## pollTimeout=0: non-blocking Telegram check each iteration.
  var tgAdapter = newTelegramAdapter(telegramToken, identityPath, pollTimeout = 0)
  var dcAdapter = newDiscordAdapter(discordToken, identityPath)
  let wecomAgentIdStr = getEnv("WECOM_AGENT_ID")
  let wecomAgentId    = if wecomAgentIdStr.len > 0: parseInt(wecomAgentIdStr) else: 0
  var wcAdapter = newWeComAdapter(wecomCorpId, getEnv("WECOM_CORP_SECRET"),
                                  getEnv("WECOM_CALLBACK_TOKEN"), wecomAgentId,
                                  identityPath)
  var fsAdapter = newFeishuAdapter(feishuAppId, getEnv("FEISHU_APP_SECRET"),
                                   identityPath)

  if discordToken.len > 0:
    dcAdapter.startGateway()
    let appId = dcAdapter.getAppId().valueOr:
      log.warn("Discord getAppId failed: " & error); ""
    if appId.len > 0:
      dcAdapter.registerSlashCommands(appId).isOkOr:
        log.warn("Discord slash cmd reg failed: " & error)
    log.info("Discord gateway started")
  else:
    log.info("DISCORD_BOT_TOKEN not set — Discord disabled")

  if wecomCorpId.len > 0:
    let wcPort = Port(parseInt(if getEnv("WECOM_WEBHOOK_PORT").len > 0:
                                 getEnv("WECOM_WEBHOOK_PORT") else: "8080"))
    wcAdapter.startWebhook(wcPort)
    log.info("WeCom webhook listener started on port " & $wcPort)
  else:
    log.info("WECOM_CORP_ID not set — WeCom disabled")

  if feishuAppId.len > 0:
    fsAdapter.startGateway()
    log.info("Feishu WebSocket gateway started")
  else:
    log.info("FEISHU_APP_ID not set — Feishu disabled")

  var toolClients: seq[McpClientAdapter]
  var tools: seq[ToolDescription]
  {.cast(gcsafe).}:
    for entry in loadToolRegistry(cfg.home / "tools.toml"):
      var client = buildMcpClient(entry)
      let schemasRes = client.listTools()
      if schemasRes.isOk:
        for s in schemasRes.value:
          tools.add(ToolDescription(
            name:        s.name,
            description: s.description,
            schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
          ))
      toolClients.add(client)
    for m in loadSkillRegistry(cfg.home / "skills.toml"):
      var client = newDenoSkillAdapter(m.script, m.permissions)
      let schemasRes = client.listTools()
      if schemasRes.isOk:
        for s in schemasRes.value:
          tools.add(ToolDescription(
            name:        s.name,
            description: s.description,
            schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
          ))
      toolClients.add(client)

  ## Global fallback provider (OpenRouter).
  let orKey = getEnv("OPENROUTER_API_KEY")
  let orAdapter   = newOpenRouterAdapter(orKey)
  let globalCompleteFn: CompleteFn =
    if orKey.len > 0: makeFn(orAdapter) else: nil
  let globalStreamFn: StreamFn =
    if orKey.len > 0: orAdapter.makeStreamFn() else: nil

  ## Shared async queue — all orchestrators post replies here.
  let globalOutbox = newAsyncQueue[OutboundMessage]()

  var sm:           SessionManager
  var streamMsgIds: Table[string, string]   ## streamId → channel message id
  var msgSeq:       int
  sm.init()

  log.info("polling for messages…")
  while true:

    ## 1. Drain globalOutbox (non-blocking: stop when empty).
    while globalOutbox.len > 0:
      let outMsg = await globalOutbox.get()
      log.info("reply user=" & $outMsg.userId & " chars=" & $outMsg.text.len &
               (if outMsg.streamId.len > 0: " [stream]" else: ""))
      routeOutbound(outMsg, tgAdapter, dcAdapter, wcAdapter, fsAdapter, log, streamMsgIds)

    ## 2. Drain Discord events (non-blocking).
    if discordToken.len > 0:
      var (hasEvent, event) = dcAdapter.tryRecvEvent()
      while hasEvent:
        case event.kind

        of deMessage:
          let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
          if event.content.strip() == "/mycode":
            let code   = dcAdapter.resolver.generateLinkCode(userId)
            dcAdapter.send(OutboundMessage(
              userId:  userId,
              channel: ckDiscord,
              text:    "Your link code: **" & code & "** (valid 10 minutes)\n" &
                       "Enter `/continue " & code & "` on another channel to reconnect.",
            )).isOkOr: log.error("dc /mycode reply: " & error)
          else:
            ensureSession(sm, InboundMessage(
              userId:    userId,
              channel:   ckDiscord,
              channelId: event.messageId,
              text:      event.content,
            ), memory, globalCompleteFn, globalStreamFn,
            toolClients, tools, globalOutbox, log, msgSeq)

        of deInteraction:
          let code   = event.content.strip()
          let linked = dcAdapter.resolver.consumeLinkCode(
            code, ckDiscord, event.discordUserId)
          let replyText =
            if linked: "Session reconnected! Your conversation history carries over."
            else:      "Invalid or expired code. Generate a fresh one with `/mycode`."
          dcAdapter.sendInteractionResponse(
            event.interactionId, event.interactionToken, replyText).isOkOr:
            log.error("dc interaction response: " & error)

        (hasEvent, event) = dcAdapter.tryRecvEvent()

    ## 3. Drain WeCom webhook events (non-blocking).
    if wecomCorpId.len > 0:
      var (hasWcEvent, wcEvent) = wcAdapter.tryRecvEvent()
      while hasWcEvent:
        if wcEvent.msgType == "text" and wcEvent.content.strip().len > 0:
          let userId = wcAdapter.resolver.resolve(ckWeCom, wcEvent.fromUser)
          ensureSession(sm, InboundMessage(
            userId:    userId,
            channel:   ckWeCom,
            channelId: wcEvent.msgId,
            text:      wcEvent.content,
          ), memory, globalCompleteFn, globalStreamFn,
          toolClients, tools, globalOutbox, log, msgSeq)
        (hasWcEvent, wcEvent) = wcAdapter.tryRecvEvent()

    ## 4. Drain Feishu gateway events (non-blocking).
    if feishuAppId.len > 0:
      var (hasFsEvent, fsEvent) = fsAdapter.tryRecvEvent()
      while hasFsEvent:
        if fsEvent.msgType == "text" and fsEvent.content.strip().len > 0:
          let userId = fsAdapter.resolver.resolve(ckFeishu, fsEvent.openId)
          ensureSession(sm, InboundMessage(
            userId:    userId,
            channel:   ckFeishu,
            channelId: fsEvent.msgId,
            text:      fsEvent.content,
          ), memory, globalCompleteFn, globalStreamFn,
          toolClients, tools, globalOutbox, log, msgSeq)
        (hasFsEvent, fsEvent) = fsAdapter.tryRecvEvent()

    ## 5. Telegram poll (non-blocking: timeout=0 returns immediately).
    let tgMsgs = tgAdapter.receive().valueOr:
      log.error("telegram receive: " & error)
      await sleepAsync(milliseconds(500))
      continue

    for msg in tgMsgs:
      let cmd = msg.text.strip()

      if cmd == "/mycode":
        let code = tgAdapter.resolver.generateLinkCode(msg.userId)
        tgAdapter.send(OutboundMessage(
          userId:  msg.userId,
          channel: ckTelegram,
          text:    "Your link code: `" & code & "` (valid 10 minutes)\n" &
                   "Type `/continue " & code & "` on Discord to reconnect.",
          replyTo: msg.channelId,
        )).isOkOr: log.error("tg /mycode reply: " & error)
        continue

      if cmd == "/help":
        tgAdapter.send(OutboundMessage(
          userId:  msg.userId,
          channel: ckTelegram,
          text:    "*Donkey* — comandos disponíveis:\n\n" &
                   "/help — esta mensagem\n" &
                   "/reset — reinicia a conversa atual\n" &
                   "/mycode — gera código de linkagem cross-channel\n" &
                   "/continue `<código>` — conecta este canal a outra sessão\n\n" &
                   "Envie qualquer mensagem para conversar.\n" &
                   "Imagens, documentos e áudios são aceitos.",
          replyTo: msg.channelId,
        )).isOkOr: log.error("tg /help reply: " & error)
        continue

      if cmd == "/reset":
        if sm.hasSession(msg.userId):
          let entry = sm.getOrCreate(msg.userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, tkReset, $msg.userId, "",
                       ckTelegram, msg.channelId))
        else:
          tgAdapter.send(OutboundMessage(
            userId:  msg.userId,
            channel: ckTelegram,
            text:    "Nenhuma conversa ativa para reiniciar.",
            replyTo: msg.channelId,
          )).isOkOr: discard
        continue

      ## Typing indicator before handing off to the orchestrator.
      tgAdapter.sendTyping(msg.userId).isOkOr: discard

      ensureSession(sm, msg, memory, globalCompleteFn, globalStreamFn,
                    toolClients, tools, globalOutbox, log, msgSeq)

    ## 4. Yield to Chronos — lets orchestrators and streaming threads run.
    await sleepAsync(milliseconds(100))

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

  let registryPath = cfg.home / "tools.toml"
  let memory       = MdFileAdapter(paddocksDir: cfg.paddocks)

  if args.len >= 1 and args[0] == "ctl":
    if args.len >= 3 and args[1] == "user" and args[2] == "list":
      ctlUserList(memory); quit(0)
    elif args.len >= 4 and args[1] == "user" and args[2] == "show":
      ctlUserShow(memory, args[3]); quit(0)
    elif args.len >= 4 and args[1] == "session" and args[2] == "list":
      ## Sessions are in-memory; this is only useful when called from within
      ## the daemon process. For an external CLI, it shows nothing.
      var sm: SessionManager
      sm.init()
      ctlSessionList(sm, args[3]); quit(0)
    elif args.len >= 4 and args[1] == "tool" and args[2] == "install":
      ctlToolInstall(registryPath, args[3], args[4 ..^ 1]); quit(0)
    elif args.len >= 5 and args[1] == "skill" and args[2] == "install":
      let skillsPath = cfg.home / "skills.toml"
      ctlSkillInstall(skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 3 and args[1] == "skill" and args[2] == "list":
      ctlSkillList(cfg.home / "skills.toml"); quit(0)
    elif args.len >= 5 and args[1] == "skill" and args[2] == "update":
      let skillsPath = cfg.home / "skills.toml"
      ctlSkillUpdate(skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 4 and args[1] == "provider" and args[2] == "test":
      ctlProviderTest(args[3]); quit(0)
    elif args.len >= 5 and args[1] == "memory" and args[2] == "search":
      when defined(withPostgres):
        let pgDsn = getEnv("DONKEY_PG_DSN")
        if pgDsn.len == 0: echo "DONKEY_PG_DSN not set"; quit(1)
        ctlMemorySearch(pgDsn, args[3], args[4]); quit(0)
      else:
        echo "Recompile with -d:withPostgres to use memory search"; quit(1)
    elif args.len >= 4 and args[1] == "memory" and args[2] == "import":
      when defined(withPostgres):
        let pgDsn = getEnv("DONKEY_PG_DSN")
        if pgDsn.len == 0: echo "DONKEY_PG_DSN not set"; quit(1)
        ctlMemoryImport(pgDsn, cfg.paddocks, args[3]); quit(0)
      else:
        echo "Recompile with -d:withPostgres to use memory import"; quit(1)
    else:
      printHelp(); quit(1)

  log.info("donkey " & Version & " starting")
  log.info("home: " & cfg.home)

  waitFor startDaemon(cfg, log)

when isMainModule:
  main()
