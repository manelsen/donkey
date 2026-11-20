## donkey — AI agent system entry point.

import std/[algorithm, json, locks, options, os, parseopt, strutils, tables, terminal, times]
when defined(posix):
  import std/posix
import locks
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
import donkey/core/pipeops
import donkey/core/reliability
import donkey/core/agent_events
import donkey/core/app_meta
import donkey/core/command_registry
import donkey/core/providers/smart_routing
import donkey/adapters/memory/md_file
when defined(withPostgres) or defined(withSqlite):
  import donkey/adapters/memory/multigraph_runtime
import donkey/adapters/provider/openrouter
import donkey/adapters/provider/runtime_builder
import donkey/adapters/provider/model_catalog
import donkey/adapters/http/std_http
import donkey/adapters/channel/telegram
import donkey/adapters/channel/outbound_builder
import donkey/app/inbound_gate
import donkey/core/security/dm_policy
import donkey/app/inbound_media
import donkey/adapters/filesystem/attachment_store
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_runtime
import donkey/adapters/channel/text_command_dispatch
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
import donkey/adapters/tools/browser_executor
import donkey/domain/tools/browser_pure
import donkey/adapters/state/runtime_store
import donkey/adapters/state/schedule_store
import donkey/adapters/state/pairing_store
import donkey/adapters/state/approval_store
import donkey/adapters/secrets/vault
import donkey/app/approval_runtime
import donkey/domain/message
import donkey/domain/agent_message
import donkey/domain/providers/descriptors
import donkey/ports/provider
import donkey/ports/subagent_workspace
import donkey/ports/http
import donkey/ports/channel
import donkey/ports/tool
import donkey/ports/runtime_state
import donkey/app/orchestrator
import donkey/app/sandbox
import donkey/app/ipc_server
import donkey/app/http_gateway
import donkey/app/chat_bridge
import donkey/domain/gateway/dashboard_pure
import donkey/domain/gateway/identity_pure
import donkey/app/heartbeat
import donkey/app/scheduler_wiring
import donkey/app/metrics_server
import donkey/app/outbound_runtime
import donkey/app/gateway_drainer
import donkey/app/session_manager
import donkey/adapters/state/daemon_lease
import donkey/app/session_bootstrap
import donkey/app/session_ingress
import donkey/app/doctor
import donkey/app/setup_wizard
import donkey/app/service_handler
import donkey/app/tui_handler
import donkey/app/daemon_start_handler
import donkey/ctl_handler
import donkey/ports/memory
import donkey/adapters/ipc/types    as ipcTypes

var gRoutingLock: Lock

template withRouteLock(body: untyped): untyped =
  block:
    acquire(gRoutingLock)
    try:
      body
    finally:
      release(gRoutingLock)

const Version* = AppVersion

proc printVersion =
  echo AppSlug & " " & Version

proc printHelp =
  echo AppSlug & " " & Version & """

Usage:
  """ & AppSlug & """ [options] [command]

Options:
  --version        Print version and exit
  --help           Show this help
  --config <path>  Path to """ & ConfigFileName & """  (default: ~/.config/""" & ConfigDirName & "/" & ConfigFileName & """)
  --dev-mode       Enable development mode (allows sandbox=none)

Commands:
  setup                          Interactive first-run configuration wizard
  about                          Show a concise runtime overview
  start                          Start the daemon
  ctl user list                  List registered users
  ctl user show <uuid>           Show user profile
  ctl user edit <uuid> <field> <value>
                                Edit a USER.md field
  ctl user revoke <uuid>        Revoke user access
  ctl user allow <uuid>         Restore user access
  ctl pair list                 List pending DM pairing requests
  ctl pair approve <code>       Approve a pairing request and allow the user
  ctl pair reject <code>        Discard a pairing request
  ctl approval list [user]      List pending tool approvals
  ctl approval approve <id>     Approve a pending tool call
  ctl approval deny <id>        Deny a pending tool call
  ctl secret set <name>         Encrypt a secret read from stdin
  ctl secret list               List stored secret names (never values)
  ctl secret remove <name>      Remove a stored secret
  ctl secret import-env [path]  Encrypt KEY=VALUE pairs from donkey.env
  ctl session list <uuid>        List active sessions for a user
  ctl tool install <command>            Register an MCP server
  ctl skill search <query>              Search remote skills on ClawHub
  ctl skill install <name> <script>     Register a local Deno skill
  ctl skill install <slug>              Download/install remote skill bundle
  ctl skill list                        List local skill registry + remote installs
  ctl skill update <name> <script>      Update a local skill path
  ctl skill update [slug]               Update one/all remote installed skills
  ctl provider test <name>              Test provider connectivity
  ctl memory search <uuid> <q>   Semantic search in user memory via MAGMA
  ctl memory import <uuid>       Import .md paddock into MAGMA
  ctl memory export <uuid> [dir] Export MAGMA memory view as .md
  ctl status                     Show daemon status (daemon must be running)
  tui                            Open live TUI dashboard (daemon must be running)
  service install                Install as systemd --user service
  service remove                 Remove the systemd --user service
  service start                  systemctl --user start """ & AppSlug & """
  service stop                   systemctl --user stop """ & AppSlug & """
  service restart                systemctl --user restart """ & AppSlug & """
  service logs [-f] [--cat]      Show service logs (follow with -f, clean output with --cat)
  doctor                         Run the full runtime diagnostic
"""

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
##   presentationState.streamMsgIds[channel|user|stream] = channelMsgId:
##     - first partial: send new message, store id
##     - subsequent partials: editMessage
##     - isPartial=false: editMessage + delete from presentationState

