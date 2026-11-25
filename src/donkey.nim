## donkey — AI agent system entry point.

import std/[json, options, os, parseopt, strutils, tables, terminal, times]
when defined(posix):
  import std/posix
import chronos
import chronos/asyncsync
import chronos/timer as ctimer
import donkey/config/loader
import donkey/config/types
import donkey/config/dotenv
import donkey/config/tools_registry
import donkey/config/skills_registry
import donkey/adapters/tool/runtime_builder
import donkey/core/log
import donkey/infra/thread_handle
import donkey/app/route_health
import donkey/adapters/state/route_health_file
import donkey/app/daemon_endpoints
import donkey/adapters/filesystem/subagent_workspace
import donkey/app/turn_reaction
import donkey/app/cli_help
import donkey/core/pipeops
import donkey/adapters/http/circuit_breakers
import donkey/core/agent_events
import donkey/core/app_meta
import donkey/core/command_registry
import donkey/core/providers/smart_routing
import donkey/adapters/memory/md_file
import donkey/adapters/memory/reminder_store
import donkey/adapters/memory/dm_allowlist
import donkey/adapters/process/process_adapter
when defined(withPostgres) or defined(withSqlite):
  import donkey/adapters/memory/multigraph_runtime
import donkey/adapters/provider/openrouter
import donkey/adapters/provider/runtime_builder
import donkey/adapters/provider/model_catalog
import donkey/adapters/http/std_http
import donkey/adapters/channel/telegram
import donkey/adapters/channel/outbound_builder
import donkey/domain/channels/qq_pure
import donkey/app/inbound_gate
import donkey/core/security/dm_policy
import donkey/app/inbound_media
import donkey/adapters/filesystem/attachment_store
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_runtime
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wecom_runtime
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wechat_runtime
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/feishu
import donkey/adapters/channel/feishu_runtime
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/whatsapp_runtime
import donkey/adapters/channel/matrix
import donkey/adapters/channel/email
import donkey/adapters/channel/signal
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_runtime
import donkey/adapters/channel/slack_socket
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/line
import donkey/adapters/channel/line_runtime
import donkey/adapters/channel/cli_repl
import donkey/adapters/webhook/webhook_receiver
import donkey/domain/channels/line_policy
import donkey/adapters/tool/mcp_client
import donkey/adapters/tool/mcp_http_client
import donkey/adapters/tool/mcp_oauth
import donkey/adapters/tools/browser_executor
import donkey/domain/tools/browser_pure
import donkey/adapters/state/runtime_store
import donkey/adapters/state/schedule_store
import donkey/ports/schedules
import donkey/ports/backtrail
import donkey/adapters/decision/perplexity_backtrail
import donkey/app/blocking_executor
import donkey/domain/memory/query_policy_pure
import donkey/adapters/embedding/openrouter_embed
import donkey/adapters/state/pairing_store
import donkey/adapters/state/approval_store
import donkey/adapters/secrets/vault
import donkey/app/approval_runtime
import donkey/domain/message
import donkey/domain/agent_message
import donkey/domain/providers/descriptors
import donkey/ports/provider
import donkey/ports/http
import donkey/ports/channel
import donkey/ports/tool
import donkey/ports/runtime_state
import donkey/app/orchestrator
import donkey/app/sandbox
import donkey/app/ipc_server
import donkey/adapters/http/gateway_server
import donkey/app/chat_bridge
import donkey/domain/gateway/dashboard_pure
import donkey/domain/gateway/identity_pure
import donkey/app/heartbeat
import donkey/app/reminders
import donkey/app/attachment_retention
import donkey/app/scheduler_wiring
import donkey/app/metrics_server
import donkey/app/outbound_runtime
import donkey/app/gateway_drainer
import donkey/app/session_manager
import donkey/adapters/state/daemon_lease
import donkey/app/session_bootstrap
from donkey/app/skill_runtime import skillRegistry
import donkey/app/credential_runtime
import donkey/app/session_ingress
import donkey/app/doctor
import donkey/app/setup_wizard
import donkey/app/service_handler
import donkey/app/tui_handler
import donkey/app/daemon_start_handler
import donkey/ctl_handler
import donkey/ports/memory
import donkey/adapters/ipc/types    as ipcTypes


proc printVersion = echo versionText()

proc printHelp = echo cliHelpText()

# ── daemon ─────────────────────────────────────────────────────────────────────

const TelegramLongPollSec = 10
  ## Telegram holds getUpdates open until a message or this many seconds: a
  ## message arrives at once, and an idle bot makes one request per 10 s. The
  ## wait occupies one blocking-executor worker.
##
## Architecture (post-refactor):
##
##   globalOutbox: AsyncQueue[OutboundMessage] — all orchestrators write here.
##   Daemon loop is async; Telegram's getUpdates long-polls on the blocking
##   executor (app/blocking_executor), so the loop never waits for it.
##   Each iteration: drain globalOutbox → drain Discord → poll Telegram → yield.
##   Orchestrators are asyncSpawn tasks; debounce lives in collectWithDebounce
##   (withTimeout, timer-exact). Streaming runs on its own thread, which builds
##   the provider closure from a StreamFactory (app/tool_loop_runtime).
##
## Stream routing:
##   OutboundMessage.streamId non-empty → streaming turn.
##   presentationState.streamMsgIds[channel|user|stream] = channelMsgId:
##     - first partial: send new message, store id
##     - subsequent partials: editMessage
##     - isPartial=false: editMessage + delete from presentationState

proc makeTgTypingFn(token, identityPath, apiBase: string;
                    settings: TelegramSettings; log: Logger): TypingFn =
  ## Returns a TypingFn that sends typing indicators to Telegram users.
  ## Uses its own TelegramAdapter instance (token + resolver shared via ref).
  let tg = new TelegramAdapter
  tg[] = newTelegramAdapter(token, identityPath, apiBase = apiBase,
                            settings = settings,
                            pollTimeout = 0)
  result = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].} =
    if channel == ckTelegram:
      try:
        tg[].sendTyping(userId).isOkOr:
          log.warn("tg sendTyping failed for user=" & $userId & " reason=" & error)
      except CatchableError: discard

type DaemonToolBundle = object
  clients: seq[ToolRuntimePort]
  tools:   seq[ToolDescription]
  browserRuntime: BrowserExecutor

type GlobalProviderBundle = object
  completeFn:    CompleteFn
  streamFactory: StreamFactory

type DaemonEnv = object
  telegramToken: string
  discordToken:  string
  discordGuildId: string
  wecomCorpId:   string
  wechatAppId:   string
  feishuAppId:   string
  slackBotToken: string
  slackAppToken: string
  dingTalkAppKey: string
  dingTalkAppSecret: string
  dingTalkRobotCode: string
  qqApiBase:     string
  qqOfficialAppId: string
  qqOfficialApiBase: string
  memory:        MdFileAdapter
  identityPath:  string
  wecomAgentId:  int
  whatsappAccessToken: string
  whatsappPhoneNumberId: string
  webhookPort: int
  webhookHost: string
  webhookTlsCert: string
  webhookTlsKey: string
  slackSigningSecret: string
  feishuVerificationToken: string
  feishuEncryptKey: string
  lineChannelSecret: string
  lineChannelAccessToken: string
  lineAllowedGroups: seq[string]
  lineAllowedUsers: seq[string]
  matrixWebhookToken: string
  whatsappVerifyToken: string
  whatsappAppSecret: string
  wecomCallbackToken: string
  wechatCallbackToken: string
  retiredWebhookPorts: seq[string]
    ## *_WEBHOOK_PORT variables still set from before the shared receiver
  matrixConfigured: bool
  qqOneBotSecret: string

type DaemonAdapters = object
  tg: TelegramAdapter
  dc: DiscordAdapter
  wc: WeComAdapter
  wch: WeChatAdapter
  qq: QQChannelAdapter
  fs: FeishuAdapter
  sl: SlackAdapter
  dt: DingTalkAdapter
  ln: LineAdapter
  mx: MatrixAdapter
  em: EmailAdapter
  wa: WhatsAppAdapter
  cli: CliAdapter
  signal: SignalAdapter

proc buildRuntimeOutboundPorts(adapters: var DaemonAdapters): OutboundChannelPorts =
  let signalPtr =
    if adapters.signal.account.len > 0: addr adapters.signal
    else: nil
  buildOutboundPorts(
    addr adapters.tg, addr adapters.dc, addr adapters.wc,
    addr adapters.wch, addr adapters.qq, addr adapters.fs, addr adapters.mx,
    addr adapters.em, addr adapters.sl, addr adapters.dt, addr adapters.wa,
    addr adapters.cli, signalPtr, addr adapters.ln)

type DaemonServices = object
  toolClients:      seq[ToolRuntimePort]
  tools:            seq[ToolDescription]
  browserRuntime:   BrowserExecutor
  globalCompleteFn: CompleteFn
  globalStreamFactory: StreamFactory
  tgTypingFn:       TypingFn
  globalSearchFn:   SearchFn
  modelCatalogLoader: ModelCatalogLoader
    ## One for the daemon: its 5-minute catalog cache lives in the closure,
    ## so building one per poll (as Telegram did) never reused it.

type
  PollResult = Result[seq[(string, InboundMessage)], string]
    ## Sender and message, unresolved: identities are resolved on the loop.
    ## The polls run on the blocking executor and get plain data (IMAP access,
    ## the signal-cli socket path), never the adapter.

proc takeFinished[T](poll: var Future[Result[T, string]]): Option[Result[T, string]] =
  ## A channel poll's result once its job finished, clearing the slot for the
  ## next poll; none while it is still running.
  if poll == nil or not poll.finished:
    return none(Result[T, string])
  let value =
    try:
      poll.read()
    except CatchableError as e:
      err(Result[T, string], e.msg)
  poll = nil
  some(value)

type DaemonRuntime = ref object
  globalOutbox:         AsyncQueue[OutboundMessage]
  sm:                   SessionManager
  apiChatBridge:        ChatBridge
    ## API turns: the gateway registers and waits, the outbox drainer
    ## delivers `api:` replies here instead of to a channel port. Both run on
    ## the daemon loop.
  stateStore:           RuntimeStateStore
  ledger:               DeliveryLedgerPort
  ledgerCompaction:     Future[Result[bool, string]]
    ## The ledger compaction in flight on the blocking executor; it holds a
    ## pointer to `stateStore`, so shutdown awaits it.
  presentationState:    PresentationState
  routeHealth:          RouteHealth
  lastReminderCheckMs:  int64
  tgPoll:               Future[Result[HttpResponse, string]]
    ## Telegram's getUpdates in flight on the blocking executor; nil between polls.
  emailPoll:            Future[PollResult]
  signalPoll:           Future[PollResult]
    ## The email and Signal polls in flight on the blocking executor.
  lastEmailPollMs:      int64
  lastSignalPollMs:     int64
  lineReplay:           LineReplayCache
  msgSeq:               int
  daemonStartMs:        int64

type DaemonContext = ref object
  env:      DaemonEnv
  adapters: DaemonAdapters
  services: DaemonServices
  runtime:  DaemonRuntime

type DaemonTickResult = object
  ok:               bool
  remindersChecked: bool

type DaemonLoopResult = object
  sleepMs: int

type DaemonBootstrap = object
  memory: MdFileAdapter
  ctx:    DaemonContext

