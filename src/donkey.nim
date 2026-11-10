## donkey — AI agent system entry point.

import std/[algorithm, json, os, parseopt, strutils, tables, terminal, times]
import locks
import chronos
import chronos/asyncsync
import chronos/timer as ctimer
import donkey/config/loader
import donkey/config/types
import donkey/core/security/dm_policy
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
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/cli_repl
import donkey/adapters/webhook/webhook_receiver
import donkey/adapters/tool/mcp_client
import donkey/adapters/state/runtime_store
import donkey/domain/message
import donkey/domain/agent_message
import donkey/ports/provider
import donkey/ports/channel
import donkey/core/media_download
import donkey/ports/tool
import donkey/ports/runtime_state
import donkey/app/orchestrator
import donkey/app/sandbox
import donkey/app/ipc_server
import donkey/app/http_gateway
import donkey/app/heartbeat
import donkey/app/metrics_server
import donkey/app/outbound_runtime
import donkey/app/gateway_drainer
import donkey/app/session_manager
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
  tg[] = newTelegramAdapter(token, identityPath, pollTimeout = 0)
  result = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].} =
    if channel == ckTelegram:
      try:
        tg[].sendTyping(userId).isOkOr:
          log.warn("tg sendTyping failed for user=" & $userId & " reason=" & error)
      except CatchableError: discard

type DaemonToolBundle = object
  clients: seq[ToolRuntimePort]
  tools:   seq[ToolDescription]

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
  slackSigningSecret: string
  feishuVerificationToken: string
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
    addr adapters.cli, signalPtr)

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
  ledger:               DeliveryLedgerPort
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
  msgSeq:               int
  daemonStartMs:        int64
  downloadDir:          string  ## directory for downloaded files from channels

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

proc loadDaemonToolBundle(cfg: DonkeyConfig): DaemonToolBundle =
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

proc makeProviderFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

proc buildGlobalProviderBundle(): GlobalProviderBundle =
  let orKey = getEnv("OPENROUTER_API_KEY")
  let orAdapter = newOpenRouterAdapter(orKey)
  result.completeFn = if orKey.len > 0: makeProviderFn(orAdapter) else: nil
  result.streamFn = if orKey.len > 0: orAdapter.makeStreamFn() else: nil

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
  let toolBundle = loadDaemonToolBundle(cfg)
  result.toolClients = toolBundle.clients
  result.tools = toolBundle.tools

  let providerBundle = buildGlobalProviderBundle()
  result.globalCompleteFn = providerBundle.completeFn
  result.globalStreamFn = providerBundle.streamFn
  result.tgTypingFn = makeTgTypingFn(env.telegramToken, env.identityPath, log)
  result.globalSearchFn = buildGlobalSearchFn(env.memory)
  when defined(withPostgres) or defined(withSqlite):
    if result.globalSearchFn != nil:
      log.info("MAGMA semantic search enabled")

proc loadDaemonEnv(cfg: DonkeyConfig; log: Logger): DaemonEnv =
  result.telegramToken = getEnv("TELEGRAM_BOT_TOKEN")
  if result.telegramToken.len == 0:
    log.error("TELEGRAM_BOT_TOKEN not set")
    quit(1)

  result.discordToken = getEnv("DISCORD_BOT_TOKEN")
  result.discordGuildId = getEnv("DISCORD_GUILD_ID")
  result.wecomCorpId = getEnv("WECOM_CORP_ID")
  result.wechatAppId = getEnv("WECHAT_APP_ID")
  result.feishuAppId = getEnv("FEISHU_APP_ID")
  result.slackBotToken = getEnv("SLACK_BOT_TOKEN")
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
  result.slackSigningSecret = getEnv("SLACK_SIGNING_SECRET")
  result.feishuVerificationToken = getEnv("FEISHU_VERIFICATION_TOKEN")
  result.matrixWebhookToken = getEnv("MATRIX_WEBHOOK_TOKEN")
  result.whatsappVerifyToken = getEnv("WHATSAPP_VERIFY_TOKEN")
  result.whatsappAppSecret = getEnv("WHATSAPP_APP_SECRET")

proc initDaemonAdapters(env: DaemonEnv): DaemonAdapters =
  result.tg = newTelegramAdapter(env.telegramToken, env.identityPath, pollTimeout = 0)
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