proc makeTgTypingFn(token: string; identityPath: string; log: Logger): TypingFn =
  ## Returns a TypingFn that sends typing indicators to Telegram users.
  ## Uses its own TelegramAdapter instance (token + resolver shared via ref).
  let tg = new TelegramAdapter
  tg[] = newTelegramAdapter(token, identityPath,
                            apiBase = getEnv("DONKEY_TELEGRAM_API_BASE").strip(),
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
  completeFn: CompleteFn
  streamFn:   StreamFn

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

const
  RecentRouteSampleLimit = 32
  DefaultRecentRouteSampleTtlSec = 6 * 60 * 60
  DefaultProviderCooldownSec = 10 * 60

type RouteSample = object
  ok: bool
  elapsedMs: int
  recordedAtUnix: int64

type DaemonServices = object
  toolClients:      seq[ToolRuntimePort]
  tools:            seq[ToolDescription]
  browserRuntime:   BrowserExecutor
  globalCompleteFn: CompleteFn
  globalStreamFn:   StreamFn
  tgTypingFn:       TypingFn
  globalSearchFn:   SearchFn

type
  PollResult = Result[seq[InboundMessage], string]

var
  gEmailPollCh: Channel[PollResult]
  gSignalPollCh: Channel[PollResult]
  gEmailPollThread: Thread[ptr EmailAdapter]
  gSignalPollThread: Thread[ptr SignalAdapter]
  gEmailPollOpened = false
  gSignalPollOpened = false
  gEmailPollInFlight = false
  gSignalPollInFlight = false

func pollFailure(msg: string): PollResult {.gcsafe.} =
  err(msg)

proc emailPollThread(adapter: ptr EmailAdapter) {.thread.} =
  var res: PollResult
  try:
    res = adapter[].pollInbox()
  except Exception as e:
    res = pollFailure(e.msg)
  gEmailPollCh.send(res)

proc signalPollThread(adapter: ptr SignalAdapter) {.thread.} =
  var res: PollResult
  try:
    res = adapter[].receive()
  except Exception as e:
    res = pollFailure(e.msg)
  gSignalPollCh.send(res)

type DaemonRuntime = ref object
  globalOutbox:         AsyncQueue[OutboundMessage]
  sm:                   SessionManager
  stateStore:           RuntimeStateStore
  ledger:               DeliveryLedgerPort
  ledgerWorker:         LedgerCompactionWorker
  presentationState:    PresentationState
  routeCounts:          Table[string, int]
  routeCallCounts:      Table[string, int]
  routeOkCounts:        Table[string, int]
  routeErrCounts:       Table[string, int]
  routeLatencyTotalsMs: Table[string, int64]
  routeRecentSamples:   Table[string, seq[RouteSample]]
  providerCooldownUntil: Table[string, int64]
  routeHealthPath:      string
  lastReminderCheckMs:  int64
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
    var client = buildMcpClient(entry)
    let schemasRes = client.listTools()
    if schemasRes.isOk:
      for s in schemasRes.value:
        result.tools.add(ToolDescription(
          name:        s.name,
          description: s.description,
          schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
        ))
    result.clients.add(client.toRuntimePort())
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
  let parsedBackend = parseBrowserBackend(getEnv("DONKEY_BROWSER_BACKEND"))
  var browserBackend = bbOff
  if parsedBackend.isSome:
    browserBackend = parsedBackend.get()
  elif getEnv("DONKEY_BROWSER_BACKEND").strip.len > 0:
    log.warn("browser: invalid DONKEY_BROWSER_BACKEND='" &
             getEnv("DONKEY_BROWSER_BACKEND") & "'; tools disabled")
  if browserBackend != bbOff:
    let rawBrowserTimeout = getEnv("DONKEY_BROWSER_TIMEOUT_MS").strip()
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
          executablePath = getEnv("DONKEY_BROWSER_PATH"),
          profileBaseDir = getEnv("DONKEY_BROWSER_PROFILE_DIR"),
          proxyServer = getEnv("DONKEY_BROWSER_PROXY"),
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
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

proc buildGlobalProviderBundle(): GlobalProviderBundle =
  let openRouter = descriptorOr("openrouter")
  let orKey =
    if openRouter.envNames.len > 0: getEnv(openRouter.envNames[0])
    else: ""
  let orAdapter = newOpenRouterAdapter(orKey)
  result.completeFn = if orKey.len > 0: makeProviderFn(orAdapter) else: nil
  result.streamFn = if orKey.len > 0: orAdapter.makeStreamFn() else: nil

func routeCostProviderIds(): seq[string] =
  ## Cost hints cover every provider that has a descriptor.
  for descriptor in providerDescriptors():
    result.add descriptor.id

proc buildGlobalSearchFn(memory: MdFileAdapter): SearchFn {.gcsafe.}

func defaultMagmaSqlitePath(home: string): string =
  home / "state" / "magma.sqlite"

func configuredMagmaSqlitePath(home: string): string =
  when defined(withSqlite):
    let configured = getEnv("DONKEY_MAGMA_SQLITE_PATH")
    if configured.len > 0: configured else: defaultMagmaSqlitePath(home)
  else:
    getEnv("DONKEY_MAGMA_SQLITE_PATH")

proc initDaemonServices(cfg: DonkeyConfig;
                        env: DaemonEnv;
                        log: Logger): DaemonServices =
  let toolBundle = loadDaemonToolBundle(cfg, log)
  result.toolClients = toolBundle.clients
  result.tools = toolBundle.tools
  result.browserRuntime = toolBundle.browserRuntime

  let providerBundle = buildGlobalProviderBundle()
  result.globalCompleteFn = providerBundle.completeFn
  result.globalStreamFn = providerBundle.streamFn
  result.tgTypingFn = makeTgTypingFn(env.telegramToken, env.identityPath, log)
  result.globalSearchFn = buildGlobalSearchFn(env.memory)
  when defined(withPostgres) or defined(withSqlite):
    if result.globalSearchFn != nil:
      log.info("MAGMA semantic search enabled")

proc loadDaemonEnv(cfg: DonkeyConfig; log: Logger): DaemonEnv =
  result.telegramToken = getEnv("TELEGRAM_BOT_TOKEN").strip()
  if result.telegramToken.len == 0:
    log.warn("TELEGRAM_BOT_TOKEN not set — Telegram disabled")

  result.discordToken = getEnv("DISCORD_BOT_TOKEN")
  result.discordGuildId = getEnv("DISCORD_GUILD_ID")
  result.wecomCorpId = getEnv("WECOM_CORP_ID")
  result.wechatAppId = getEnv("WECHAT_APP_ID")
  result.feishuAppId = getEnv("FEISHU_APP_ID")
  result.slackBotToken = getEnv("SLACK_BOT_TOKEN")
  result.slackAppToken = getEnv("SLACK_APP_TOKEN")
  result.dingTalkAppKey = getEnv("DINGTALK_APP_KEY")
  result.dingTalkAppSecret = getEnv("DINGTALK_APP_SECRET")
  result.dingTalkRobotCode = getEnv("DINGTALK_ROBOT_CODE")
  result.qqApiBase = getEnv("QQ_ONEBOT_URL")
  result.qqOfficialAppId = getEnv("QQ_OFFICIAL_APP_ID")
  result.qqOfficialApiBase = getEnv("QQ_OFFICIAL_API_BASE")
  let pgDsn = getEnv("DONKEY_PG_DSN")
  result.memory = MdFileAdapter(
    paddocksDir:     cfg.paddocks,
    magmaDsn:       pgDsn,
    magmaSqlitePath: configuredMagmaSqlitePath(cfg.home),
    magmaSqliteVectorPath:
      block:
        let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
        if vecPath.len > 0: vecPath else: getEnv("DONKEY_SQLITE_VECTOR_PATH"),
  )
  result.identityPath = cfg.home / "identities.tsv"
  let wecomAgentIdStr = getEnv("WECOM_AGENT_ID")
  result.wecomAgentId =
    if wecomAgentIdStr.len > 0: parseInt(wecomAgentIdStr) else: 0
  
  # WhatsApp Cloud API
  result.whatsappAccessToken = getEnv("WHATSAPP_ACCESS_TOKEN")
  result.whatsappPhoneNumberId = getEnv("WHATSAPP_PHONE_NUMBER_ID")

  # HTTP webhook receiver (Slack / Feishu / DingTalk / Matrix / WhatsApp)
  let webhookPortStr = getEnv("DONKEY_WEBHOOK_PORT")
  result.webhookPort = 0
  if webhookPortStr.len > 0:
    try:
      result.webhookPort = parseInt(webhookPortStr)
    except ValueError:
      result.webhookPort = 0
  let webhookHost = getEnv("DONKEY_WEBHOOK_HOST")
  result.webhookHost = if webhookHost.len > 0: webhookHost else: "127.0.0.1"
  result.webhookTlsCert = getEnv("DONKEY_WEBHOOK_TLS_CERT").strip()
  result.webhookTlsKey = getEnv("DONKEY_WEBHOOK_TLS_KEY").strip()
  result.slackSigningSecret = getEnv("SLACK_SIGNING_SECRET")
  result.feishuVerificationToken = getEnv("FEISHU_VERIFICATION_TOKEN")
  result.feishuEncryptKey = getEnv("FEISHU_ENCRYPT_KEY")
  ## LINE: the route is mounted only when the access token exists; the channel
  ## secret is the HMAC key for X-Line-Signature. Groups are default-deny
  ## (empty = none), users are opt-in (empty = all) — see line_policy.
  result.lineChannelSecret = getEnv("LINE_CHANNEL_SECRET").strip()
  result.lineChannelAccessToken = getEnv("LINE_CHANNEL_ACCESS_TOKEN").strip()
  result.lineAllowedGroups = parseChatIdList(getEnv("LINE_ALLOWED_GROUPS"))
  result.lineAllowedUsers = parseChatIdList(getEnv("LINE_ALLOWED_USERS"))
  result.matrixWebhookToken = getEnv("MATRIX_WEBHOOK_TOKEN")
  result.whatsappVerifyToken = getEnv("WHATSAPP_VERIFY_TOKEN")
  result.whatsappAppSecret = getEnv("WHATSAPP_APP_SECRET")

proc initDaemonAdapters(env: DaemonEnv): DaemonAdapters =
  result.tg = newTelegramAdapter(
    env.telegramToken, env.identityPath,
    apiBase = getEnv("DONKEY_TELEGRAM_API_BASE").strip(),
    pollTimeout = 0)
  result.dc = newDiscordAdapter(env.discordToken, env.identityPath)
  result.wc = newWeComAdapter(env.wecomCorpId, getEnv("WECOM_CORP_SECRET"),
                              getEnv("WECOM_CALLBACK_TOKEN"), env.wecomAgentId,
                              env.identityPath)
  result.wch = newWeChatAdapter(env.wechatAppId, getEnv("WECHAT_APP_SECRET"),
                                getEnv("WECHAT_CALLBACK_TOKEN"),
                                getEnv("WECHAT_TEMPLATE_ID"),
                                env.identityPath)
  if env.qqOfficialAppId.len > 0 and getEnv("QQ_OFFICIAL_CLIENT_SECRET").len > 0:
    result.qq = newQQOfficialChannelAdapter(
      env.qqOfficialAppId,
      getEnv("QQ_OFFICIAL_CLIENT_SECRET"),
      env.identityPath,
      apiBase = getEnv("QQ_OFFICIAL_API_BASE"),
      tokenBase = getEnv("QQ_OFFICIAL_TOKEN_BASE"),
    )
  elif env.qqApiBase.len > 0:
    result.qq = newQQOneBotChannelAdapter(env.qqApiBase, getEnv("QQ_ONEBOT_TOKEN"),
                                          env.identityPath)
  else:
    result.qq = newQQDisabledChannelAdapter(env.identityPath)
  result.fs = newFeishuAdapter(env.feishuAppId, getEnv("FEISHU_APP_SECRET"),
                               env.identityPath)
  result.sl = newSlackAdapter(env.slackBotToken, env.identityPath)
  result.dt = newDingTalkAdapter(env.dingTalkAppKey, env.dingTalkAppSecret,
                                 env.dingTalkRobotCode, env.identityPath)
  ## A stale/bad `LINE_API_BASE` must not abort startup when LINE is not
  ## configured: construct at the default base in that case (the adapter then
  ## fails sends with "missing token", which is the truth).
  result.ln =
    if env.lineChannelAccessToken.len > 0:
      newLineAdapter(env.lineChannelAccessToken, env.identityPath)
    else:
      newLineAdapter("", env.identityPath, apiBase = "https://api.line.me")
  result.mx = newMatrixAdapter(getEnv("MATRIX_HOMESERVER"), getEnv("MATRIX_BOT_USER_ID"),
                               getEnv("MATRIX_ACCESS_TOKEN"), env.identityPath)
  result.em = newEmailAdapter(getEnv("EMAIL_IMAP_HOST"), getEnv("EMAIL_SMTP_HOST"),
                              getEnv("EMAIL_USER"), getEnv("EMAIL_PASSWORD"),
                              env.identityPath)
  result.cli = newCliAdapter()
  
  # WhatsApp (optional - only if credentials are set)
  if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
    result.wa = newWhatsAppAdapter(env.whatsappAccessToken, env.whatsappPhoneNumberId,
                                   env.identityPath)

  # Signal (optional - requires a running signal-cli daemon socket)
  let signalAccount = getEnv("SIGNAL_ACCOUNT").strip()
  if signalAccount.len > 0:
    let rawSock = getEnv("SIGNAL_SOCKET").strip()
    result.signal = newSignalAdapter(
      signalAccount,
      env.identityPath,
      sockPath = if rawSock.len > 0: rawSock else: SignalDefaultSock,
    )

func recentRouteSampleTtlSec(): int64 =
  let raw = getEnv("DONKEY_ROUTE_HEALTH_TTL_SEC")
  if raw.len == 0:
    return DefaultRecentRouteSampleTtlSec
  try:
    let ttl = parseInt(raw)
    if ttl > 0: ttl else: DefaultRecentRouteSampleTtlSec
  except ValueError:
    DefaultRecentRouteSampleTtlSec

func routeHealthPath(home: string): string =
  home / "state" / "route_health.json"

func providerCooldownSec(): int64 =
  let raw = getEnv("DONKEY_PROVIDER_COOLDOWN_SEC")
  if raw.len == 0:
    return DefaultProviderCooldownSec
  try:
    let ttl = parseInt(raw)
    if ttl > 0: ttl else: DefaultProviderCooldownSec
  except ValueError:
    DefaultProviderCooldownSec

proc pruneRecentRouteSamples(runtime: DaemonRuntime) =
  let nowSec = getTime().toUnix()
  let ttlSec = recentRouteSampleTtlSec()
  for route, samples in runtime.routeRecentSamples.mpairs:
    var kept: seq[RouteSample] = @[]
    for sample in samples:
      if sample.recordedAtUnix > 0 and nowSec - sample.recordedAtUnix <= ttlSec:
        kept.add(sample)
    if kept.len > RecentRouteSampleLimit:
      kept = kept[(kept.len - RecentRouteSampleLimit) .. ^1]
    samples = kept

proc pruneProviderCooldowns(runtime: DaemonRuntime) =
  let nowSec = getTime().toUnix()
  var expired: seq[string] = @[]
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix <= nowSec:
      expired.add(providerName)
  for providerName in expired:
    runtime.providerCooldownUntil.del(providerName)

proc saveRecentRouteSamples(runtime: DaemonRuntime) =
  if runtime.routeHealthPath.len == 0:
    return
  try:
    runtime.pruneRecentRouteSamples()
    createDir(parentDir(runtime.routeHealthPath))
    var data = newJArray()
    for route, samples in runtime.routeRecentSamples:
      if samples.len == 0:
        continue
      var sampleData = newJArray()
      for sample in samples:
        sampleData.add(%*{
          "ok": sample.ok,
          "elapsed_ms": sample.elapsedMs,
          "recorded_at": sample.recordedAtUnix,
        })
      data.add(%*{
        "route": route,
        "samples": sampleData,
      })
    var cooldowns = newJArray()
    for providerName, untilUnix in runtime.providerCooldownUntil:
      cooldowns.add(%*{
        "provider": providerName,
        "until_unix": untilUnix,
      })
    writeFile(runtime.routeHealthPath, $(%*{
      "saved_at": getTime().toUnix(),
      "routes": data,
      "provider_cooldowns": cooldowns,
    }))
  except CatchableError:
    discard

proc loadRecentRouteSamples(runtime: DaemonRuntime) =
  if runtime.routeHealthPath.len == 0 or not fileExists(runtime.routeHealthPath):
    return
  try:
    let parsed = parseJson(readFile(runtime.routeHealthPath))
    for routeNode in parsed{"routes"}:
      let route = routeNode{"route"}.getStr("")
      if route.len == 0:
        continue
      var samples: seq[RouteSample] = @[]
      for sampleNode in routeNode{"samples"}:
        samples.add(RouteSample(
          ok: sampleNode{"ok"}.getBool(false),
          elapsedMs: sampleNode{"elapsed_ms"}.getInt(0),
          recordedAtUnix: sampleNode{"recorded_at"}.getBiggestInt(0),
        ))
      runtime.routeRecentSamples[route] = samples
    runtime.pruneRecentRouteSamples()
    for cooldownNode in parsed{"provider_cooldowns"}:
      let providerName = cooldownNode{"provider"}.getStr("")
      let untilUnix = cooldownNode{"until_unix"}.getBiggestInt(0)
      if providerName.len > 0 and untilUnix > 0:
        runtime.providerCooldownUntil[providerName] = untilUnix
    runtime.pruneProviderCooldowns()
  except CatchableError:
    discard

var gRoutingLockReady = false

proc envFloatValue(name: string; default: float): float =
  let raw = getEnv(name).strip()
  if raw.len == 0:
    return default
  try:
    result = parseFloat(raw)
  except ValueError:
    result = default

proc initDaemonRuntime(home: string): DaemonRuntime =
  new(result)
  if not gRoutingLockReady:
    initLock(gRoutingLock)
    gRoutingLockReady = true
  result.globalOutbox = newAsyncQueue[OutboundMessage]()
  result.sm.init()
  let stateStore = newRuntimeStateStore(
    home / "state",
    ledgerRetentionDays = envFloatValue("DONKEY_LEDGER_RETENTION_DAYS",
                                        LedgerRetentionDaysDefault),
    ledgerCompactIntervalSec = envFloatValue("DONKEY_LEDGER_COMPACT_INTERVAL_SEC",
                                             LedgerCompactIntervalSecDefault),
  )
  result.stateStore = stateStore
  result.sm.setRegistryStore(stateStore.sessionRegistry())
  result.ledger = stateStore.deliveryLedger()
  result.presentationState = initPresentationState()
  result.routeHealthPath = routeHealthPath(home)
  result.loadRecentRouteSamples()
  result.daemonStartMs = nowMs()

proc recordRouteChoice(runtime: DaemonRuntime; selection: ProviderSelection) =
  let key = selection.formatSelection
  runtime.routeCounts[key] = runtime.routeCounts.getOrDefault(key) + 1

proc refreshProviderCooldowns(runtime: DaemonRuntime) {.gcsafe.}
proc currentRouteFeedback(runtime: DaemonRuntime): seq[RouteFeedback] {.gcsafe.}

proc recordRouteResult(runtime: DaemonRuntime;
                       selection: ProviderSelection;
                       elapsedMs: int64;
                       ok: bool) {.gcsafe.} =
  let key = selection.formatSelection
  let nowSec = getTime().toUnix()
  runtime.routeCallCounts[key] = runtime.routeCallCounts.getOrDefault(key) + 1
  runtime.routeLatencyTotalsMs[key] = runtime.routeLatencyTotalsMs.getOrDefault(key) + elapsedMs
  var samples = runtime.routeRecentSamples.getOrDefault(key)
  samples.add(RouteSample(
    ok: ok,
    elapsedMs: if elapsedMs > 0: int(elapsedMs) else: 0,
    recordedAtUnix: nowSec,
  ))
  if samples.len > RecentRouteSampleLimit:
    samples = samples[(samples.len - RecentRouteSampleLimit) .. ^1]
  runtime.routeRecentSamples[key] = samples
  runtime.pruneRecentRouteSamples()
  runtime.saveRecentRouteSamples()
  if ok:
    runtime.routeOkCounts[key] = runtime.routeOkCounts.getOrDefault(key) + 1
  else:
    runtime.routeErrCounts[key] = runtime.routeErrCounts.getOrDefault(key) + 1
  runtime.refreshProviderCooldowns()

proc refreshProviderCooldowns(runtime: DaemonRuntime) {.gcsafe.} =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  for feedback in aggregateProviderFeedback(runtime.currentRouteFeedback()):
    if feedback.shouldCircuitBreakProvider and
       runtime.providerCooldownUntil.getOrDefault(feedback.providerName) <= nowSec:
      runtime.providerCooldownUntil[feedback.providerName] = nowSec + providerCooldownSec()
  runtime.saveRecentRouteSamples()

proc topRouteCounts(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteCount] =
  var items: seq[(string, int)] = @[]
  for route, count in runtime.routeCounts:
    items.add((route, count))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    result.add(ipcTypes.RouteCount(route: items[i][0], count: items[i][1]))

proc topRouteMetrics(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteMetric] =
  var items: seq[(string, int)] = @[]
  for route, calls in runtime.routeCallCounts:
    items.add((route, calls))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let route = items[i][0]
    let calls = items[i][1]
    let totalLatency = runtime.routeLatencyTotalsMs.getOrDefault(route)
    result.add(ipcTypes.RouteMetric(
      route: route,
      calls: calls,
      okCalls: runtime.routeOkCounts.getOrDefault(route),
      errCalls: runtime.routeErrCounts.getOrDefault(route),
      avgLatencyMs: if calls > 0: int(totalLatency div calls) else: 0,
    ))

proc topRecentRouteMetrics(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.RouteMetric] =
  runtime.pruneRecentRouteSamples()
  var items: seq[(string, int)] = @[]
  for route, samples in runtime.routeRecentSamples:
    if samples.len > 0:
      items.add((route, samples.len))
  items.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      return cmp(b[1], a[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let route = items[i][0]
    let samples = runtime.routeRecentSamples.getOrDefault(route)
    var okCalls = 0
    var errCalls = 0
    var totalLatency = 0
    for sample in samples:
      totalLatency += sample.elapsedMs
      if sample.ok:
        inc okCalls
      else:
        inc errCalls
    let calls = samples.len
    result.add(ipcTypes.RouteMetric(
      route: route,
      calls: calls,
      okCalls: okCalls,
      errCalls: errCalls,
      avgLatencyMs: if calls > 0: totalLatency div calls else: 0,
    ))

proc currentRouteFeedback(runtime: DaemonRuntime): seq[RouteFeedback] {.gcsafe.} =
  runtime.pruneRecentRouteSamples()
  for route, samples in runtime.routeRecentSamples:
    if samples.len == 0:
      continue
    var okCalls = 0
    var errCalls = 0
    var totalLatency = 0
    for sample in samples:
      totalLatency += sample.elapsedMs
      if sample.ok:
        inc okCalls
      else:
        inc errCalls
    let calls = samples.len
    result.add(RouteFeedback(
      route: route,
      calls: calls,
      okCalls: okCalls,
      errCalls: errCalls,
      avgLatencyMs: if calls > 0: totalLatency div calls else: 0,
    ))

proc topRecentProviderMetrics(runtime: DaemonRuntime; limit = 5): seq[ipcTypes.ProviderMetric] =
  let feedback = aggregateProviderFeedback(runtime.currentRouteFeedback())
  var items = feedback
  items.sort(proc(a, b: ProviderFeedback): int =
    if a.calls != b.calls:
      return cmp(b.calls, a.calls)
    cmp(a.providerName, b.providerName)
  )
  for i in 0 ..< min(limit, items.len):
    result.add(ipcTypes.ProviderMetric(
      providerName: items[i].providerName,
      calls: items[i].calls,
      okCalls: items[i].okCalls,
      errCalls: items[i].errCalls,
      avgLatencyMs: items[i].avgLatencyMs,
    ))

proc activeProviderCooldowns(runtime: DaemonRuntime; limit = 5): seq[string] =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  var items: seq[(string, int64)] = @[]
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix > nowSec:
      items.add((providerName, untilUnix))
  items.sort(proc(a, b: (string, int64)): int =
    if a[1] != b[1]:
      return cmp(a[1], b[1])
    cmp(a[0], b[0])
  )
  for i in 0 ..< min(limit, items.len):
    let remaining = max(0'i64, items[i][1] - nowSec)
    result.add(items[i][0] & " (" & relativeAgeText(remaining) & ")")

proc currentProviderCooldowns(runtime: DaemonRuntime): seq[ProviderCooldown] =
  runtime.pruneProviderCooldowns()
  let nowSec = getTime().toUnix()
  for providerName, untilUnix in runtime.providerCooldownUntil:
    if untilUnix > nowSec:
      result.add(ProviderCooldown(providerName: providerName, untilUnix: untilUnix))

proc initDaemonContext(cfg: DonkeyConfig;
                       env: DaemonEnv;
                       log: Logger): DaemonContext =
  new(result)
  result.env = env
  result.adapters = initDaemonAdapters(env)
  result.services = initDaemonServices(cfg, env, log)
  result.runtime = initDaemonRuntime(cfg.home)

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

proc startOptionalWeComGateway(wcAdapter: var WeComAdapter;
                               wecomCorpId: string;
                               log: Logger) =
  if wecomCorpId.len == 0:
    log.info("WECOM_CORP_ID not set — WeCom disabled")
    return

  let wcPort = Port(parseInt(if getEnv("WECOM_WEBHOOK_PORT").len > 0:
                               getEnv("WECOM_WEBHOOK_PORT") else: "8081"))
  wcAdapter.startWebhook(wcPort, log)
  log.info("WeCom webhook started on port " & $wcPort)

proc startOptionalFeishuGateway(fsAdapter: var FeishuAdapter;
                                feishuAppId: string;
                                log: Logger) =
  if feishuAppId.len == 0:
    log.info("FEISHU_APP_ID not set — Feishu disabled")
    return

  fsAdapter.startGateway()
  log.info("Feishu WebSocket gateway started")

proc startOptionalWeChatGateway(wchAdapter: var WeChatAdapter;
                                wechatAppId: string;
                                log: Logger) =
  if wechatAppId.len == 0:
    log.info("WECHAT_APP_ID not set — WeChat disabled")
    return

  let port = Port(parseInt(if getEnv("WECHAT_WEBHOOK_PORT").len > 0:
                             getEnv("WECHAT_WEBHOOK_PORT") else: "8081"))
  wchAdapter.startWebhook(port, log)
  log.info("WeChat webhook listener started on port " & $port)

proc startOptionalSlackGateway(slAdapter: var SlackAdapter;
                               slackBotToken: string;
                               slackAppToken: string;
                               slackHttp: HttpRuntimePort;
                               log: Logger) =
  if slackBotToken.len == 0:
    log.info("SLACK_BOT_TOKEN not set — Slack disabled")
    return

  slAdapter.openQueue()
  if slackAppToken.len > 0:
    startSlackSocketMode(slackAppToken, slackHttp, log).isOkOr:
      log.error("slack socket: " & error)
  elif getEnv("SLACK_SIGNING_SECRET").len == 0:
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

func matrixConfigured(): bool =
  getEnv("MATRIX_HOMESERVER").len > 0 and
    getEnv("MATRIX_BOT_USER_ID").len > 0 and
    getEnv("MATRIX_ACCESS_TOKEN").len > 0

proc startOptionalMatrixGateway(mxAdapter: var MatrixAdapter;
                                log: Logger) =
  if not matrixConfigured():
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

proc startOptionalWebhookReceiver(env: DaemonEnv; log: Logger) =
  ## Mounts only the routes whose channel is configured AND has a secret.
  if env.webhookPort <= 0:
    log.info("DONKEY_WEBHOOK_PORT not set — webhook receiver disabled")
    return
  if (env.webhookTlsCert.len > 0) != (env.webhookTlsKey.len > 0):
    log.error("DONKEY_WEBHOOK_TLS_CERT and DONKEY_WEBHOOK_TLS_KEY must be set together — webhook receiver disabled")
    return

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
      if matrixConfigured(): env.matrixWebhookToken else: "",
    whatsappVerifyToken:
      if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
        env.whatsappVerifyToken
      else: "",
    whatsappAppSecret:
      if env.whatsappVerifyToken.len > 0: env.whatsappAppSecret else: "",
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
                             log: Logger) =
  if not qqAdapter.enabled():
    log.info("QQ not configured — QQ disabled")
    return
  case qqAdapter.kind
  of qbkOneBot:
    let oneBotPort = Port(parseInt(
      if getEnv("QQ_ONEBOT_WEBHOOK_PORT").len > 0:
        getEnv("QQ_ONEBOT_WEBHOOK_PORT") else: "8082"))
    let oneBotHost =
      if getEnv("QQ_ONEBOT_WEBHOOK_HOST").len > 0: getEnv("QQ_ONEBOT_WEBHOOK_HOST")
      else: "127.0.0.1"
    qqAdapter.startWebhook(oneBotHost, oneBotPort, getEnv("QQ_ONEBOT_SECRET"),
                           log).isOkOr:
      log.error("QQ OneBot webhook: " & error)
      return
    log.info("QQ OneBot webhook listener started on " & oneBotHost & ":" &
             $oneBotPort)
  of qbkOfficial:
    log.info("QQ official API client enabled")
    qqAdapter.startGateway()
    log.info("QQ official gateway started")
  of qbkNone:
    discard

proc buildGlobalSearchFn(memory: MdFileAdapter): SearchFn {.gcsafe.} =
  when defined(withPostgres) or defined(withSqlite):
    result = buildGlobalMagmaSearchFn(memory)
  else:
    discard

# The API turn bridge: the gateway worker registers/polls, the daemon outbox
# drainer delivers `api:` replies here instead of to a channel port.
var gApiChatBridge: ChatBridge

proc apiChatNowMs(): int64 {.gcsafe, raises: [].} =
  int64(epochTime() * 1000)

proc apiChatNap(ms: int) {.gcsafe, raises: [].} =
  ## The ingress actor for an API turn is spawned on the gateway worker thread
  ## (same path as `/api/chat`), so this bounded wait also drives that thread's
  ## dispatcher while the worker waits on the bridge.
  try:
    waitFor(sleepAsync(chronos.milliseconds(ms)))
  except CatchableError:
    discard

# Forward declaration for handleGatewayFallback (defined later, used in setupIpcServer)
proc handleGatewayFallback(ctx: DaemonContext; cfg: DonkeyConfig;
                          memory: MdFileAdapter; msg: InboundMessage;
                          log: Logger) {.gcsafe.}

# Forward declaration for buildDaemonSessionServices (defined later, used in setupIpcServer)
func buildDaemonSessionServices(ctx: DaemonContext; cfg: DonkeyConfig;
                                memory: MdFileAdapter;
                                log: Logger): SessionIngressServices

## The dashboard reads sessions from the gateway worker threads while the
## daemon mutates `sm` on its own thread. Publish a copy from the daemon thread
## under a small lock instead of iterating the live table across threads.
var gSessionsLock: Lock
var gSessionsSnapshot: seq[SessionDetail]
var gSessionsSnapshotSec: int64 = -1

proc publishSessions(sm: SessionManager) {.gcsafe, raises: [].} =
  let nowSec = epochTime().int64
  {.cast(gcsafe).}:
    if nowSec == gSessionsSnapshotSec:
      return
    gSessionsSnapshotSec = nowSec
    let snapshot = sm.listSessionDetails()
    acquire(gSessionsLock)
    try:
      gSessionsSnapshot = snapshot
    finally:
      release(gSessionsLock)

proc sessionsSnapshot(): seq[SessionDetail] {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    acquire(gSessionsLock)
    try:
      result = gSessionsSnapshot
    finally:
      release(gSessionsLock)

proc setupIpcServer(cfg: DonkeyConfig;
                    runtime: DaemonRuntime;
                    sm: SessionManager;
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
  let ipcStatusFn: StatusProvider = proc(): DaemonStatus {.gcsafe, raises: [].} =
    var sessions: seq[SessionInfo]
    for (uid, chans) in sm.listSessions():
      var chanNames: seq[string]
      for (ck, _) in chans:
        chanNames.add($ck)
      sessions.add(SessionInfo(userId: $uid, channels: chanNames))
    var activeChannels: seq[string]
    if telegramToken.len > 0: activeChannels.add("telegram")
    if discordToken.len > 0: activeChannels.add("discord")
    if wecomCorpId.len > 0: activeChannels.add("wecom")
    if wechatAppId.len > 0: activeChannels.add("wechat")
    if feishuAppId.len > 0: activeChannels.add("feishu")
    if slackBotToken.len > 0: activeChannels.add("slack")
    if qqEnabled: activeChannels.add("qq")
    var memoryStats: MemoryStats
    when defined(withPostgres) or defined(withSqlite):
      if gatewayInboundMemory.hasMagmaBackend:
        try:
          memoryStats = loadMagmaMemoryStats(gatewayInboundMemory)
        except CatchableError:
          discard
    DaemonStatus(
      uptimeSec:     (nowMs() - daemonStartMs) div 1000,
      sessionCount:  sm.sessionCount(),
      sessions:      sessions,
      channels:      activeChannels,
      providers:     availableProviderNames(detectProviderAvailability()),
      routeCounts:   withRouteLock(runtime.topRouteCounts()),
      routeMetrics:  withRouteLock(runtime.topRouteMetrics()),
      recentRouteMetrics: withRouteLock(runtime.topRecentRouteMetrics()),
      recentProviderMetrics: withRouteLock(runtime.topRecentProviderMetrics()),
      providerCooldowns: withRouteLock(runtime.activeProviderCooldowns()),
      toolsCount:    toolsCount,
      memoryBackend: block:
        when defined(withPostgres) or defined(withSqlite):
          if gatewayInboundMemory.hasMagmaBackend:
            "md+" & gatewayInboundMemory.magmaBackendName
          else:
            "md"
        else:
          "md",
      memoryStats:   memoryStats,
    )
  let ipcLogFn: LogProvider = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].} =
    for e in ringSnapshot(n):
      result.add(IpcLogEntry(ts: e.ts, level: e.level, subsys: e.sub, msg: e.msg))
  let gwInboundFn: GatewayInboundFn = proc(msg: InboundMessage) {.gcsafe.} =
    handleGatewayFallback(gatewayInboundCtx, cfg, gatewayInboundMemory, msg, gatewayInboundLog)
  let gwAuthorizeFn: AuthorizeFn =
    proc(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
      ## Same policy as the ingress: revocation wins, then the DM allowlist.
      ## A profile that cannot be read fails closed.
      try:
        if gatewayInboundMemory.isRevoked(userId):
          avRevoked
        elif cfg.dmPolicy != DmPolicyOpen and
             not gatewayInboundMemory.isDmAllowed(userId):
          avNotAllowed
        else:
          avAllowed
      except Exception:
        avRevoked
  try:
    startIpcServer(sockPath, ipcStatusFn, ipcLogFn)
    log.info("IPC socket: " & sockPath)
  except CatchableError as e:
    log.warn("IPC socket disabled: " & e.msg)
  let httpPort = resolveGatewayPort(getEnv("DONKEY_HTTP_PORT"))
  initLock(gSessionsLock)
  publishSessions(runtime.sm)
  let gwStatusFn: GatewayStatusFn = proc(): DaemonStatus {.gcsafe.} =
    ipcStatusFn()
  let gwLogFn: GatewayLogFn = proc(n: int): seq[IpcLogEntry] {.gcsafe.} =
    ipcLogFn(n)
  let gwEventFn: GatewayEventFn = proc(n: int): seq[AgentEvent] {.gcsafe.} =
    agentEventSnapshot(n)
  let gwSessionsFn: GatewaySessionsFn = proc(): seq[SessionDetail] {.gcsafe.} =
    sessionsSnapshot()
  let gwProvidersFn: GatewayProvidersFn = proc(): string {.gcsafe.} =
    buildProvidersJson(
      detectProviderAvailability(),
      withRouteLock(runtime.currentProviderCooldowns()),
      aggregateProviderFeedback(withRouteLock(runtime.currentRouteFeedback())))
  let gwSessionActionFn: GatewaySessionActionFn =
    proc(rawUserId: string; taskKind: TaskKind;
         payload: string): GatewaySessionActionOutcome {.gcsafe.} =
      ## The dashboard carries the raw session key; it is never run through
      ## `apiUserId`. An unknown key is a 404, a revoked profile a 403
      ## (`isRevoked` already answers "revoked" when the profile is unreadable).
      ## The action takes the raw **user key** (the second column of the
      ## dashboard table), not the session id: accepting both made a user key
      ## that equals another session's id resolve to the wrong session.
      if rawUserId notin runtime.sm.entries:
        return gsaoNotFound
      let sessionKey = rawUserId
      let uid = UserId(sessionKey)
      ## Same policy as the API: revocation first, then the DM allowlist. A
      ## policy denial must not answer 202 for a task the ingress will drop.
      case gwAuthorizeFn(uid)
      of avAllowed: discard
      of avRevoked, avNotAllowed: return gsaoRevoked
      ## Answer on the channel the user actually uses. Passing the session key
      ## as a `ckCli` channel id recorded a fake channel and sent the
      ## confirmation to stdout.
      let target = runtime.sm.latestChannelFor(sessionKey)
      ensureSessionTask(
        runtime.sm,
        InboundMessage(
          userId: uid,
          channel: target.kind,
          channelId: target.rawId,
          rawChannelId: target.rawId,
        ),
        buildDaemonSessionServices(gatewayInboundCtx, cfg, gatewayInboundMemory,
                                   gatewayInboundLog),
        runtime.msgSeq,
        taskKind,
        payload,
      )
      gsaoAccepted
  let httpBind = block:
    let raw = getEnv("DONKEY_HTTP_BIND").strip()
    if raw.len > 0: raw else: "127.0.0.1"
  let httpToken = getEnv("DONKEY_HTTP_TOKEN").strip()
  let httpAllowInsecure = getEnv("DONKEY_HTTP_ALLOW_INSECURE").strip() == "1"
  if httpPort > 0:
    if not gatewayBindIsAllowed(httpBind, httpToken, httpAllowInsecure):
      log.error("HTTP gateway disabled: non-loopback bind (" & httpBind &
                ") requires DONKEY_HTTP_TOKEN and DONKEY_HTTP_ALLOW_INSECURE=1")
    else:
      let gwChatBridge = block:
        {.cast(gcsafe).}: gApiChatBridge
      let gatewayStart = startHttpGateway(httpPort, gwStatusFn, gwLogFn, gwEventFn, gwInboundFn,
                                          bindAddr = httpBind, authToken = httpToken,
                                          agentDispatchFn = gwInboundFn,
                                          agentStreamNapFn = apiChatNap,
                                          sessionsFn = gwSessionsFn,
                                          providersFn = gwProvidersFn,
                                          sessionActionFn = gwSessionActionFn,
                                          authorizeFn = gwAuthorizeFn,
                                          chatBridge = gwChatBridge,
                                          modelName = cfg.defaultModel)
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

when defined(posix):
  const
    PosixODirectory = cint(0o200000)
    PosixONoFollow = cint(0o400000)

proc ensurePrivateDir(path: string): Result[void, string]
                                      {.gcsafe, raises: [].} =
  ## Creates or validates a real directory with 0700 permissions. The final
  ## component is opened with O_NOFOLLOW so a symlink cannot redirect chmod or
  ## the child paddock creation.
  if path.len == 0:
    return err("empty subagent paddock path")
  when defined(posix):
    if posix.mkdir(path.cstring, Mode(0o700)) != 0 and
       osLastError() != OSErrorCode(posix.EEXIST):
      return err("mkdir subagent paddock: " & osErrorMsg(osLastError()))
    let fd = posix.open(path.cstring,
                        O_RDONLY or PosixODirectory or PosixONoFollow)
    if fd < 0:
      return err("open subagent paddock: " & osErrorMsg(osLastError()))
    defer: discard posix.close(fd)
    if posix.fchmod(fd, Mode(0o700)) != 0:
      return err("chmod subagent paddock: " & osErrorMsg(osLastError()))
    ok()
  else:
    try:
      createDir(path)
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})
      ok()
    except CatchableError as e:
      err("create subagent paddock: " & e.msg)

proc createSubagentPaddock(root, subagentId: string):
                           Result[string, string] {.gcsafe, raises: [].} =
  let subagentsRoot = root / "subagents"
  ?ensurePrivateDir(subagentsRoot)
  let childDir = subagentsRoot / subagentId
  ?ensurePrivateDir(childDir)
  ok(childDir)

proc removeSubagentPaddock(path: string): Result[void, string]
                                           {.gcsafe, raises: [].} =
  if path.len == 0:
    return ok()
  try:
    if symlinkExists(path):
      removeFile(path)
    elif dirExists(path):
      removeDir(path)
    ok()
  except CatchableError as e:
    err("remove subagent paddock: " & e.msg)

proc subagentWorkspacePort*(): SubagentWorkspacePort =
  SubagentWorkspacePort(
    create: createSubagentPaddock,
    remove: removeSubagentPaddock,
  )

func buildDaemonSessionServices(ctx: DaemonContext;
                                cfg: DonkeyConfig;
                                memory: MdFileAdapter;
                                log: Logger): SessionIngressServices =
  buildSessionIngressServices(
    memory.toRuntimePort(),
    cfg,
    ctx.services.globalCompleteFn,
    ctx.services.globalStreamFn,
    ctx.services.toolClients,
    ctx.services.tools,
    ctx.runtime.globalOutbox,
    log,
    cfg.sandboxMode,
    cfg.sandboxRuntimeCmd,
    cfg.sandboxImage,
    nil,
    ctx.services.globalSearchFn,
    proc(userId: UserId): bool = memory.isRevoked(userId),
    proc(userId: UserId): bool = memory.isDmAllowed(userId),
    cfg.dmPolicy,
    newStdHttpAdapter(allowlist = cfg.webAllowlist,
                      proxy = getEnv("DONKEY_WEB_PROXY").strip()).toRuntimePort(),
    buildProviderBundle,
    buildDenoSkillRuntime,
    buildSkillRuntimePolicyResolver(cfg),
    routeRecordHook = proc(selection: ProviderSelection) {.gcsafe.} =
      withRouteLock(ctx.runtime.recordRouteChoice(selection)),
    routeResultHook = proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.} =
      withRouteLock(ctx.runtime.recordRouteResult(selection, elapsedMs, ok)),
    routeFeedbackHook = proc(): seq[RouteFeedback] {.gcsafe.} =
      withRouteLock(ctx.runtime.currentRouteFeedback()),
    routeCostHook = proc(): seq[RouteCostHint] {.gcsafe.} =
      loadRouteCostHints(routeCostProviderIds()),
    routeProviderCooldownHook = proc(): seq[ProviderCooldown] {.gcsafe.} =
      withRouteLock(ctx.runtime.currentProviderCooldowns()),
    subagentWorkspace = subagentWorkspacePort(),
    fs = newFsAdapter(),
  )

proc handleDaemonSessionFallback(runtime:  var DaemonRuntime;
                                  msg:      InboundMessage;
                                  services: SessionIngressServices) =
  handleSessionFallback(runtime.sm, runtime.msgSeq, msg, services)

func inboundStatusMessageId(msg: InboundMessage): string =
  if msg.messageId.len > 0: msg.messageId else: msg.channelId

func shouldStageInboundReaction(msg: InboundMessage): bool =
  supportsMessageReactions(msg.channel) and
    msg.callbackId.len == 0 and
    inboundStatusMessageId(msg).len > 0

proc stageInboundReactionStatus(runtime: var DaemonRuntime;
                                outboundPorts: OutboundChannelPorts;
                                msg: InboundMessage) =
  if not shouldStageInboundReaction(msg):
    return
  let statusMsgId = inboundStatusMessageId(msg)
  discard setOutboundReaction(msg.channel, msg.userId, msg.channelId, statusMsgId, "⏳", outboundPorts, newLogger("status.reaction"))
  runtime.presentationState.rememberStatus(msg.channel, msg.userId, "turn", statusMsgId, msg.channelId)

proc completeInboundReactionStatus(runtime: var DaemonRuntime;
                                   outboundPorts: OutboundChannelPorts;
                                   channel: ChannelKind;
                                   userId: UserId;
                                   channelId, msgId: string;
                                   isError: bool) =
  if not supportsMessageReactions(channel) or msgId.len == 0:
    return
  runtime.presentationState.clearStatus(channel, userId, "turn")
  let finalEmoji = if isError: "❌" else: "✅"
  discard setOutboundReaction(channel, userId, channelId, msgId, finalEmoji, outboundPorts, newLogger("status.reaction"))

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
                         log:          Logger): bool =
  let completeBuilder = makeCompleteBuilder()
  let modelCatalogLoader = buildModelCatalogLoader()
  let runtimePtr = addr runtime
  var tgMsgs = tgAdapter.receive().valueOr:
    log.error("telegram receive: " & error)
    return false

  for msg in tgMsgs.mitems:
    let auth = authorizeResolvedInbound(
      runtime.sm, tgAdapter.resolver.identityGate(), ckTelegram,
      msg.userId, msg.text)
    if not auth.allowed:
      log.warn("telegram: unauthorized message from " & $msg.userId)
      continue

    let stagedReaction = shouldStageInboundReaction(msg)
    if stagedReaction:
      tgAdapter.sendTyping(msg.userId).isOkOr:
        log.warn("tg sendTyping (staged) failed for user=" & $msg.userId & " reason=" & error)
      stageInboundReactionStatus(runtime, outboundPorts, msg)
    
    # Download media if present
    processInboundMediaDownload(msg, outboundPorts.telegram,
                                memory.paddockDir(msg.userId), log)
    
    if telegram_runtime.handleTelegramMessage(
      msg, runtime.sm, tgAdapter, runtime.presentationState, memory, completeBuilder,
      modelCatalogLoader,
      services.toolClients.len, services.tools.len + nativeSessionTools().len, runtime.msgSeq, runtime.daemonStartMs, log,
      proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} =
        ensureSessionTask(runtimePtr[].sm, msg, services, runtimePtr[].msgSeq, taskKind, payload)):
      if stagedReaction:
        completeInboundReactionStatus(runtime, outboundPorts, msg.channel, msg.userId, msg.channelId, inboundStatusMessageId(msg), false)
    else:
      handleTelegramFallback(runtime, msg, services)
  true