proc loadDaemonToolBundle(cfg: DonkeyConfig; log: Logger): DaemonToolBundle =
  for entry in loadToolRegistry(cfg.home / "tools.toml"):
    var port: ToolRuntimePort
    var schemasRes: Result[seq[ToolSchema], string]
    case entry.kind
    of tkMcp:
      var client = buildMcpClient(entry)
      schemasRes = client.listTools()
      port = client.toRuntimePort()
    of tkMcpHttp:
      ## The bearer comes from the variable the entry names, read from the
      ## environment snapshot; the registry holds only the name.
      let bearer = if entry.tokenEnv.len > 0: cfg.env.get(entry.tokenEnv) else: ""
      let tokenFn: McpHttpTokenFn =
        if entry.oauth:
          mcpTokenSource(cfg.home / "state" / McpOAuthDirName, entry.url,
            secretOf = proc(name: string): string {.gcsafe.} = cfg.env.get(name))
        else: nil
      var client = newMcpHttpClient(entry.url, bearer = bearer, tokenFn = tokenFn)
      schemasRes = client.listTools()
      port = client.toRuntimePort()
    if schemasRes.isOk:
      for s in schemasRes.value:
        result.tools.add(ToolDescription(
          name:        s.name,
          description: s.description,
          schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
        ))
    else:
      log.warn("mcp: " & (if entry.kind == tkMcpHttp: entry.url else: entry.command) &
               ": " & schemasRes.error)
    result.clients.add(port)
  for manifest in loadSkillRegistry(cfg.home / "skills.toml"):
    let runtimeRes = buildDenoSkillRuntime(
      manifest.script, manifest.permissions, buildSkillRuntimePolicy(cfg, manifest.name))
    if runtimeRes.isOk:
      for s in runtimeRes.value.schemas:
        result.tools.add(ToolDescription(
          name:        s.name,
          description: s.description,
          schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
        ))
      result.clients.add(runtimeRes.value.port)

  ## Browser tools are opt-in: no process is spawned until the first
  ## browser_navigate call. Backend selection is pure/strategy-based.
  let parsedBackend = parseBrowserBackend(cfg.env.get("DONKEY_BROWSER_BACKEND"))
  var browserBackend = bbOff
  if parsedBackend.isSome:
    browserBackend = parsedBackend.get()
  elif cfg.env.get("DONKEY_BROWSER_BACKEND").strip.len > 0:
    log.warn("browser: invalid DONKEY_BROWSER_BACKEND='" &
             cfg.env.get("DONKEY_BROWSER_BACKEND") & "'; tools disabled")
  if browserBackend != bbOff:
    let rawBrowserTimeout = cfg.env.get("DONKEY_BROWSER_TIMEOUT_MS").strip()
    var browserTimeoutMs = BrowserDefaultTimeoutMs
    if rawBrowserTimeout.len > 0:
      try:
        discard parseInt(rawBrowserTimeout)
        browserTimeoutMs = parseBrowserTimeoutMs(rawBrowserTimeout)
      except ValueError:
        log.warn("browser: invalid DONKEY_BROWSER_TIMEOUT_MS='" &
                 rawBrowserTimeout & "'; using " & $BrowserDefaultTimeoutMs)
    let browserRuntime =
      try:
        newBrowserExecutor(
          backend = browserBackend,
          executablePath = cfg.env.get("DONKEY_BROWSER_PATH"),
          profileBaseDir = cfg.env.get("DONKEY_BROWSER_PROFILE_DIR"),
          proxyServer = cfg.env.get("DONKEY_BROWSER_PROXY"),
          timeoutMs = browserTimeoutMs)
      except CatchableError as e:
        log.warn("browser disabled: " & e.msg)
        return
    result.browserRuntime = browserRuntime
    let browserPort = browserRuntime.toRuntimePort()
    let browserSchemas = browserPort.listTools().valueOr:
      @[]
    for s in browserSchemas:
      result.tools.add(ToolDescription(
        name:        s.name,
        description: s.description,
        schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
      ))
    result.clients.add(browserPort)

proc makeProviderFn[A](a: A): CompleteFn =
  makeFn(a)

proc openRouterKey(env: Environment): string =
  let openRouter = descriptorOr("openrouter")
  if openRouter.envNames.len > 0: env.get(openRouter.envNames[0]) else: ""

proc openRouterStream(apiKey: string): StreamFn {.nimcall, gcsafe.} =
  ## Runs on the stream thread: the adapter and its closure are built there.
  newOpenRouterAdapter(apiKey).makeStreamFn()

proc buildGlobalProviderBundle(env: Environment): GlobalProviderBundle =
  let orKey = openRouterKey(env)
  let orAdapter = newOpenRouterAdapter(orKey)
  result.completeFn = if orKey.len > 0: makeProviderFn(orAdapter) else: nil
  result.streamFactory =
    if orKey.len > 0: StreamFactory(build: openRouterStream, credential: orKey,
                                 provider: "openrouter")
    else: StreamFactory()

func routeCostProviderIds(): seq[string] =
  ## Cost hints cover every provider that has a descriptor.
  for descriptor in providerDescriptors():
    result.add descriptor.id

proc buildGlobalSearchFn(memory: MdFileAdapter): SearchFn {.gcsafe.}

func accessPortOf(memory: MdFileAdapter): AccessPort =
  ## Revocation from the profile, DM access from the instance allowlist.
  memory.toAccessPort(dmAllowlistOf(memory.paddocksDir))

func defaultMagmaSqlitePath(home: string): string =
  home / "state" / "magma.sqlite"

func configuredMagmaSqlitePath(home: string; env: Environment): string =
  when defined(withSqlite):
    env.get("DONKEY_MAGMA_SQLITE_PATH", defaultMagmaSqlitePath(home))
  else:
    env.get("DONKEY_MAGMA_SQLITE_PATH")

proc daemonBacktrail(cfg: DonkeyConfig): BacktrailPort =
  ## Opt-in: on when PERPLEXITY_API_KEY is set (the vault fills it), off
  ## with DONKEY_BACKTRAIL=off. Messages then go to Perplexity's own
  ## endpoint (paid access, not used for training) to be classified.
  if cfg.env.get("DONKEY_BACKTRAIL").strip.toLowerAscii in ["off", "0", "false", "no"]:
    return BacktrailPort()
  let key = cfg.env.get("PERPLEXITY_API_KEY").strip
  if key.len == 0:
    return BacktrailPort()
  ## The HTTP runs on a worker (app/blocking_executor): only the key and the
  ## message cross, as text; the loop keeps serving while Perplexity answers.
  BacktrailPort(classify: proc(message: string): Future[Result[RouteDecision, string]]
                              {.async.} =
    var raw: Result[string, string]
    try:
      raw = await runOffLoop(perplexityBacktrailJob, $(%*{"key": key, "message": message}))
    except CatchableError as e:
      raw = err(Result[string, string], e.msg)
    if raw.isErr:
      return err(Result[RouteDecision, string], raw.error)
    return decodeDecision(raw.get))

proc initDaemonServices(cfg: DonkeyConfig;
                        env: DaemonEnv;
                        log: Logger): DaemonServices =
  let toolBundle = loadDaemonToolBundle(cfg, log)
  result.toolClients = toolBundle.clients
  result.tools = toolBundle.tools
  result.browserRuntime = toolBundle.browserRuntime

  let providerBundle = buildGlobalProviderBundle(cfg.env)
  result.globalCompleteFn = providerBundle.completeFn
  result.globalStreamFactory = providerBundle.streamFactory
  result.tgTypingFn = makeTgTypingFn(env.telegramToken, env.identityPath,
                                     cfg.env.stripped("DONKEY_TELEGRAM_API_BASE"),
                                     telegramSettings(cfg.env), log)
  result.globalSearchFn = buildGlobalSearchFn(env.memory)
  result.modelCatalogLoader = buildModelCatalogLoader(cfg.env)
  when defined(withPostgres) or defined(withSqlite):
    if result.globalSearchFn != nil:
      log.info("MAGMA semantic search enabled")
  if daemonBacktrail(cfg).backtrailAvailable:
    log.info("Backtrail on: messages about the past start with a search " &
             "(Perplexity Decider 1.3; DONKEY_BACKTRAIL=off to disable)")

proc loadDaemonEnv(cfg: DonkeyConfig; log: Logger): DaemonEnv =
  result.telegramToken = cfg.env.get("TELEGRAM_BOT_TOKEN").strip()
  if result.telegramToken.len == 0:
    log.warn("TELEGRAM_BOT_TOKEN not set — Telegram disabled")

  result.discordToken = cfg.env.get("DISCORD_BOT_TOKEN")
  result.discordGuildId = cfg.env.get("DISCORD_GUILD_ID")
  result.wecomCorpId = cfg.env.get("WECOM_CORP_ID")
  result.wechatAppId = cfg.env.get("WECHAT_APP_ID")
  result.feishuAppId = cfg.env.get("FEISHU_APP_ID")
  result.slackBotToken = cfg.env.get("SLACK_BOT_TOKEN")
  result.slackAppToken = cfg.env.get("SLACK_APP_TOKEN")
  result.dingTalkAppKey = cfg.env.get("DINGTALK_APP_KEY")
  result.dingTalkAppSecret = cfg.env.get("DINGTALK_APP_SECRET")
  result.dingTalkRobotCode = cfg.env.get("DINGTALK_ROBOT_CODE")
  result.qqApiBase = cfg.env.get("QQ_ONEBOT_URL")
  result.qqOfficialAppId = cfg.env.get("QQ_OFFICIAL_APP_ID")
  result.qqOfficialApiBase = cfg.env.get("QQ_OFFICIAL_API_BASE")
  let pgDsn = cfg.env.get("DONKEY_PG_DSN")
  result.memory = MdFileAdapter(
    paddocksDir:     cfg.paddocks,
    magmaDsn:       pgDsn,
    magmaSqlitePath: configuredMagmaSqlitePath(cfg.home, cfg.env),
    magmaEnv:       magmaEnvironment(cfg.env),
    magmaSqliteVectorPath:
      block:
        let vecPath = cfg.env.get("DONKEY_SQLITE_VEC_PATH")
        if vecPath.len > 0: vecPath else: cfg.env.get("DONKEY_SQLITE_VECTOR_PATH"),
  )
  result.identityPath = cfg.home / "identities.tsv"
  let wecomAgentIdStr = cfg.env.get("WECOM_AGENT_ID")
  result.wecomAgentId =
    if wecomAgentIdStr.len > 0: parseInt(wecomAgentIdStr) else: 0
  
  # WhatsApp Cloud API
  result.whatsappAccessToken = cfg.env.get("WHATSAPP_ACCESS_TOKEN")
  result.whatsappPhoneNumberId = cfg.env.get("WHATSAPP_PHONE_NUMBER_ID")

  # HTTP webhook receiver (Slack / Feishu / DingTalk / Matrix / WhatsApp)
  let webhookPortStr = cfg.env.get("DONKEY_WEBHOOK_PORT")
  result.webhookPort = 0
  if webhookPortStr.len > 0:
    try:
      result.webhookPort = parseInt(webhookPortStr)
    except ValueError:
      result.webhookPort = 0
  let webhookHost = cfg.env.get("DONKEY_WEBHOOK_HOST")
  result.webhookHost = if webhookHost.len > 0: webhookHost else: "127.0.0.1"
  result.webhookTlsCert = cfg.env.get("DONKEY_WEBHOOK_TLS_CERT").strip()
  result.webhookTlsKey = cfg.env.get("DONKEY_WEBHOOK_TLS_KEY").strip()
  result.slackSigningSecret = cfg.env.get("SLACK_SIGNING_SECRET")
  result.feishuVerificationToken = cfg.env.get("FEISHU_VERIFICATION_TOKEN")
  result.feishuEncryptKey = cfg.env.get("FEISHU_ENCRYPT_KEY")
  ## LINE: the route is mounted only when the access token exists; the channel
  ## secret is the HMAC key for X-Line-Signature. Groups are default-deny
  ## (empty = none), users are opt-in (empty = all) — see line_policy.
  result.lineChannelSecret = cfg.env.get("LINE_CHANNEL_SECRET").strip()
  result.lineChannelAccessToken = cfg.env.get("LINE_CHANNEL_ACCESS_TOKEN").strip()
  result.lineAllowedGroups = parseChatIdList(cfg.env.get("LINE_ALLOWED_GROUPS"))
  result.lineAllowedUsers = parseChatIdList(cfg.env.get("LINE_ALLOWED_USERS"))
  result.matrixWebhookToken = cfg.env.get("MATRIX_WEBHOOK_TOKEN")
  result.whatsappVerifyToken = cfg.env.get("WHATSAPP_VERIFY_TOKEN")
  result.whatsappAppSecret = cfg.env.get("WHATSAPP_APP_SECRET")
  result.wecomCallbackToken = cfg.env.get("WECOM_CALLBACK_TOKEN").strip()
  result.wechatCallbackToken = cfg.env.get("WECHAT_CALLBACK_TOKEN").strip()
  for retired in ["WECOM_WEBHOOK_PORT", "WECHAT_WEBHOOK_PORT",
                  "QQ_ONEBOT_WEBHOOK_PORT", "QQ_ONEBOT_WEBHOOK_HOST"]:
    if cfg.env.get(retired).len > 0:
      result.retiredWebhookPorts.add retired
  result.matrixConfigured =
    cfg.env.get("MATRIX_HOMESERVER").len > 0 and
    cfg.env.get("MATRIX_BOT_USER_ID").len > 0 and
    cfg.env.get("MATRIX_ACCESS_TOKEN").len > 0
  result.qqOneBotSecret = cfg.env.get("QQ_ONEBOT_SECRET")