proc initDaemonRuntime(home: string): DaemonRuntime =
  new(result)
  if not gRoutingLockReady:
    initLock(gRoutingLock)
    gRoutingLockReady = true
  result.globalOutbox = newAsyncQueue[OutboundMessage]()
  result.sm.init()
  let stateStore = newRuntimeStateStore(home / "state")
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
                               log: Logger) =
  if slackBotToken.len == 0:
    log.info("SLACK_BOT_TOKEN not set — Slack disabled")
    return

  slAdapter.openQueue()
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
    log.info("DONKEY_WEBHOOK_PORT not set — HTTP webhook receiver disabled")
    return

  let cfg = WebhookConfig(
    slackSigningSecret:
      if env.slackBotToken.len > 0: env.slackSigningSecret else: "",
    feishuVerificationToken:
      if env.feishuAppId.len > 0: env.feishuVerificationToken else: "",
    dingtalkAppSecret:
      if env.dingTalkAppKey.len > 0: env.dingTalkAppSecret else: "",
    matrixToken:
      if matrixConfigured(): env.matrixWebhookToken else: "",
    whatsappVerifyToken:
      if env.whatsappAccessToken.len > 0 and env.whatsappPhoneNumberId.len > 0:
        env.whatsappVerifyToken
      else: "",
    whatsappAppSecret:
      if env.whatsappVerifyToken.len > 0: env.whatsappAppSecret else: "",
  )
  startWebhookReceiver(cfg, env.webhookPort, env.webhookHost, log).isOkOr:
    log.error("webhook receiver: " & error)
    return
  log.info("webhook receiver started on " & env.webhookHost & ":" & $env.webhookPort)

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
    qqAdapter.startWebhook(oneBotPort, log)
    log.info("QQ OneBot webhook listener started on port " & $oneBotPort)
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

# Forward declaration for handleGatewayFallback (defined later, used in setupIpcServer)
proc handleGatewayFallback(ctx: DaemonContext; cfg: DonkeyConfig;
                          memory: MdFileAdapter; msg: InboundMessage;
                          log: Logger) {.gcsafe.}

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
  try:
    startIpcServer(sockPath, ipcStatusFn, ipcLogFn)
    log.info("IPC socket: " & sockPath)
  except CatchableError as e:
    log.warn("IPC socket disabled: " & e.msg)
  let httpPort = resolveGatewayPort(getEnv("DONKEY_HTTP_PORT"))
  let gwStatusFn: GatewayStatusFn = proc(): DaemonStatus {.gcsafe.} =
    ipcStatusFn()
  let gwLogFn: GatewayLogFn = proc(n: int): seq[IpcLogEntry] {.gcsafe.} =
    ipcLogFn(n)
  let gwEventFn: GatewayEventFn = proc(n: int): seq[AgentEvent] {.gcsafe.} =
    agentEventSnapshot(n)
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
      startHttpGateway(httpPort, gwStatusFn, gwLogFn, gwEventFn, gwInboundFn,
                       bindAddr = httpBind, authToken = httpToken)
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
    newStdHttpAdapter(allowlist = cfg.webAllowlist).toRuntimePort(),
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
      loadRouteCostHints(@["openrouter", "groq", "anthropic", "zai-anthropic", "gemini",
                           "minimax", "zai", "zai-coding", "zen"]),
    routeProviderCooldownHook = proc(): seq[ProviderCooldown] {.gcsafe.} =
      withRouteLock(ctx.runtime.currentProviderCooldowns()),
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