proc publishDueReminders(runtime: var DaemonRuntime;
                         memory:  MdFileAdapter;
                         log:     Logger) =
  if nowMs() - runtime.lastReminderCheckMs < 30_000:
    return

  runtime.lastReminderCheckMs = nowMs()
  let dueReminders = memory.loadDueReminders()
  for rem in dueReminders:
    let rUid = UserId(rem["userId"].getStr())
    let rCh  = block:
      var found = ckTelegram
      for ck in ChannelKind:
        if $ck == rem["channel"].getStr(): found = ck; break
      found
    let rId = rem["id"].getStr()
    runtime.globalOutbox.putNoWait(OutboundMessage(
      userId:  rUid,
      channel: rCh,
      text:    "⏰ " & rem["message"].getStr(),
    ))
    memory.deleteReminder(rUid, rId)
    log.info("reminder fired " & $rUid)

proc completeInboundReactionStatus(runtime:   var DaemonRuntime;
                                   outboundPorts: OutboundChannelPorts;
                                   outMsg:    OutboundMessage) =
  let msgId = runtime.presentationState.lookupStatus(outMsg.channel, outMsg.userId, "turn")
  if not supportsMessageReactions(outMsg.channel) or outMsg.isPartial or msgId.len == 0:
    return

  let channelId = runtime.presentationState.lookupStatusChannelId(outMsg.channel, outMsg.userId, "turn")
  let isError = outMsg.text.startsWith("Desculpe") or
                outMsg.text.startsWith("Tool call loop")
  completeInboundReactionStatus(runtime, outboundPorts, outMsg.channel, outMsg.userId, channelId, msgId, isError)