proc initDaemonAdapters(cfg: DonkeyConfig; env: DaemonEnv): DaemonAdapters =
  result.tg = newTelegramAdapter(
    env.telegramToken, env.identityPath,
    apiBase = cfg.env.get("DONKEY_TELEGRAM_API_BASE").strip(),
    pollTimeout = TelegramLongPollSec, settings = telegramSettings(cfg.env))
  result.dc = newDiscordAdapter(env.discordToken, env.identityPath,
                                requireMention = discordRequireMention(cfg.env),
                                allowedChannels = discordAllowedChannels(cfg.env))
  result.wc = newWeComAdapter(env.wecomCorpId, cfg.env.get("WECOM_CORP_SECRET"),
                              cfg.env.get("WECOM_CALLBACK_TOKEN"), env.wecomAgentId,
                              env.identityPath)
  result.wch = newWeChatAdapter(env.wechatAppId, cfg.env.get("WECHAT_APP_SECRET"),
                                cfg.env.get("WECHAT_CALLBACK_TOKEN"),
                                cfg.env.get("WECHAT_TEMPLATE_ID"),
                                env.identityPath)
  if env.qqOfficialAppId.len > 0 and cfg.env.get("QQ_OFFICIAL_CLIENT_SECRET").len > 0:
    result.qq = newQQOfficialChannelAdapter(
      env.qqOfficialAppId,
      cfg.env.get("QQ_OFFICIAL_CLIENT_SECRET"),
      env.identityPath,
      apiBase = cfg.env.get("QQ_OFFICIAL_API_BASE"),
      tokenBase = cfg.env.get("QQ_OFFICIAL_TOKEN_BASE"),
    )
  elif env.qqApiBase.len > 0:
    result.qq = newQQOneBotChannelAdapter(env.qqApiBase, cfg.env.get("QQ_ONEBOT_TOKEN"),
                                          env.identityPath)
  else:
    result.qq = newQQDisabledChannelAdapter(env.identityPath)
  result.fs = newFeishuAdapter(env.feishuAppId, cfg.env.get("FEISHU_APP_SECRET"),
                               env.identityPath)
  result.sl = newSlackAdapter(env.slackBotToken, env.identityPath)
  result.dt = newDingTalkAdapter(env.dingTalkAppKey, env.dingTalkAppSecret,
                                 env.dingTalkRobotCode, env.identityPath)
  ## A stale/bad `LINE_API_BASE` must not abort startup when LINE is not
  ## configured: construct at the default base in that case (the adapter then
  ## fails sends with "missing token", which is the truth).
  result.ln =
    if env.lineChannelAccessToken.len > 0:
      newLineAdapter(env.lineChannelAccessToken, env.identityPath,
                     apiBase = cfg.env.stripped("LINE_API_BASE"))
    else:
      newLineAdapter("", env.identityPath, apiBase = "https://api.line.me")
  result.mx = newMatrixAdapter(cfg.env.get("MATRIX_HOMESERVER"), cfg.env.get("MATRIX_BOT_USER_ID"),
                               cfg.env.get("MATRIX_ACCESS_TOKEN"), env.identityPath)
  result.em = newEmailAdapter(cfg.env.get("EMAIL_IMAP_HOST"), cfg.env.get("EMAIL_SMTP_HOST"),
                              cfg.env.get("EMAIL_USER"), cfg.env.get("EMAIL_PASSWORD"),
                              env.identityPath)
  result.cli = newCliAdapter()
  
  # WhatsApp (optional - only if credentials are set)
  if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
    result.wa = newWhatsAppAdapter(env.whatsappAccessToken, env.whatsappPhoneNumberId,
                                   env.identityPath)

  # Signal (optional - requires a running signal-cli daemon socket)
  let signalAccount = cfg.env.get("SIGNAL_ACCOUNT").strip()
  if signalAccount.len > 0:
    let rawSock = cfg.env.get("SIGNAL_SOCKET").strip()
    result.signal = newSignalAdapter(
      signalAccount,
      env.identityPath,
      sockPath = if rawSock.len > 0: rawSock else: SignalDefaultSock,
    )

proc envSeconds(env: Environment; name: string; default: int64): int64 =
  ## A positive whole number of seconds from the environment, or `default`.
  let raw = env.stripped(name)
  if raw.len == 0:
    return default
  try:
    let value = parseInt(raw)
    if value > 0: value else: default
  except ValueError:
    default

proc envFloatValue(env: Environment; name: string; default: float): float =
  let raw = env.stripped(name)
  if raw.len == 0:
    return default
  try:
    result = parseFloat(raw)
  except ValueError:
    result = default

proc initDaemonRuntime(home: string; env: Environment): DaemonRuntime =
  new(result)
  result.globalOutbox = newAsyncQueue[OutboundMessage]()
  result.sm.init()
  let stateStore = newRuntimeStateStore(
    home / "state",
    ledgerRetentionDays = envFloatValue(env, "DONKEY_LEDGER_RETENTION_DAYS",
                                        LedgerRetentionDaysDefault),
    ledgerCompactIntervalSec = envFloatValue(env, "DONKEY_LEDGER_COMPACT_INTERVAL_SEC",
                                             LedgerCompactIntervalSecDefault),
  )
  result.stateStore = stateStore
  result.sm.setRegistryStore(stateStore.sessionRegistry())
  result.ledger = stateStore.deliveryLedger()
  result.presentationState = initPresentationState()
  result.routeHealth = newRouteHealth(
    routeHealthFileStore(home / "state" / "route_health.json"),
    sampleTtlSec = envSeconds(env, "DONKEY_ROUTE_HEALTH_TTL_SEC",
                              DefaultRecentRouteSampleTtlSec),
    cooldownSec = envSeconds(env, "DONKEY_PROVIDER_COOLDOWN_SEC",
                             DefaultProviderCooldownSec))
  result.routeHealth.load()
  result.daemonStartMs = nowMs()

proc initDaemonContext(cfg: DonkeyConfig;
                       env: DaemonEnv;
                       log: Logger): DaemonContext =
  new(result)
  result.env = env
  result.adapters = initDaemonAdapters(cfg, env)
  result.services = initDaemonServices(cfg, env, log)
  result.runtime = initDaemonRuntime(cfg.home, cfg.env)

proc loadDaemonBootstrap(cfg: DonkeyConfig;
                         log: Logger): DaemonBootstrap =
  let env = loadDaemonEnv(cfg, log)
  result.memory = env.memory
  result.ctx = initDaemonContext(cfg, env, log)

proc startOptionalDiscordGateway(dcAdapter: var DiscordAdapter;
                                 discordToken: string;
                                 discordGuildId: string;
                                 log: Logger) =
  if discordToken.len == 0:
    log.info("DISCORD_BOT_TOKEN not set — Discord disabled")
    return

  log.info("Discord gateway starting (token len=" & $discordToken.len & ")")
  dcAdapter.startGateway(log)
  let appId = dcAdapter.getAppId().valueOr:
    log.warn("Discord getAppId failed: " & error); ""
  if appId.len > 0:
    log.info("Discord appId: " & appId)
    ## Register globally (DM support via integration_types=[0,1] + contexts=[0,1,2])
    dcAdapter.registerSlashCommands(appId, guildId = "").isOkOr:
      log.warn("Discord slash cmd reg (global) failed: " & error)
    ## Also register guild commands when DISCORD_GUILD_ID is set — takes effect immediately
    if discordGuildId.len > 0:
      dcAdapter.registerSlashCommands(appId, guildId = discordGuildId).isOkOr:
        log.warn("Discord slash cmd reg (guild) failed: " & error)
      log.info("Discord slash commands registered (global + guild " & discordGuildId & ")")
    else:
      log.info("Discord slash commands registered (global)")
  else:
    log.warn("Discord slash commands NOT registered — appId unavailable")
  log.info("Discord gateway thread started")

proc startOptionalWeComGateway(wecomCorpId: string; log: Logger) =
  ## Inbound arrives through the shared webhook receiver (/webhook/wecom).
  if wecomCorpId.len == 0:
    log.info("WECOM_CORP_ID not set — WeCom disabled")
    return
  log.info("WeCom enabled; callbacks on the webhook receiver at " & WeComPath)

proc startOptionalFeishuGateway(fsAdapter: var FeishuAdapter;
                                feishuAppId: string;
                                log: Logger) =
  if feishuAppId.len == 0:
    log.info("FEISHU_APP_ID not set — Feishu disabled")
    return

  fsAdapter.startGateway()
  log.info("Feishu WebSocket gateway started")

proc startOptionalWeChatGateway(wechatAppId: string; log: Logger) =
  ## Inbound arrives through the shared webhook receiver (/webhook/wechat).
  if wechatAppId.len == 0:
    log.info("WECHAT_APP_ID not set — WeChat disabled")
    return
  log.info("WeChat enabled; callbacks on the webhook receiver at " & WeChatPath)

proc slackSocketHttp(): HttpRuntimePort {.nimcall, gcsafe.} =
  ## Built on the Socket Mode reader thread (see SlackHttpFactory).
  newStdHttpAdapter(timeout = 15, maxRetries = 2,
                    circuitBreaker = false).toRuntimePort()

proc startOptionalSlackGateway(slAdapter: var SlackAdapter;
                               slackBotToken: string;
                               slackAppToken: string;
                               slackSigningSecret: string;
                               slackHttp: SlackHttpFactory;
                               log: Logger) =
  if slackBotToken.len == 0:
    log.info("SLACK_BOT_TOKEN not set — Slack disabled")
    return

  slAdapter.openQueue()
  if slackAppToken.len > 0:
    startSlackSocketMode(slackAppToken, slackHttp, log).isOkOr:
      log.error("slack socket: " & error)
  elif slackSigningSecret.len == 0:
    log.warn("SLACK_SIGNING_SECRET/SLACK_APP_TOKEN not set — Slack inbound disabled")
  log.info("Slack gateway started")