proc processInboundMediaDownload(runtime: var DaemonRuntime;
                                 msg: InboundMessage;
                                 channelPort: OutboundChannelPort;
                                 log: Logger) =
  ## Downloads and saves files from inbound messages if mediaUrl is present.
  ## Uses the channel port interface - respects hexagonal architecture.
  if msg.mediaUrl.len == 0:
    return
  
  # Create download directory if it doesn't exist
  if runtime.downloadDir.len == 0:
    runtime.downloadDir = getAppDir() / "downloads"
  
  let userDir = runtime.downloadDir / $msg.userId
  if not dirExists(userDir):
    createDir(userDir)
  
  # Try to download file using the port interface
  # The fileId format is channel-specific:
  #   Telegram: file_id
  #   WhatsApp: mediaId
  #   Discord: HTTP URL (already resolved)
  let fileId = msg.mediaUrl
  
  let downloadResult = channelPort.downloadFile(fileId)
  if downloadResult.isOk:
    var fileDownload = downloadResult.value
    
    # Save to disk using generic media_download helper
    let saveResult = fileDownload.saveFileToDisk(userDir)
    if saveResult.isOk:
      log.info($msg.channel & ": downloaded file " & fileDownload.fileName & " -> " & saveResult.value)
    else:
      log.warn($msg.channel & ": failed to save file: " & saveResult.error)
  else:
    # Not an error - some channels don't support downloadFile
    # Just log for debugging
    log.debug($msg.channel & ": downloadFile not available for " & fileId)

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
  let tgMsgs = tgAdapter.receive().valueOr:
    log.error("telegram receive: " & error)
    return false

  for msg in tgMsgs:
    if not runtime.sm.allows(msg.userId):
      log.warn("telegram: unauthorized message from " & $msg.userId)
      continue

    let stagedReaction = shouldStageInboundReaction(msg)
    if stagedReaction:
      tgAdapter.sendTyping(msg.userId).isOkOr:
        log.warn("tg sendTyping (staged) failed for user=" & $msg.userId & " reason=" & error)
      stageInboundReactionStatus(runtime, outboundPorts, msg)
    
    # Download media if present
    processInboundMediaDownload(runtime, msg, outboundPorts.telegram, log)
    
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
    completeInboundReactionStatus(runtime, outboundPorts, outMsg)
    routeOutbound(outMsg, outboundPorts, log, runtime.presentationState, runtime.ledger)