proc drainGlobalOutbox(runtime:  var DaemonRuntime;
                       adapters: var DaemonAdapters;
                       log:      Logger) =
  let outboundPorts = buildRuntimeOutboundPorts(adapters)
  while runtime.globalOutbox.len > 0:
    let outMsg = runtime.globalOutbox.getNoWait()
    {.cast(gcsafe).}:
      if isApiChatReply(outMsg):
        ## API replies belong to a waiting HTTP turn, never to a channel port.
        ## A reply without a turn token (a scheduled firing for an `api:` user,
        ## for example) must not close an unrelated HTTP request.
        if outMsg.bridgeToken == 0:
          log.warn("dropping an API reply without a turn token for " &
                   $outMsg.userId)
          continue
        if gApiChatBridge != nil:
          discard gApiChatBridge.deliver(outMsg, outMsg.bridgeToken)
        continue
    completeInboundReactionStatus(runtime, outboundPorts, outMsg)
    routeOutbound(outMsg, outboundPorts, log, runtime.presentationState, runtime.ledger)

proc startDaemonIngress(ctx: DaemonContext;
                        log: Logger) =
  startOptionalDiscordGateway(ctx.adapters.dc, ctx.env.discordToken, ctx.env.discordGuildId, log)
  startOptionalWeComGateway(ctx.adapters.wc, ctx.env.wecomCorpId, log)
  startOptionalWeChatGateway(ctx.adapters.wch, ctx.env.wechatAppId, log)
  startOptionalFeishuGateway(ctx.adapters.fs, ctx.env.feishuAppId, log)
  startOptionalSlackGateway(ctx.adapters.sl, ctx.env.slackBotToken,
                            ctx.env.slackAppToken,
                            newStdHttpAdapter(timeout = 15, maxRetries = 2,
                                              circuitBreaker = false).toRuntimePort(),
                            log)
  startOptionalDingTalkGateway(ctx.adapters.dt, ctx.env.dingTalkAppKey, log)
  startOptionalMatrixGateway(ctx.adapters.mx, log)
  startOptionalWhatsAppGateway(ctx.adapters.wa, ctx.env.whatsappAccessToken,
                               ctx.env.whatsappPhoneNumberId, log)
  ## The LINE route can enqueue as soon as the receiver binds; the queue must
  ## be open first (an unopened Channel cannot be sent to from a worker).
  if ctx.env.lineChannelAccessToken.len > 0:
    ctx.adapters.ln.openQueue()
    log.info("LINE webhook queue started")
  startOptionalWebhookReceiver(ctx.env, log)
  startOptionalQQGateway(ctx.adapters.qq, log)
  if ctx.env.telegramToken.len > 0:
    log.info("Telegram bot starting (token len=" & $ctx.env.telegramToken.len & ")")
    ctx.adapters.tg.registerBotCommands().isOkOr:
      log.warn("Telegram registerBotCommands failed: " & error)
    log.info("Telegram bot started, polling active")