proc startOptionalDingTalkGateway(dtAdapter: var DingTalkAdapter;
                                  dingTalkAppKey: string;
                                  log: Logger) =
  if dingTalkAppKey.len == 0:
    log.info("DINGTALK_APP_KEY not set — DingTalk disabled")
    return

  dtAdapter.openQueue()
  log.info("DingTalk gateway started")

proc startOptionalMatrixGateway(mxAdapter: var MatrixAdapter;
                                configured: bool;
                                log: Logger) =
  if not configured:
    log.info("MATRIX_HOMESERVER/MATRIX_BOT_USER_ID/MATRIX_ACCESS_TOKEN not set — Matrix disabled")
    return

  mxAdapter.startGateway()
  log.info("Matrix gateway started")

proc startOptionalWhatsAppGateway(waAdapter: var WhatsAppAdapter;
                                  accessToken: string;
                                  phoneNumberId: string;
                                  log: Logger) =
  if accessToken.len == 0 or phoneNumberId.len == 0:
    log.info("WHATSAPP_ACCESS_TOKEN/WHATSAPP_PHONE_NUMBER_ID not set — WhatsApp disabled")
    return

  waAdapter.openQueue()
  log.info("WhatsApp webhook queue started")

proc startOptionalWebhookReceiver(env: DaemonEnv; qqOneBot: bool; log: Logger) =
  ## Mounts only the routes whose channel is configured AND has a secret.
  ## WeCom, WeChat and QQ OneBot have no listener of their own: their
  ## callbacks come here too.
  for retired in env.retiredWebhookPorts:
    log.warn(retired & " is no longer used: WeCom, WeChat and QQ OneBot " &
             "callbacks go to the webhook receiver (DONKEY_WEBHOOK_PORT) at " &
             WeComPath & ", " & WeChatPath & " and " & QQOneBotPath &
             "; re-register the callback URL")
  let callbackChannels = env.wecomCorpId.len > 0 or env.wechatAppId.len > 0 or qqOneBot
  if env.webhookPort <= 0:
    if callbackChannels:
      log.error("DONKEY_WEBHOOK_PORT not set — WeCom, WeChat and QQ OneBot " &
                "receive nothing without the webhook receiver")
    else:
      log.info("DONKEY_WEBHOOK_PORT not set — webhook receiver disabled")
    return
  if (env.webhookTlsCert.len > 0) != (env.webhookTlsKey.len > 0):
    log.error("DONKEY_WEBHOOK_TLS_CERT and DONKEY_WEBHOOK_TLS_KEY must be set together — webhook receiver disabled")
    return

  ## Unsigned OneBot only on a loopback receiver: anyone who reaches it could
  ## post as any QQ user.
  let qqMount = oneBotListenerCheck(env.webhookHost, env.qqOneBotSecret)
  if qqOneBot and qqMount.isErr:
    log.error("QQ OneBot route not mounted: " & qqMount.error)
  let cfg = WebhookConfig(
    ## Slack events are drained by slack_runtime; only accept them when the
    ## bot token and signature secret are configured.
    slackSigningSecret:
      if env.slackBotToken.len > 0: env.slackSigningSecret else: "",
    feishuVerificationToken:
      if env.feishuAppId.len > 0: env.feishuVerificationToken else: "",
    feishuEncryptKey:
      if env.feishuAppId.len > 0: env.feishuEncryptKey else: "",
    dingtalkAppSecret:
      if env.dingTalkAppKey.len > 0: env.dingTalkAppSecret else: "",
    lineChannelSecret:
      if env.lineChannelAccessToken.len > 0: env.lineChannelSecret else: "",
    lineChannelAccessToken: env.lineChannelAccessToken,
    lineAllowedGroups: env.lineAllowedGroups,
    lineAllowedUsers: env.lineAllowedUsers,
    matrixToken:
      if env.matrixConfigured: env.matrixWebhookToken else: "",
    whatsappVerifyToken:
      if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
        env.whatsappVerifyToken
      else: "",
    whatsappAppSecret:
      if env.whatsappVerifyToken.len > 0: env.whatsappAppSecret else: "",
    wecomToken:
      if env.wecomCorpId.len > 0: env.wecomCallbackToken else: "",
    wechatToken:
      if env.wechatAppId.len > 0: env.wechatCallbackToken else: "",
    qqOneBotEnabled: qqOneBot and qqMount.isOk,
    qqOneBotSecret: env.qqOneBotSecret,
    tlsCertFile: env.webhookTlsCert,
    tlsKeyFile: env.webhookTlsKey,
  )
  startWebhookReceiver(cfg, env.webhookPort, env.webhookHost, log).isOkOr:
    log.error("webhook receiver: " & error)
    return
  let scheme = if env.webhookTlsCert.len > 0: "https" else: "http"
  log.info("webhook receiver started on " & scheme & "://" &
           env.webhookHost & ":" & $env.webhookPort)

proc startOptionalQQGateway(qqAdapter: var QQChannelAdapter;
                             env: DaemonEnv;
                             log: Logger) =
  if not qqAdapter.enabled():
    log.info("QQ not configured — QQ disabled")
    return
  case qqAdapter.kind
  of qbkOneBot:
    log.info("QQ OneBot enabled; events on the webhook receiver at " & QQOneBotPath)
  of qbkOfficial:
    log.info("QQ official API client enabled")
    qqAdapter.startGateway()
    log.info("QQ official gateway started")
  of qbkNone:
    discard

proc buildGlobalSearchFn(memory: MdFileAdapter): SearchFn {.gcsafe.} =
  ## The memory agent's recall. The question's embedding is an HTTP call
  ## that blocks until its deadline, so it runs on a worker
  ## (app/blocking_executor); the SQLite search then runs here with the
  ## vector. Without an embedding key, or when the call fails, recall ranks
  ## by literal terms, as it already did when embedding was unavailable.
  when defined(withPostgres) or defined(withSqlite):
    let vectorSearch = buildGlobalMagmaVectorSearchFn(memory)
    if vectorSearch == nil:
      return nil
    let key = memory.magmaEnv.get("OPENROUTER_API_KEY").strip
    result = proc(userId: UserId; query: string; limit: int;
                  policy: Option[QueryPolicy]): Future[seq[MemoryHit]] {.async.} =
      var embedding: seq[float32]
      if key.len > 0 and query.strip.len > 0:
        try:
          let raw = await runOffLoop(openRouterEmbedJob, $(%*{"key": key, "text": query}))
          if raw.isOk:
            embedding = decodeEmbedding(raw.get).get(@[])
        except CatchableError:
          discard
      return vectorSearch(userId, query, limit, embedding, policy)
  else:
    discard

proc apiChatNowMs(): int64 {.gcsafe, raises: [].} =
  int64(epochTime() * 1000)

proc apiChatNap(ms: int) {.gcsafe, raises: [].} =
  ## The gateway runs on the daemon loop and its turns wait with `sleepAsync`
  ## (`poll(stepMs = 0)`), so the bridge never naps here. A blocking poll on
  ## this loop would stall every connection: nested `waitFor` is not an
  ## option, so this only bounds such a misuse.
  os.sleep(ms)

# Forward declaration for handleGatewayFallback (defined later, used in setupIpcServer)
proc handleGatewayFallback(ctx: DaemonContext; cfg: DonkeyConfig;
                          memory: MdFileAdapter; msg: InboundMessage;
                          log: Logger) {.gcsafe.}

# Forward declaration for buildDaemonSessionServices (defined later, used in setupIpcServer)
func buildDaemonSessionServices(ctx: DaemonContext; cfg: DonkeyConfig;
                                memory: MdFileAdapter;
                                log: Logger): SessionIngressServices

proc userSchedulePort(cfg: DonkeyConfig): SchedulePort =
  ## The store `manage_schedules` writes to; none when the scheduler is off,
  ## so the tool does not accept jobs that would never run.
  let lookup: EnvLookup = proc(name: string): string {.
      gcsafe, raises: [], noSideEffect.} = cfg.env.get(name)
  if not parseSchedulerConfig(lookup).enabled:
    return SchedulePort()
  newScheduleStoreRef(cfg.home / "state").toSchedulePort()