proc startDaemonIngress(ctx: DaemonContext;
                        log: Logger) =
  startOptionalDiscordGateway(ctx.adapters.dc, ctx.env.discordToken, ctx.env.discordGuildId, log)
  startOptionalWeComGateway(ctx.adapters.wc, ctx.env.wecomCorpId, log)
  startOptionalWeChatGateway(ctx.adapters.wch, ctx.env.wechatAppId, log)
  startOptionalFeishuGateway(ctx.adapters.fs, ctx.env.feishuAppId, log)
  startOptionalSlackGateway(ctx.adapters.sl, ctx.env.slackBotToken, log)
  startOptionalDingTalkGateway(ctx.adapters.dt, ctx.env.dingTalkAppKey, log)
  startOptionalMatrixGateway(ctx.adapters.mx, log)
  startOptionalWhatsAppGateway(ctx.adapters.wa, ctx.env.whatsappAccessToken,
                               ctx.env.whatsappPhoneNumberId, log)
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
                 ctx.env.wechatAppId, ctx.env.feishuAppId, ctx.adapters.qq.enabled(), log,
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
  processInboundMediaDownload(
    ctx.runtime,
    msg,
    outboundPortForChannel(outboundPorts, msg.channel),
    log,
  )
  handleDaemonSessionFallback(
    ctx.runtime,
    msg,
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
  let isAuthorized = proc(userId: UserId): bool {.gcsafe.} =
    ctx.runtime.sm.allows(userId)

  initGatewayDrainer(
    drainDiscord = proc(): bool =
      drainDiscordGateway(ctx.env.discordToken.len > 0, proc(): bool =
        discord_runtime.drainDiscordEvents(
          ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState, memory, completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount, ctx.runtime.daemonStartMs,
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
          ctx.adapters.wc, ctx.env.wecomCorpId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount, ctx.runtime.daemonStartMs,
          ctx.runtime.msgSeq, log, fallback)
        true
      ),
    drainWeChat = proc(): bool =
      drainWeChatGateway(ctx.env.wechatAppId.len > 0, proc(): bool =
        wechat_runtime.drainWeChatEvents(
          ctx.adapters.wch, ctx.env.wechatAppId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount, ctx.runtime.daemonStartMs,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainQQ = proc(): bool =
      drainQQGateway(ctx.adapters.qq.enabled(), proc(): bool =
        qq_runtime.drainQQEvents(
          ctx.adapters.qq, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount, ctx.runtime.daemonStartMs,
          ctx.runtime.msgSeq, fallback, log)
        true
      ),
    drainFeishu = proc(): bool =
      drainFeishuGateway(ctx.env.feishuAppId.len > 0, proc(): bool =
        feishu_runtime.drainFeishuEvents(
          ctx.adapters.fs, ctx.env.feishuAppId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount, ctx.runtime.daemonStartMs,
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
              let userId = ctx.adapters.dt.resolver.resolve(ckDingTalk, event.rawId)
              return (true, InboundMessage(
                userId: userId,
                channel: ckDingTalk,
                channelId: event.messageId,
                messageId: event.messageId,
                text: event.content,
                mediaUrl: event.downloadCode,
              ))
            (hasEvent, event) = ctx.adapters.dt.tryRecvEvent()
          (false, InboundMessage()),
        fallback,
        log,
        isAuthorized
      )
      count > 0,
    drainMatrix = proc(): bool =
      let count = drainMatrixGateway(
        matrixConfigured(),
        proc(): (bool, InboundMessage) =
          var (hasEvent, event) = ctx.adapters.mx.tryRecvEvent()
          while hasEvent:
            if event.content.strip.len > 0 or event.mediaUrl.len > 0:
              let userId = ctx.adapters.mx.resolver.resolve(ckMatrix, event.roomId)
              return (true, InboundMessage(
                userId: userId,
                channel: ckMatrix,
                channelId: event.eventId,
                messageId: event.eventId,
                text: event.content,
                mediaUrl: event.mediaUrl,
              ))
            (hasEvent, event) = ctx.adapters.mx.tryRecvEvent()
          (false, InboundMessage()),
        fallback,
        log,
        isAuthorized
      )
      count > 0,
    drainTelegram = proc(): bool =
      let services =
        buildDaemonSessionServices(ctx, cfg, memory, log) |>->
        withTypingFn(ctx.services.tgTypingFn)
      drainTelegramEvents(ctx.runtime, ctx.adapters.tg, outboundPorts, services, memory, log),
    drainWhatsApp = proc(): bool =
      drainWhatsAppGateway(ctx.env.whatsappAccessToken.len > 0, proc(): bool =
        whatsapp_runtime.drainWhatsAppEvents(
          ctx.adapters.wa, ctx.env.whatsappPhoneNumberId, ctx.runtime.sm, memory,
          completeBuilder, modelCatalogLoader,
          toolsCount, toolClientsCount,
          ctx.runtime.daemonStartMs, ctx.runtime.msgSeq, fallback, log)
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
  let tick = runDaemonTick(ctx, drainer, memory, log)
  DaemonLoopResult(
    sleepMs: if tick.ok: 100 else: 500,
  )

proc startDaemon(cfg: DonkeyConfig; log: Logger) {.async: (raises: [Exception]).} =
  ## Async daemon: Telegram (pollTimeout=0) + Discord (gateway thread) + WeCom (webhook thread).
  ## Loop: drain globalOutbox → drain Discord → drain WeCom → poll Telegram → sleepAsync(100ms)
  if cfg.invalidDmPolicy.len > 0:
    log.error("invalid dm_policy: " & cfg.invalidDmPolicy & " (use open|allowlist)")
    quit(1)
  if cfg.dmPolicy == DmPolicyPairing:
    log.error("dm_policy=pairing is not implemented yet; use open or allowlist")
    quit(1)
  log.info("daemon starting — Telegram + Discord + WeCom")
  {.cast(gcsafe).}:
    initMetrics()
    startOptionalMetricsServer(log)

  let bootstrap = loadDaemonBootstrap(cfg, log)
  let memory = bootstrap.memory
  let ctx = bootstrap.ctx
  ## DM authorization is configured once, before any drainer/actor can consume
  ## an inbound message. Service builders stay side-effect free.
  ctx.runtime.sm.configureDmPolicy(
    cfg.dmPolicy,
    proc(userId: UserId): bool {.gcsafe.} = memory.isDmAllowed(userId))
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

  ## One-time startup: recover messages received while bot was offline.
  block:
    let completeBuilder = makeCompleteBuilder()
    let modelCatalogLoader = buildModelCatalogLoader()
    let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
    discord_runtime.checkDiscordOfflineMessages(
      ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState, memory,
      completeBuilder, modelCatalogLoader,
      ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
      ctx.runtime.msgSeq, log,
      proc(msg: InboundMessage) {.gcsafe.} =
        stageInboundReactionStatus(ctx.runtime, outboundPorts, msg),
      proc(msg: InboundMessage) {.gcsafe.} =
        completeInboundReactionStatus(ctx.runtime, outboundPorts, msg.channel, msg.userId,
          msg.channelId, inboundStatusMessageId(msg), false),
      proc(msg: InboundMessage) {.gcsafe.} =
        handleGatewayFallback(ctx, cfg, memory, msg, log))

  log.info("polling for messages…")
  while true:
    let loopResult = runDaemonLoop(ctx, drainer, memory, log)
    await sleepAsync(ctimer.milliseconds(loopResult.sleepMs.int64))

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

  let cfg = loadConfig(configPath)

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