proc setupDaemonRuntime(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  setupIpcServer(cfg, ctx.runtime, ctx.runtime.sm, ctx.services.tools.len + nativeSessionTools().len, ctx.runtime.daemonStartMs,
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
  let modelCatalogLoader = buildModelCatalogLoader()
  let toolsCount = ctx.services.tools.len + nativeSessionTools().len
  let toolClientsCount = ctx.services.toolClients.len
  let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
  let fallback = proc(msg: InboundMessage) {.gcsafe.} =
    handleGatewayFallback(ctx, cfg, memory, msg, log)
  let cmdEnv = CommandEnv(
    memory: memory, completeBuilder: completeBuilder,
    modelCatalogLoader: modelCatalogLoader, toolsCount: toolsCount,
    toolClientsCount: toolClientsCount, daemonStartMs: ctx.runtime.daemonStartMs)

  initGatewayDrainer(
    drainDiscord = proc(): bool =
      drainDiscordGateway(ctx.env.discordToken.len > 0, proc(): bool =
        discord_runtime.drainDiscordEvents(
          ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState, cmdEnv,
          ctx.runtime.msgSeq, log,
          proc(msg: InboundMessage) =
            stageInboundReactionStatus(ctx.runtime, outboundPorts, msg),
          proc(msg: InboundMessage) =
            completeInboundReactionStatus(ctx.runtime, outboundPorts, msg.channel, msg.userId,
              msg.channelId, inboundStatusMessageId(msg), false),
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
        matrixConfigured(),
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
      drainTelegramEvents(ctx.runtime, ctx.adapters.tg, outboundPorts, services, memory, log),
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
      if gEmailPollInFlight:
        let (hasResult, polled) = gEmailPollCh.tryRecv()
        if hasResult:
          gEmailPollInFlight = false
          joinThread(gEmailPollThread)
          if polled.isErr:
            log.warn("email poll: " & polled.error)
            return false
          for msg in polled.value:
            fallback(msg)
          return polled.value.len > 0
        return false
      let now = nowMs()
      if now - ctx.runtime.lastEmailPollMs < EmailPollIntervalMs:
        return false
      ctx.runtime.lastEmailPollMs = now
      if not gEmailPollOpened:
        gEmailPollCh.open(1)
        gEmailPollOpened = true
      gEmailPollInFlight = true
      createThread(gEmailPollThread, emailPollThread, addr ctx.adapters.em)
      false,
    drainSignal = proc(): bool =
      if ctx.adapters.signal.account.len == 0:
        return false
      if gSignalPollInFlight:
        let (hasResult, polled) = gSignalPollCh.tryRecv()
        if hasResult:
          gSignalPollInFlight = false
          joinThread(gSignalPollThread)
          if polled.isErr:
            log.warn("signal poll: " & polled.error)
            return false
          for msg in polled.value:
            fallback(msg)
          return polled.value.len > 0
        return false
      let now = nowMs()
      if now - ctx.runtime.lastSignalPollMs < SignalPollIntervalMs:
        return false
      ctx.runtime.lastSignalPollMs = now
      if not gSignalPollOpened:
        gSignalPollCh.open(1)
        gSignalPollOpened = true
      gSignalPollInFlight = true
      createThread(gSignalPollThread, signalPollThread, addr ctx.adapters.signal)
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
  publishSessions(ctx.runtime.sm)
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
  {.cast(gcsafe).}:
    initMetrics()
    startOptionalMetricsServer(log)

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
  {.cast(gcsafe).}:
    gApiChatBridge = newChatBridge(apiChatNowMs, apiChatNap)
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
  ctx.runtime.sm.configureDmPolicy(
    cfg.dmPolicy,
    proc(userId: UserId): bool {.gcsafe.} = memory.isDmAllowed(userId))
  ctx.runtime.sm.configureGroupGate(GroupGate(
    allowedChats: parseChatIdList(getEnv(EnvTelegramAllowedGroups))))
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

  ## Heartbeat: periodic maintenance (reminder delivery, etc.)
  var hbReg = newHeartbeatRegistry()
  if ctx.services.browserRuntime != nil:
    let browserRuntime = ctx.services.browserRuntime
    ## Independent of DONKEY_HEARTBEAT_CRON: idle browsers must be reaped
    ## within a bounded time even if the main heartbeat runs daily.
    startPeriodicTask(proc() {.gcsafe.} = browserRuntime.evictIdle(),
                      intervalSec = 60, name = "browser-idle")
  if ctx.runtime.stateStore != nil:
    let compactionSec = ctx.runtime.stateStore.ledgerCompactIntervalSec()
    if compactionSec > 0:
      let workerRes = startLedgerCompactionWorker(
        addr ctx.runtime.stateStore, max(1.0, compactionSec))
      if workerRes.isErr:
        log.warn("ledger compaction worker: " & workerRes.error)
      else:
        ctx.runtime.ledgerWorker = workerRes.get()
  let memPort = memory.toRuntimePort()
  let reminderOutboxFn: ReminderOutboxFn = proc(userId, channel, message: string) {.gcsafe.} =
    let uid = UserId(userId)
    ctx.runtime.globalOutbox.putNoWait(OutboundMessage(
      userId:  uid,
      channel: parseEnum[ChannelKind](channel, ckTelegram),
      text:    message,
    ))
  hbReg.registerTask("reminders", proc() {.gcsafe.} =
    deliverDueReminders(memPort, reminderOutboxFn))
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
    deliverHeartbeats(cfg.paddocks, heartbeatOutboxFn))
  let hbCronExpr = getEnv("DONKEY_HEARTBEAT_CRON").strip()
  if hbCronExpr.len > 0:
    let hbCronStart = startHeartbeatCron(hbReg, hbCronExpr)
    if hbCronStart.isErr:
      log.error("heartbeat cron: " & hbCronStart.error)
      quit(1)
    log.info("heartbeat cron: " & hbCronExpr)
  else:
    let hbIntervalStr = getEnv("DONKEY_HEARTBEAT_SEC")
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
        gcsafe, raises: [], noSideEffect.} = getEnv(name)
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
    let modelCatalogLoader = buildModelCatalogLoader()
    let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
    discord_runtime.checkDiscordOfflineMessages(
      ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState,
      CommandEnv(memory: memory, completeBuilder: completeBuilder,
                 modelCatalogLoader: modelCatalogLoader,
                 toolsCount: ctx.services.tools.len + nativeSessionTools().len,
                 toolClientsCount: ctx.services.toolClients.len,
                 daemonStartMs: ctx.runtime.daemonStartMs),
      ctx.runtime.msgSeq, log,
      proc(msg: InboundMessage) {.gcsafe.} =
        stageInboundReactionStatus(ctx.runtime, outboundPorts, msg),
      proc(msg: InboundMessage) {.gcsafe.} =
        completeInboundReactionStatus(ctx.runtime, outboundPorts, msg.channel, msg.userId,
          msg.channelId, inboundStatusMessageId(msg), false),
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
    stopLedgerCompactionWorker(ctx.runtime.ledgerWorker)
    stopSlackSocketMode()
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
    quit(runSandboxWorker(args[1], args[2]))

  # setup doesn't need config — handle it early
  if args.len >= 1 and args[0] == "setup":
    runSetupWizard(resolveHome())
    quit(0)

  if configPath.len == 0:
    configPath = getConfigDir() / ConfigDirName / ConfigFileName

  let home = resolveHome()

  ## Load .env file if present — checks {home}/donkey.env then ~/.config/donkey/donkey.env
  discard loadDonkeyEnv(home)

  var cfg = loadConfig(configPath)
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
      cfg = loadConfig(configPath)
  configureApprovalServiceFromEnv(
    newApprovalStore(cfg.home / "state" / "approvals.json").toApprovalPort())

  let sandboxPolicy = validateSandboxPolicy(cfg, devMode)
  if sandboxPolicy.isErr:
    stderr.writeLine sandboxPolicy.error
    stderr.writeLine "Use --dev-mode only for local development, or tighten the [sandbox] policy in donkey.toml"
    quit(1)
  let sandboxAvailability = sandboxAvailabilityResult(cfg)
  if not devMode and sandboxAvailability.isErr:
    stderr.writeLine "Security Error: " & sandboxAvailability.error
    stderr.writeLine "Install the configured sandbox runtime, or switch to a supported [sandbox] mode before starting in production"
    quit(1)
  let paddockOwnership = validatePaddockOwnership(cfg, devMode)
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
      runSetupWizard(resolveHome()); 0,
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
      dispatchService(a, logsFollow),
    context: ccNone, description: "Systemd --user service management"))
  cmdReg.register(CommandEntry(
    name: "tui", minArgs: 1,
    handler: proc(a: seq[string]): int =
      dispatchTui(cfg.home / SockFileName),
    context: ccConfigLoaded, description: "Open live TUI dashboard"))
  cmdReg.register(CommandEntry(
    name: "doctor", minArgs: 1,
    handler: proc(a: seq[string]): int =
      runDoctor(cfg, devMode),
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