proc setupIpcServer(cfg: DonkeyConfig;
                    runtime: DaemonRuntime;
                    toolsCount: int;
                    daemonStartMs: int64;
                    telegramToken: string;
                    discordToken: string;
                    wecomCorpId: string;
                    wechatAppId: string;
                    feishuAppId: string;
                    slackBotToken: string;
                    qqEnabled: bool;
                    log: Logger;
                    gatewayInboundCtx: DaemonContext;
                    gatewayInboundMemory: MdFileAdapter;
                    gatewayInboundLog: Logger) =
  let sockPath = cfg.home / SockFileName
  let channels = ActiveChannels(
    telegram: telegramToken.len > 0, discord: discordToken.len > 0,
    wecom: wecomCorpId.len > 0, wechat: wechatAppId.len > 0,
    feishu: feishuAppId.len > 0, slack: slackBotToken.len > 0, qq: qqEnabled)
  let ipcStatusFn: StatusProvider = proc(): DaemonStatus {.gcsafe, raises: [].} =
    ## Reads the live session table (runtime.sm): the `sm` argument is a copy
    ## taken at startup, and showed the startup sessions forever.
    var memoryStats: MemoryStats
    var memoryBackend = "md"
    when defined(withPostgres) or defined(withSqlite):
      if gatewayInboundMemory.hasMagmaBackend:
        memoryBackend = "md+" & gatewayInboundMemory.magmaBackendName
        try:
          memoryStats = loadMagmaMemoryStats(gatewayInboundMemory)
        except CatchableError:
          discard
    daemonStatus(runtime.sm, DaemonStatusInputs(
      channels: channels, health: runtime.routeHealth, toolsCount: toolsCount,
      uptimeSec: (nowMs() - daemonStartMs) div 1000,
      providers: availableProviderNames(detectProviderAvailability()),
      memoryBackend: memoryBackend, memoryStats: memoryStats))
  let ipcLogFn: LogProvider = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].} =
    for e in ringSnapshot(n):
      result.add(IpcLogEntry(ts: e.ts, level: e.level, subsys: e.sub, msg: e.msg))
  let gwInboundFn: GatewayInboundFn =
    proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].} =
      try:
        handleGatewayFallback(gatewayInboundCtx, cfg, gatewayInboundMemory, msg,
                              gatewayInboundLog)
      except CatchableError as e:
        raise e
      except Exception as e:  ## effect boundary: callee raises are unannotated
        raise newException(CatchableError, "gateway inbound: " & e.msg, e)
  let gatewayAccess = accessPortOf(gatewayInboundMemory)
  let gwAuthorizeFn: AuthorizeFn =
    proc(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
      authorizeUser(userId, gatewayAccess, cfg.dmPolicy)
  try:
    startIpcServer(newFsAdapter(), sockPath, ipcStatusFn, ipcLogFn)
    log.info("IPC socket: " & sockPath)
  except CatchableError as e:
    log.warn("IPC socket disabled: " & e.msg)
  let httpPort = resolveGatewayPort(cfg.env.get("DONKEY_HTTP_PORT"))
  let gwStatusFn: GatewayStatusFn = proc(): DaemonStatus {.gcsafe.} =
    ipcStatusFn()
  let gwLogFn: GatewayLogFn = proc(n: int): seq[IpcLogEntry] {.gcsafe.} =
    ipcLogFn(n)
  let gwEventFn: GatewayEventFn = proc(n: int): seq[AgentEvent] {.gcsafe.} =
    agentEventSnapshot(n)
  let gwSessionsFn: GatewaySessionsFn = proc(): seq[SessionDetail] {.gcsafe.} =
    ## The gateway runs on the daemon loop: the live table is read directly.
    runtime.sm.listSessionDetails()
  let gwProvidersFn: GatewayProvidersFn = proc(): string {.gcsafe.} =
    buildProvidersJson(
      detectProviderAvailability(),
      runtime.routeHealth.cooldowns(),
      aggregateProviderFeedback(runtime.routeHealth.feedback()))
  let enqueueSessionTask: SessionTaskEnqueue =
    proc(msg: InboundMessage; kind: TaskKind; payload: string)
        {.gcsafe, raises: [CatchableError].} =
      try:
        ensureSessionTask(
          runtime.sm, msg,
          buildDaemonSessionServices(gatewayInboundCtx, cfg, gatewayInboundMemory,
                                     gatewayInboundLog),
          runtime.msgSeq, kind, payload)
      except CatchableError as e:
        raise e
      except Exception as e:  ## effect boundary: callee raises are unannotated
        raise newException(CatchableError, "gateway session task: " & e.msg, e)
  let gwSessionActionFn: GatewaySessionActionFn =
    proc(rawUserId: string; taskKind: TaskKind;
         payload: string): GatewaySessionActionOutcome
        {.gcsafe, raises: [CatchableError].} =
      runSessionAction(runtime.sm, rawUserId, taskKind, payload,
                       gwAuthorizeFn, enqueueSessionTask)
  let httpBind = block:
    let raw = cfg.env.get("DONKEY_HTTP_BIND").strip()
    if raw.len > 0: raw else: "127.0.0.1"
  let httpToken = cfg.env.get("DONKEY_HTTP_TOKEN").strip()
  let httpAllowInsecure = cfg.env.get("DONKEY_HTTP_ALLOW_INSECURE").strip() == "1"
  if httpPort > 0:
    if not gatewayBindIsAllowed(httpBind, httpToken, httpAllowInsecure):
      log.error("HTTP gateway disabled: non-loopback bind (" & httpBind &
                ") requires DONKEY_HTTP_TOKEN and DONKEY_HTTP_ALLOW_INSECURE=1")
    else:
      let gwChatBridge = runtime.apiChatBridge
      let gatewayStart = startHttpGateway(httpPort, gwStatusFn, gwLogFn, gwEventFn, gwInboundFn,
                                          bindAddr = httpBind, authToken = httpToken,
                                          agentDispatchFn = gwInboundFn,
                                          sessionsFn = gwSessionsFn,
                                          providersFn = gwProvidersFn,
                                          sessionActionFn = gwSessionActionFn,
                                          authorizeFn = gwAuthorizeFn,
                                          chatBridge = gwChatBridge,
                                          modelName = cfg.defaultModel,
                                          agentTimeoutMs = resolveAgentTimeoutMs(
                                            cfg.env.get("DONKEY_HTTP_AGENT_TIMEOUT_SEC")))
      if gatewayStart.isErr:
        log.error("HTTP gateway disabled: " & gatewayStart.error)
      else:
        log.info("HTTP gateway: http://" & httpBind & ":" & $httpPort &
                 (if httpToken.len > 0: " (bearer auth enabled)" else: ""))
        if httpToken.len > 0 and httpBind notin ["127.0.0.1", "localhost", "::1", "[::1]"]:
          log.warn("HTTP gateway is not loopback and has no TLS; put it behind a " &
                   "TLS-terminating reverse proxy — the Bearer token travels in cleartext")
  else:
    log.info("HTTP gateway: disabled")

func buildDaemonSessionServices(ctx: DaemonContext;
                                cfg: DonkeyConfig;
                                memory: MdFileAdapter;
                                log: Logger): SessionIngressServices =
  buildSessionIngressServices(
    memory.toRuntimePort(),
    cfg,
    ctx.services.globalCompleteFn,
    ctx.services.globalStreamFactory,
    ctx.services.toolClients,
    ctx.services.tools,
    ctx.runtime.globalOutbox,
    log,
    cfg.sandboxMode,
    cfg.sandboxRuntimeCmd,
    cfg.sandboxImage,
    nil,
    ctx.services.globalSearchFn,
    accessPortOf(memory),
    cfg.dmPolicy,
    newStdHttpAdapter(allowlist = cfg.webAllowlist,
                      proxy = cfg.env.get("DONKEY_WEB_PROXY").strip()).toRuntimePort(),
    buildProviderBundle,
    buildDenoSkillRuntime,
    buildSkillRuntimePolicyResolver(cfg),
    routeRecordHook = proc(selection: ProviderSelection) {.gcsafe, raises: [].} =
      ctx.runtime.routeHealth.recordChoice(selection),
    routeResultHook = proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe, raises: [].} =
      ctx.runtime.routeHealth.recordResult(selection, elapsedMs, ok),
    routeFeedbackHook = proc(): seq[RouteFeedback] {.gcsafe, raises: [].} =
      ctx.runtime.routeHealth.feedback(),
    routeCostHook = proc(): seq[RouteCostHint] {.gcsafe, raises: [].} =
      loadRouteCostHints(routeCostProviderIds()),
    routeProviderCooldownHook = proc(): seq[ProviderCooldown] {.gcsafe, raises: [].} =
      ctx.runtime.routeHealth.cooldowns(),
    subagentWorkspace = subagentWorkspacePort(),
    fs = newFsAdapter(),
    reminders = newReminderStore(memory.paddocksDir).toReminderPort(),
    schedules = userSchedulePort(cfg),
    backtrail = daemonBacktrail(cfg),
    process = newProcessAdapter(),
    attachments = newAttachmentStore(),
  )

proc handleDaemonSessionFallback(runtime:  var DaemonRuntime;
                                  msg:      InboundMessage;
                                  services: SessionIngressServices) =
  handleSessionFallback(runtime.sm, runtime.msgSeq, msg, services)

proc handleTelegramFallback(runtime:      var DaemonRuntime;
                            msg:          InboundMessage;
                            services:     SessionIngressServices) =
  handleDaemonSessionFallback(runtime, msg, services)

proc processInboundMediaDownload(msg: var InboundMessage;
                                 channelPort: OutboundChannelPort;
                                 paddockDir: string;
                                 log: Logger) =
  ## Downloads an inbound attachment and stores it inside the paddock.
  ## The channel file_id is never forwarded to the provider.
  if msg.mediaUrl.len == 0:
    return

  let fileId = msg.mediaUrl
  let downloadResult = channelPort.downloadFile(fileId)
  if downloadResult.isOk:
    let saveResult = applyInboundAttachment(
      msg, downloadResult.value, paddockDir, newAttachmentStore(),
      msg.mediaFileName, msg.mediaMimeType)
    if saveResult.isOk:
      log.info($msg.channel & ": attached " & saveResult.value.relPath &
               " (" & $saveResult.value.size & " bytes)")
    else:
      log.warn($msg.channel & ": failed to save attachment: " & saveResult.error)
      if msg.text.len > 0:
        msg.text.add("\n\n")
      msg.text.add("[Falha ao salvar o anexo: " & saveResult.error & "]")
      msg.mediaUrl = ""
  else:
    log.debug($msg.channel & ": downloadFile not available for " & fileId)
    ## Some channels already provide a public URL; leave it for the provider
    ## instead of replacing a potentially valid image with an error marker.
    let looksLikeUrl = msg.mediaUrl.startsWith("http://") or
                       msg.mediaUrl.startsWith("https://")
    if not looksLikeUrl:
      if msg.text.len > 0:
        msg.text.add("\n\n")
      msg.text.add("[Falha ao baixar o anexo: " & downloadResult.error & "]")
      msg.mediaUrl = ""

func outboundPortForChannel(ports: OutboundChannelPorts;
                            channel: ChannelKind): OutboundChannelPort =
  case channel
  of ckTelegram: ports.telegram
  of ckDiscord: ports.discord
  of ckWeCom: ports.wecom
  of ckWeChat: ports.wechat
  of ckQQ: ports.qq
  of ckFeishu: ports.feishu
  of ckSlack: ports.slack
  of ckWhatsApp: ports.whatsapp
  of ckSignal: ports.signal
  of ckDingTalk: ports.dingtalk
  of ckMatrix: ports.matrix
  of ckEmail: ports.email
  of ckCli: ports.cli
  of ckLine: ports.line

proc makeCompleteBuilder(): proc(preferencesMd: string): CompleteFn {.gcsafe.} =
  result = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)

proc drainTelegramEvents(runtime:      var DaemonRuntime;
                         tgAdapter:    var TelegramAdapter;
                         outboundPorts: OutboundChannelPorts;
                         services:     SessionIngressServices;
                         memory:       MdFileAdapter;
                         modelCatalogLoader: ModelCatalogLoader;
                         log:          Logger): bool =
  ## getUpdates runs on the blocking executor; this drain starts it and, on
  ## a later tick, takes its result. The offset and identities stay here.
  if runtime.tgPoll == nil:
    runtime.tgPoll = runOffLoop(fetchTelegramUpdates, tgAdapter.pollRequest())
    return false
  let finished = runtime.tgPoll.takeFinished()
  if finished.isNone:
    return false
  let fetched = finished.get
  var tgMsgs = tgAdapter.acceptTelegramUpdates(fetched).valueOr:
    log.error("telegram receive: " & error)
    return false
  ## The offset moved: the next long poll can start now.
  runtime.tgPoll = runOffLoop(fetchTelegramUpdates, tgAdapter.pollRequest())
  let completeBuilder = makeCompleteBuilder()
  let runtimePtr = addr runtime

  for msg in tgMsgs.mitems:
    let auth = authorizeResolvedInbound(
      runtime.sm, tgAdapter.resolver.identityGate(), ckTelegram,
      msg.userId, msg.text)
    if not auth.allowed:
      log.warn("telegram: unauthorized message from " & $msg.userId)
      continue

    let stagedReaction = shouldStageReaction(msg)
    if stagedReaction:
      tgAdapter.sendTyping(msg.userId).isOkOr:
        log.warn("tg sendTyping (staged) failed for user=" & $msg.userId & " reason=" & error)
      stageReaction(runtime.presentationState, outboundPorts, msg)
    
    # Download media if present
    processInboundMediaDownload(msg, outboundPorts.telegram,
                                memory.paddockDir(msg.userId), log)
    
    if telegram_runtime.handleTelegramMessage(
      msg, runtime.sm, tgAdapter, runtime.presentationState, memory, completeBuilder,
      modelCatalogLoader,
      services.toolClients.len, services.tools.len + nativeSessionTools().len, runtime.msgSeq, runtime.daemonStartMs, log,
      proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} =
        ensureSessionTask(runtimePtr[].sm, msg, services, runtimePtr[].msgSeq, taskKind, payload),
      skillRegistry(services.cfg.env)):
      if stagedReaction:
        completeReaction(runtime.presentationState, outboundPorts, msg.channel,
                         msg.userId, msg.channelId, statusMessageId(msg), false)
    else:
      handleTelegramFallback(runtime, msg, services)
  true

proc publishDueReminders(runtime: var DaemonRuntime;
                         memory:  MdFileAdapter;
                         log:     Logger) =
  ## The one place reminders are delivered: every 30 s on the daemon tick.
  if nowMs() - runtime.lastReminderCheckMs < 30_000:
    return
  runtime.lastReminderCheckMs = nowMs()
  let outbox = runtime.globalOutbox
  let reminderLog = log
  let fired = deliverDueReminders(
    newReminderStore(memory.paddocksDir).toReminderPort(), getTime().toUnix(),
    proc(reminder: Reminder): Result[void, string] {.gcsafe, raises: [].} =
      try:
        outbox.putNoWait(reminderMessage(reminder))
        reminderLog.info("reminder fired " & $reminder.userId)
        ok()
      except CatchableError as e:
        err(e.msg),
    log)
  discard fired

proc drainGlobalOutbox(runtime:  var DaemonRuntime;
                       adapters: var DaemonAdapters;
                       log:      Logger) =
  let outboundPorts = buildRuntimeOutboundPorts(adapters)
  while runtime.globalOutbox.len > 0:
    let outMsg = runtime.globalOutbox.getNoWait()
    if isApiChatReply(outMsg):
      ## API replies belong to a waiting HTTP turn, never to a channel port.
      ## A reply without a turn token (a scheduled firing for an `api:` user,
      ## for example) must not close an unrelated HTTP request.
      if outMsg.bridgeToken == 0:
        log.warn("dropping an API reply without a turn token for " &
                 $outMsg.userId)
        continue
      if runtime.apiChatBridge != nil:
        discard runtime.apiChatBridge.deliver(outMsg, outMsg.bridgeToken)
      continue
    completeReactionFor(runtime.presentationState, outboundPorts, outMsg)
    routeOutbound(outMsg, outboundPorts, log, runtime.presentationState, runtime.ledger)
    settleDiscordCursorOnReply(adapters.dc, runtime.sm, outMsg)

proc startDaemonIngress(ctx: DaemonContext;
                        log: Logger) =
  startOptionalDiscordGateway(ctx.adapters.dc, ctx.env.discordToken, ctx.env.discordGuildId, log)
  startOptionalWeComGateway(ctx.env.wecomCorpId, log)
  startOptionalWeChatGateway(ctx.env.wechatAppId, log)
  startOptionalFeishuGateway(ctx.adapters.fs, ctx.env.feishuAppId, log)
  startOptionalSlackGateway(ctx.adapters.sl, ctx.env.slackBotToken,
                            ctx.env.slackAppToken, ctx.env.slackSigningSecret,
                            slackSocketHttp, log)
  startOptionalDingTalkGateway(ctx.adapters.dt, ctx.env.dingTalkAppKey, log)
  startOptionalMatrixGateway(ctx.adapters.mx, ctx.env.matrixConfigured, log)
  startOptionalWhatsAppGateway(ctx.adapters.wa, ctx.env.whatsappAccessToken,
                               ctx.env.whatsappPhoneNumberId, log)
  ## The LINE route can enqueue as soon as the receiver binds; the queue must
  ## be open first (an unopened Channel cannot be sent to from a worker).
  if ctx.env.lineChannelAccessToken.len > 0:
    ctx.adapters.ln.openQueue()
    log.info("LINE webhook queue started")
  startOptionalWebhookReceiver(ctx.env,
    ctx.adapters.qq.enabled() and ctx.adapters.qq.kind == qbkOneBot, log)
  startOptionalQQGateway(ctx.adapters.qq, ctx.env, log)
  if ctx.env.telegramToken.len > 0:
    log.info("Telegram bot starting (token len=" & $ctx.env.telegramToken.len & ")")
    ctx.adapters.tg.registerBotCommands().isOkOr:
      log.warn("Telegram registerBotCommands failed: " & error)
    log.info("Telegram bot started, polling active")

proc setupDaemonRuntime(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  ## The Discord DM cursor is saved by the adapter after delivery; the memory
  ## that stores it lives here.
  ctx.adapters.dc.cursor.save = proc(userId: UserId; msgId: string) {.gcsafe.} =
    discard memory.saveChannelPreference(userId, "discord_last_msg_id", msgId)
  setupIpcServer(cfg, ctx.runtime, ctx.services.tools.len + nativeSessionTools().len, ctx.runtime.daemonStartMs,
                 ctx.env.telegramToken, ctx.env.discordToken, ctx.env.wecomCorpId,
                 ctx.env.wechatAppId, ctx.env.feishuAppId, ctx.env.slackBotToken,
                 ctx.adapters.qq.enabled(), log,
                 ctx, memory, log)

proc activateDaemonBootstrap(ctx: DaemonContext;
                             cfg: DonkeyConfig;
                             memory: MdFileAdapter;
                             log: Logger) =
  startDaemonIngress(ctx, log)
  setupDaemonRuntime(ctx, cfg, memory, log)

proc handleGatewayFallback(ctx: DaemonContext;
                           cfg: DonkeyConfig;
                           memory: MdFileAdapter;
                           msg: InboundMessage;
                           log: Logger) {.gcsafe.} =
  let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
  let approvalReply = tryHandleApprovalInput(msg.userId, msg.text)
  if approvalReply.isSome:
    let port = outboundPortForChannel(outboundPorts, msg.channel)
    if port.send != nil:
      discard port.send(OutboundMessage(
        userId: msg.userId, channel: msg.channel, text: approvalReply.get))
    return
  var resolvedMsg = msg
  processInboundMediaDownload(
    resolvedMsg,
    outboundPortForChannel(outboundPorts, resolvedMsg.channel),
    memory.paddockDir(resolvedMsg.userId),
    log,
  )
  handleDaemonSessionFallback(
    ctx.runtime,
    resolvedMsg,
    buildDaemonSessionServices(ctx, cfg, memory, log),
  )

const
  EmailPollIntervalMs*  = 15_000
  SignalPollIntervalMs* = 2_000

proc buildDaemonGatewayDrainer(ctx: DaemonContext;
                               cfg: DonkeyConfig;
                               memory: MdFileAdapter;
                               log: Logger): GatewayDrainer =
  let completeBuilder = makeCompleteBuilder()
  let modelCatalogLoader = ctx.services.modelCatalogLoader
  let toolsCount = ctx.services.tools.len + nativeSessionTools().len
  let toolClientsCount = ctx.services.toolClients.len
  let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
  let fallback = proc(msg: InboundMessage) {.gcsafe.} =
    handleGatewayFallback(ctx, cfg, memory, msg, log)
  let cmdEnv = newChannelRuntimeEnv(
    memory, completeBuilder, modelCatalogLoader, toolsCount,
    toolClientsCount, ctx.runtime.daemonStartMs, skillRegistry(cfg.env))

  initGatewayDrainer(
    drainDiscord = proc(): bool =
      drainDiscordGateway(ctx.env.discordToken.len > 0, proc(): bool =
        discord_runtime.drainDiscordEvents(
          ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState, cmdEnv,
          ctx.runtime.msgSeq, log,
          proc(msg: InboundMessage) =
            stageReaction(ctx.runtime.presentationState, outboundPorts, msg),
          proc(msg: InboundMessage) =
            completeReaction(ctx.runtime.presentationState, outboundPorts, msg.channel, msg.userId,
              msg.channelId, statusMessageId(msg), false),
          fallback)
        true
      ),
    drainWeCom = proc(): bool =
      drainWeComGateway(ctx.env.wecomCorpId.len > 0, proc(): bool =
        wecom_runtime.drainWeComEvents(
          ctx.adapters.wc, ctx.env.wecomCorpId, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainWeChat = proc(): bool =
      drainWeChatGateway(ctx.env.wechatAppId.len > 0, proc(): bool =
        wechat_runtime.drainWeChatEvents(
          ctx.adapters.wch, ctx.env.wechatAppId, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainQQ = proc(): bool =
      drainQQGateway(ctx.adapters.qq.enabled(), proc(): bool =
        qq_runtime.drainQQEvents(
          ctx.adapters.qq, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainFeishu = proc(): bool =
      drainFeishuGateway(ctx.env.feishuAppId.len > 0, proc(): bool =
        feishu_runtime.drainFeishuEvents(
          ctx.adapters.fs, ctx.env.feishuAppId, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainSlack = proc(): bool =
      drainSlackGateway(ctx.env.slackBotToken.len > 0 and
                        (ctx.env.slackSigningSecret.len > 0 or
                         ctx.env.slackAppToken.len > 0), proc(): bool =
        slack_runtime.drainSlackEvents(
          ctx.adapters.sl, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainDingTalk = proc(): bool =
      let count = drainDingTalkGateway(
        ctx.env.dingTalkAppKey.len > 0,
        proc(): (bool, InboundMessage) =
          var (hasEvent, event) = ctx.adapters.dt.tryRecvEvent()
          while hasEvent:
            if event.content.strip.len > 0 or event.downloadCode.len > 0:
              ## The generic gateway fallback does not dispatch `/continue`;
              ## do not admit link commands here until a DingTalk command
              ## runtime exists.
              let auth = authorizeInbound(
                ctx.runtime.sm, ctx.adapters.dt.resolver.identityGate(),
                ckDingTalk, event.rawId, event.content, ilsNone)
              if not auth.allowed:
                log.warn("dingtalk: unauthorized message from " &
                         (if auth.identified: $auth.userId else: "unidentified sender"))
                (hasEvent, event) = ctx.adapters.dt.tryRecvEvent()
                continue
              return (true, InboundMessage(
                userId: auth.userId,
                channel: ckDingTalk,
                channelId: event.messageId,
                messageId: event.messageId,
                text: event.content,
                mediaUrl: event.downloadCode,
              ))
            (hasEvent, event) = ctx.adapters.dt.tryRecvEvent()
          (false, InboundMessage()),
        fallback,
        log
      )
      count > 0,
    drainLine = proc(): bool =
      if ctx.env.lineChannelAccessToken.len == 0:
        return false
      let linePolicy = LinePolicy(
        allowedGroups: ctx.env.lineAllowedGroups,
        allowedUsers:  ctx.env.lineAllowedUsers)
      ## Hand the `/continue` confirmation to the outbox so this drain does not
      ## wait for the LINE POST. The outbox drainer runs later on the same
      ## daemon thread, so this removes the wait from the channel drain, not
      ## from the daemon (an outbound worker is future work).
      let enqueueLineReply = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
        try:
          ctx.runtime.globalOutbox.putNoWait(msg)
          ok()
        except AsyncQueueFullError:
          err("LINE: outbox full, /continue reply dropped")
      drainLineEvents(
        ctx.adapters.ln, ctx.runtime.sm, ctx.runtime.lineReplay,
        linePolicy, getTime().toUnix(), fallback, enqueueLineReply, log) > 0,
    drainMatrix = proc(): bool =
      let count = drainMatrixGateway(
        ctx.env.matrixConfigured,
        proc(): (bool, InboundMessage) =
          var (hasEvent, event) = ctx.adapters.mx.tryRecvEvent()
          while hasEvent:
            if event.content.strip.len > 0 or event.mediaUrl.len > 0:
              ## The generic gateway fallback does not dispatch `/continue`;
              ## do not admit link commands here until a Matrix command
              ## runtime exists.
              let auth = authorizeInbound(
                ctx.runtime.sm, ctx.adapters.mx.resolver.identityGate(),
                ckMatrix, event.roomId, event.content, ilsNone)
              if not auth.allowed:
                log.warn("matrix: unauthorized message from " &
                         (if auth.identified: $auth.userId else: "unidentified sender"))
                (hasEvent, event) = ctx.adapters.mx.tryRecvEvent()
                continue
              return (true, InboundMessage(
                userId: auth.userId,
                channel: ckMatrix,
                channelId: event.eventId,
                messageId: event.eventId,
                text: event.content,
                mediaUrl: event.mediaUrl,
              ))
            (hasEvent, event) = ctx.adapters.mx.tryRecvEvent()
          (false, InboundMessage()),
        fallback,
        log
      )
      count > 0,
    drainTelegram = proc(): bool =
      if ctx.env.telegramToken.len == 0:
        return true
      let services =
        buildDaemonSessionServices(ctx, cfg, memory, log) |>->
        withTypingFn(ctx.services.tgTypingFn)
      drainTelegramEvents(ctx.runtime, ctx.adapters.tg, outboundPorts, services, memory,
                          ctx.services.modelCatalogLoader, log),
    drainWhatsApp = proc(): bool =
      drainWhatsAppGateway(ctx.env.whatsappAccessToken.len > 0, proc(): bool =
        whatsapp_runtime.drainWhatsAppEvents(
          ctx.adapters.wa, ctx.env.whatsappPhoneNumberId, ctx.runtime.sm, cmdEnv,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainEmail = proc(): bool =
      if ctx.adapters.em.imapHost.len == 0:
        return false
      if ctx.runtime.emailPoll != nil:
        let finished = ctx.runtime.emailPoll.takeFinished()
        if finished.isNone:
          return false
        let polled = finished.get
        if polled.isErr:
          log.warn("email poll: " & polled.error)
          return false
        for msg in ctx.adapters.em.resolvePolled(polled.value):
          fallback(msg)
        return polled.value.len > 0
      let now = nowMs()
      if now - ctx.runtime.lastEmailPollMs < EmailPollIntervalMs:
        return false
      ctx.runtime.lastEmailPollMs = now
      ctx.runtime.emailPoll = runOffLoop(pollEmail, ctx.adapters.em.inbox)
      false,
    drainSignal = proc(): bool =
      if ctx.adapters.signal.account.len == 0:
        return false
      if ctx.runtime.signalPoll != nil:
        let finished = ctx.runtime.signalPoll.takeFinished()
        if finished.isNone:
          return false
        let polled = finished.get
        if polled.isErr:
          log.warn("signal poll: " & polled.error)
          return false
        for msg in ctx.adapters.signal.resolvePolled(polled.value):
          fallback(msg)
        return polled.value.len > 0
      let now = nowMs()
      if now - ctx.runtime.lastSignalPollMs < SignalPollIntervalMs:
        return false
      ctx.runtime.lastSignalPollMs = now
      ctx.runtime.signalPoll = runOffLoop(pollSignal, ctx.adapters.signal.sockPath)
      false,
  )

proc withOutboxDrain(ctx: DaemonContext;
                     log: Logger;
                     tick: DaemonTickResult): DaemonTickResult =
  result = tick
  drainGlobalOutbox(ctx.runtime, ctx.adapters, log)

proc withGatewayDrain(drainer: GatewayDrainer;
                      tick: DaemonTickResult): DaemonTickResult =
  result = tick
  drainGatewayEvents(drainer)
  result.ok = true  # Always ok, gateways drained

proc withReminderCheck(ctx: DaemonContext;
                       memory: MdFileAdapter;
                       log: Logger;
                       tick: DaemonTickResult): DaemonTickResult =
  result = tick
  if not result.ok:
    return
  publishDueReminders(ctx.runtime, memory, log)
  result.remindersChecked = true

proc runDaemonTick(ctx: DaemonContext;
                   drainer: GatewayDrainer;
                   memory: MdFileAdapter;
                   log: Logger): DaemonTickResult =
  setActiveSessions(ctx.runtime.sm.entries.len)
  result =
    DaemonTickResult(ok: true, remindersChecked: false) |>->
    withOutboxDrain(ctx, log) |>->
    withGatewayDrain(drainer) |>->
    withReminderCheck(ctx, memory, log)

proc runDaemonLoop(ctx: DaemonContext;
                   drainer: GatewayDrainer;
                   memory: MdFileAdapter;
                   log: Logger): DaemonLoopResult =
  if ctx.runtime.stateStore != nil:
    let compactError = ctx.runtime.stateStore.tryCompactError()
    if compactError.isSome:
      log.warn("ledger compaction: " & compactError.get())
  let tick = runDaemonTick(ctx, drainer, memory, log)
  DaemonLoopResult(
    sleepMs: if tick.ok: 100 else: 500,
  )

var gShutdownRequested {.volatile.}: bool

proc handleShutdownSignal(sig: cint) {.noconv.} =
  gShutdownRequested = true

proc startDaemon(cfg: DonkeyConfig; log: Logger) {.async: (raises: [Exception]).} =
  ## Async daemon: Telegram (pollTimeout=0) + Discord (gateway thread) + WeCom (webhook thread).
  ## Loop: drain globalOutbox → drain Discord → drain WeCom → poll Telegram → sleepAsync(100ms)
  if cfg.invalidDmPolicy.len > 0:
    log.error("invalid dm_policy: " & cfg.invalidDmPolicy &
              " (use open|pairing|allowlist)")
    quit(1)
  log.info("daemon starting — Telegram + Discord + WeCom")
  gShutdownRequested = false
  when defined(posix):
    posix.signal(posix.SIGTERM, handleShutdownSignal)
    posix.signal(posix.SIGINT, handleShutdownSignal)
  initMetrics(startedAtMs = epochMs(), version = AppVersion)
  startOptionalMetricsServer(cfg.env, log)

  ## One daemon per state directory. A lease left by a dead process is taken
  ## over; a live one stops this startup before any store is opened.
  var daemonLease = acquireDaemonLease(cfg.home / "state").valueOr:
    stderr.writeLine "Security Error: " & error
    quit(1)
  defer: releaseDaemonLease(daemonLease)

  let bootstrap = loadDaemonBootstrap(cfg, log)
  let memory = bootstrap.memory
  let ctx = bootstrap.ctx
  ## The API bridge must exist before the gateway accepts a turn and before
  ## the outbox drainer can route `api:` replies.
  ctx.runtime.apiChatBridge = newChatBridge(apiChatNowMs, apiChatNap)
  if ctx.runtime.stateStore != nil:
    let ledgerErr = ctx.runtime.stateStore.ledgerLastCompactError()
    if ledgerErr.len > 0:
      log.warn("ledger compaction at startup: " & ledgerErr)
    ## Deliveries left pending by the previous process can never finish.
    let reconciled = ctx.runtime.stateStore.reconcileInterruptedDeliveries()
    if reconciled.isErr:
      log.warn("delivery ledger reconciliation: " & reconciled.error)
    elif reconciled.get() > 0:
      log.warn("delivery ledger: " & $reconciled.get() &
               " interrupted deliveries marked failed")
  ## DM authorization is configured once, before any drainer/actor can consume
  ## an inbound message. Service builders stay side-effect free.
  let access = accessPortOf(memory)
  ctx.runtime.sm.configureDmPolicy(
    cfg.dmPolicy,
    proc(userId: UserId): bool {.gcsafe.} = access.dmAllowed(userId))
  ctx.runtime.sm.configureGroupGate(GroupGate(
    allowedChats: parseChatIdList(cfg.env.get(EnvTelegramAllowedGroups))))
  let pairingStore = newPairingStore(cfg.home / "state" / "pairings.json")
  ctx.runtime.sm.pairingRequest =
    proc(kind: ChannelKind; rawId: string): Result[void, string] {.gcsafe.} =
      let res = pairingStore.requestPairing(kind, rawId)
      if res.isErr:
        log.warn("pairing request rejected for " & $kind & " " & rawId &
                 ": " & res.error)
        return err(res.error)
      log.info("pairing request created for " & $kind & " " & rawId &
               " (approve with ctl pair list/approve)")
      ok()
  ctx.runtime.sm.setRegistryErrorHook(
    proc(error: string) {.gcsafe, raises: [].} =
      log.warn("session registry: " & error))
  let restoredSessions = ctx.runtime.sm.restoreSessions()
  if restoredSessions.isErr:
    log.warn("session registry restore: " & restoredSessions.error)
  elif restoredSessions.value > 0:
    log.info("restored " & $restoredSessions.value & " sessions from registry")
  activateDaemonBootstrap(ctx, cfg, memory, log)
  let sessionServices = buildDaemonSessionServices(ctx, cfg, memory, log)
  let drainer = buildDaemonGatewayDrainer(ctx, cfg, memory, log)

  ## Heartbeat: periodic maintenance (reminders go out on the daemon tick)
  var hbReg = newHeartbeatRegistry()
  if ctx.services.browserRuntime != nil:
    let browserRuntime = ctx.services.browserRuntime
    ## Independent of DONKEY_HEARTBEAT_CRON: idle browsers must be reaped
    ## within a bounded time even if the main heartbeat runs daily.
    startPeriodicTask(proc() {.gcsafe.} = browserRuntime.evictIdle(),
                      intervalSec = 60, name = "browser-idle")
  block:
    ## Off unless the operator sets a number of days.
    let days = retentionDays(cfg.env.get(AttachmentRetentionEnv))
    if days > 0:
      let paddocksDir = cfg.paddocks
      startPeriodicTask(proc() {.gcsafe.} =
        let removed = pruneAttachments(newFsAdapter(), paddocksDir,
                                       getTime().toUnix(), days,
                                       newLogger("attachments"))
        if removed > 0:
          newLogger("attachments").info("retention: removed " & $removed &
                                        " attachments older than " & $days & " days"),
        intervalSec = 3600, name = "attachment-retention")
      log.info("attachment retention: " & $days & " days")
  if ctx.runtime.stateStore != nil:
    let compactionSec = ctx.runtime.stateStore.ledgerCompactIntervalSec()
    if compactionSec > 0:
      ## Off the loop on the blocking executor, one at a time; failures
      ## reach the loop through `tryCompactError`.
      let runtime = ctx.runtime
      startPeriodicTask(proc() {.gcsafe.} =
        if runtime.ledgerCompaction == nil or runtime.ledgerCompaction.finished:
          runtime.ledgerCompaction = runOffLoop(compactLedgerJob,
            LedgerCompactionJob(store: addr runtime.stateStore, force: true))
        else:
          ## A compaction longer than the whole interval is stuck or the
          ## ledger is huge: say so instead of skipping in silence.
          newLogger("ledger").warn("ledger compaction still running after a " &
                                   "full interval; this tick is skipped"),
        intervalSec = max(1, compactionSec.int), name = "ledger-compaction")
  let heartbeatOutboxFn: HeartbeatOutboxFn = proc(userId, channel, taskPayload: string) {.gcsafe.} =
    let uid = UserId(userId)
    let ck =
      if channel.len > 0:
        parseEnum[ChannelKind](channel, ckTelegram)
      else:
        ctx.runtime.sm.latestChannel(uid).get(ckTelegram)
    ensureSessionTask(
      ctx.runtime.sm,
      InboundMessage(
        userId: uid,
        channelId: "",
        callbackId: "",
        text: "",
        mediaUrl: "",
        channel: ck,
      ),
      sessionServices,
      ctx.runtime.msgSeq,
      tkHeartbeat,
      taskPayload,
    )
  hbReg.registerTask("heartbeat", proc() {.gcsafe.} =
    deliverHeartbeats(newFsAdapter(), cfg.paddocks, heartbeatOutboxFn))
  let hbCronExpr = cfg.env.get("DONKEY_HEARTBEAT_CRON").strip()
  if hbCronExpr.len > 0:
    let hbCronStart = startHeartbeatCron(hbReg, hbCronExpr)
    if hbCronStart.isErr:
      log.error("heartbeat cron: " & hbCronStart.error)
      quit(1)
    log.info("heartbeat cron: " & hbCronExpr)
  else:
    let hbIntervalStr = cfg.env.get("DONKEY_HEARTBEAT_SEC")
    let hbInterval = if hbIntervalStr.len > 0:
      try: parseInt(hbIntervalStr) except ValueError: 60
    else: 60
    startHeartbeat(hbReg, intervalSec = hbInterval)
    log.info("heartbeat: every " & $hbInterval & "s")

  ## Scheduler (automação US-006): a dedicated periodic task, never the
  ## heartbeat registry — DONKEY_HEARTBEAT_CRON cannot silence
  ## DONKEY_SCHEDULES_TICK_SEC. Off by default. The store lives in the same
  ## state dir as the runtime store.
  var schedulerTask: SchedulerTask
  block:
    let envLookup: EnvLookup = proc(name: string): string {.
        gcsafe, raises: [], noSideEffect.} = cfg.env.get(name)
    let schedulesCfg = parseSchedulerConfig(envLookup)
    for warning in schedulesCfg.warnings:
      log.warn("scheduler config: " & warning)
    if not schedulesCfg.enabled:
      log.info("scheduler: disabled (DONKEY_SCHEDULES_ENABLED=0)")
    else:
      let scheduleStore = newScheduleStoreRef(cfg.home / "state")
      let loadSchedules: ScheduleSnapshotLoader =
        proc(): Result[seq[ScheduleSnapshot], string] {.
            gcsafe, raises: [].} =
          let records = scheduleStore.loadAllRecords()
          if records.isErr:
            return err(records.error)
          var snapshot: seq[ScheduleSnapshot]
          for record in records.get():
            snapshot.add(ScheduleSnapshot(
              spec: record.spec,
              loadWarning: record.loadWarning,
            ))
          ok(snapshot)
      schedulerTask = startSchedulerTask(
        scheduleStore.scheduleStorePort,
        loadSchedules,
        scheduleEnqueueFn(addr ctx.runtime.sm, sessionServices,
                          addr ctx.runtime.msgSeq),
        schedulesCfg,
        epochMs,
        log.child("scheduler"),
      )

  ## One-time startup: recover messages received while bot was offline.
  block:
    let completeBuilder = makeCompleteBuilder()
    let modelCatalogLoader = ctx.services.modelCatalogLoader
    let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
    discord_runtime.checkDiscordOfflineMessages(
      ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState,
      newChannelRuntimeEnv(memory, completeBuilder, modelCatalogLoader,
                           ctx.services.tools.len + nativeSessionTools().len,
                           ctx.services.toolClients.len,
                           ctx.runtime.daemonStartMs, skillRegistry(cfg.env)),
      ctx.runtime.msgSeq, log,
      proc(msg: InboundMessage) {.gcsafe.} =
        stageReaction(ctx.runtime.presentationState, outboundPorts, msg),
      proc(msg: InboundMessage) {.gcsafe.} =
        completeReaction(ctx.runtime.presentationState, outboundPorts, msg.channel, msg.userId,
          msg.channelId, statusMessageId(msg), false),
      proc(msg: InboundMessage) {.gcsafe.} =
        handleGatewayFallback(ctx, cfg, memory, msg, log))

  log.info("polling for messages…")
  try:
    while not gShutdownRequested:
      let loopResult = runDaemonLoop(ctx, drainer, memory, log)
      await sleepAsync(ctimer.milliseconds(loopResult.sleepMs.int64))
  finally:
    log.info("daemon shutdown: stopping background workers")
    stopSchedulerTask(schedulerTask)
    if ctx.runtime.ledgerCompaction != nil and not ctx.runtime.ledgerCompaction.finished:
      ## The job writes through a pointer to the store: let it finish.
      discard await ctx.runtime.ledgerCompaction
    stopSlackSocketMode()
    discord.stopGateway()
    stopQQOfficialGateway()
    stopWebhookReceiver()
    ## LINE events were acked with 200 when queued, so LINE will not redeliver
    ## them: drain them before the actors are cancelled.
    if ctx.env.lineChannelAccessToken.len > 0:
      discard drainer.drainLine()
      ## The event was acked with 200 and is now being processed; give the
      ## admitted turn the same bounded chance Slack gets before the actors are
      ## cancelled.
      await sleepAsync(ctimer.milliseconds(500))
    ## Stop ingress first, then let already-admitted turns publish their replies.
    ## Connections accepted before the stop may have enqueued Feishu events;
    ## consume them once before exiting. Slack envelopes were already acked
    ## when queued, so give admitted turns a bounded chance to finish before
    ## cancelling actors and children.
    discard drainer.drainSlack()
    let slackInbound = ctx.env.slackBotToken.len > 0 and
      (ctx.env.slackSigningSecret.len > 0 or ctx.env.slackAppToken.len > 0)
    if slackInbound:
      await sleepAsync(ctimer.milliseconds(2000))
    drainGlobalOutbox(ctx.runtime, ctx.adapters, log)
    discard drainer.drainFeishu()
    await sleepAsync(ctimer.milliseconds(500))
    drainGlobalOutbox(ctx.runtime, ctx.adapters, log)
    let actorStop = ctx.runtime.sm.cancelAllActors()
    let actorsStopped = await withTimeout(
      actorStop, ctimer.milliseconds(2_000))
    if not actorsStopped:
      log.warn("daemon shutdown: actor stop deadline elapsed")
    if ctx.services.browserRuntime != nil:
      let browserStopped = await withTimeout(
        ctx.services.browserRuntime.stop(), ctimer.milliseconds(2_000))
      if not browserStopped:
        log.warn("daemon shutdown: browser stop deadline elapsed")
    drainGlobalOutbox(ctx.runtime, ctx.adapters, log)
    if ctx.runtime.stateStore != nil:
      discard ctx.runtime.stateStore.flushSessions()

# ── main ───────────────────────────────────────────────────────────────────────

proc main =
  var configPath = ""
  var args: seq[string] = @[]
  var logsFollow = false
  var logsCat    = false
  var devMode    = false
  var configPathPending = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "version": printVersion(); quit(0)
      of "help":    printHelp();    quit(0)
      of "config":
        if val.len > 0:
          configPath = val
          configPathPending = false
        else:
          configPathPending = true
      of "cat":     logsCat    = true
      of "dev-mode": devMode   = true
      else: discard
    of cmdShortOption:
      case key
      of "v": printVersion(); quit(0)
      of "h": printHelp();    quit(0)
      of "f": logsFollow = true
      else: discard
    of cmdArgument:
      if configPathPending:
        configPath = key
        configPathPending = false
      else:
        args.add key
    of cmdEnd:
      break

  if args.len >= 3 and args[0] == SandboxExecCommand:
    quit(runSandboxWorker(newProcessAdapter(), args[1], args[2]))

  # setup doesn't need config — handle it early
  if args.len >= 1 and args[0] == "setup":
    let env = readEnvironment()
    runSetupWizard(newFsAdapter(), resolveHome(env), env)
    quit(0)

  if configPath.len == 0:
    configPath = getConfigDir() / ConfigDirName / ConfigFileName

  let home = resolveHome(readEnvironment())

  ## Load .env file if present — checks {home}/donkey.env then ~/.config/donkey/donkey.env
  discard loadDonkeyEnv(home)

  ## From here on the environment is read once: `cfg.env` is the snapshot
  ## taken after donkey.env (and, below, the vault) filled it in.
  var cfg = loadConfig(configPath, readEnvironment())
  ## Decrypting the vault must not block administrative commands that do not
  ## consume its variables (service stop/logs, secret recovery, user/pairing).
  let needsVault =
    args.len == 0 or
    args[0] in ["start", "about", "doctor"] or
    (args[0] == "ctl" and args.len >= 2 and
     (args[1] in ["provider", "memory"] or
      (args[1] == "skill" and args.len >= 3 and
       args[2] in ["install", "update", "search"])))
  if needsVault:
    let vaultApplied = newSecretVault(cfg.home).applyToEnv()
    if vaultApplied.isErr:
      stderr.writeLine "Security Error: " & vaultApplied.error
      quit(1)
    if vaultApplied.get() > 0:
      ## Reload env-backed policies (dm_policy, allowlist, ...) after the
      ## vault populated variables that were absent from donkey.env.
      cfg = loadConfig(configPath, readEnvironment())
  ## Provider keys and the presence checks of /about and /doctor read the
  ## snapshot installed here, on the loop thread that uses them.
  useCredentials(cfg.env)
  configureApprovalServiceFromEnv(
    newApprovalStore(cfg.home / "state" / "approvals.json").toApprovalPort(), cfg.env)

  let sandboxPolicy = validateSandboxPolicy(cfg, devMode)
  if sandboxPolicy.isErr:
    stderr.writeLine sandboxPolicy.error
    stderr.writeLine "Use --dev-mode only for local development, or tighten the [sandbox] policy in donkey.toml"
    quit(1)
  let sandboxAvailability = sandboxAvailabilityResult(newProcessAdapter(), newFsAdapter(), cfg)
  if not devMode and sandboxAvailability.isErr:
    stderr.writeLine "Security Error: " & sandboxAvailability.error
    stderr.writeLine "Install the configured sandbox runtime, or switch to a supported [sandbox] mode before starting in production"
    quit(1)
  let paddockOwnership = validatePaddockOwnership(newFsAdapter(), cfg, devMode)
  if paddockOwnership.isErr:
    stderr.writeLine paddockOwnership.error
    stderr.writeLine "Fix ownership of the paddocks directory before starting in production"
    quit(1)

  ringInit()            ## enable log ring buffer before the first Logger is created
  initReliability()     ## enable circuit breaker and reliability tracking
  agentEventRingInit()  ## enable agent event ring buffer
  enableHumanLog()
  if isatty(stderr): enableColorLog()
  let log = newLogger(AppSlug)

  let registryPath = cfg.home / "tools.toml"
  let memory       = MdFileAdapter(paddocksDir: cfg.paddocks)

  # ── command registry ────────────────────────────────────────────────────────
  let cmdReg = newCommandRegistry()

  # Pre-bootstrap commands (no config needed)
  cmdReg.register(CommandEntry(
    name: "setup", minArgs: 1,
    handler: proc(a: seq[string]): int =
      runSetupWizard(newFsAdapter(), resolveHome(cfg.env), cfg.env); 0,
    context: ccNone, description: "Interactive first-run configuration wizard"))

  # Post-bootstrap commands
  cmdReg.register(CommandEntry(
    name: "ctl", minArgs: 2,
    handler: proc(a: seq[string]): int =
      dispatchCtl(cfg, memory, registryPath, a,
                  proc(preferencesMd: string): CompleteFn =
                    buildCompleteFn(preferencesMd, buildProviderBundle)),
    context: ccConfigLoaded, description: "Admin commands (user, skill, tool, memory, status)"))
  cmdReg.register(CommandEntry(
    name: "service", minArgs: 2,
    handler: proc(a: seq[string]): int =
      dispatchService(newProcessAdapter(), newFsAdapter(), a, logsFollow, cfg.env),
    context: ccNone, description: "Systemd --user service management"))
  cmdReg.register(CommandEntry(
    name: "tui", minArgs: 1,
    handler: proc(a: seq[string]): int =
      dispatchTui(cfg.home / SockFileName, cfg.env),
    context: ccConfigLoaded, description: "Open live TUI dashboard"))
  cmdReg.register(CommandEntry(
    name: "doctor", minArgs: 1,
    handler: proc(a: seq[string]): int =
      runDoctor(newProcessAdapter(), newFsAdapter(), cfg, devMode),
    context: ccConfigLoaded, description: "Run full runtime diagnostic"))
  cmdReg.register(CommandEntry(
    name: "about", minArgs: 1,
    handler: proc(a: seq[string]): int =
      echo buildDoctorSummary(cfg, devMode); 0,
    context: ccConfigLoaded, description: "Show concise runtime overview"))
  cmdReg.register(CommandEntry(
    name: "start", minArgs: 1,
    handler: proc(a: seq[string]): int =
      logDaemonStart(log, cfg)
      waitFor startDaemon(cfg, log)
      0,
    context: ccConfigLoaded, description: "Start the daemon"))

  # ── dispatch ────────────────────────────────────────────────────────────────
  if args.len >= 1:
    let exitCode = cmdReg.dispatch(args)
    if exitCode == 2: printHelp()
    quit(if exitCode < 0: 1 else: exitCode)

  # No command given → default to start daemon
  logDaemonStart(log, cfg)
  waitFor startDaemon(cfg, log)

when isMainModule:
  main()
