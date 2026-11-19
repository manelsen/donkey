## wiring — construction of the daemon's runtime state.
##
## Composition-root code extracted from `src/donkey.nim`; it is not app logic
## and may reference concrete adapters.
##
## Pure wiring: load configuration/env, build ports, adapters and services.
## The daemon loop and dispatch logic stay in the entry point.

import std/[options, os, strutils]
import chronos/asyncsync
import donkey/config/types
import donkey/config/tools_registry
import donkey/config/skills_registry
import donkey/adapters/tool/runtime_builder
import donkey/adapters/tool/mcp_client
import donkey/adapters/tools/browser
import donkey/adapters/memory/md_file
when defined(withPostgres) or defined(withSqlite):
  import donkey/adapters/memory/multigraph_runtime
import donkey/adapters/provider/openrouter
import donkey/adapters/http/std_http
import donkey/adapters/channel/telegram
import donkey/adapters/channel/outbound_builder
import donkey/adapters/channel/discord
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wechat
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/feishu
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/matrix
import donkey/adapters/channel/email
import donkey/adapters/channel/signal
import donkey/adapters/channel/slack
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/line
import donkey/adapters/channel/cli_repl
import donkey/adapters/state/runtime_store
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/dm_policy
import donkey/core/outbound/outbound
import donkey/domain/message
import donkey/domain/providers/descriptors
import donkey/domain/tools/browser_pure
import donkey/ports/channel
import donkey/ports/memory
import donkey/ports/provider
import donkey/ports/tool
import donkey/app/session_manager
import donkey/app/session_ingress
import donkey/app/tool_loop_runtime
import ./daemon_types
import ./route_metrics

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

proc buildRuntimeOutboundPorts*(adapters: var DaemonAdapters): OutboundChannelPorts =
  let signalPtr =
    if adapters.signal.account.len > 0: addr adapters.signal
    else: nil
  buildOutboundPorts(
    addr adapters.tg, addr adapters.dc, addr adapters.wc,
    addr adapters.wch, addr adapters.qq, addr adapters.fs, addr adapters.mx,
    addr adapters.em, addr adapters.sl, addr adapters.dt, addr adapters.wa,
    addr adapters.cli, signalPtr, addr adapters.ln)

proc loadDaemonToolBundle*(cfg: DonkeyConfig; log: Logger): DaemonToolBundle =
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
    ## CDP discovery polls a loopback endpoint while Chromium boots; a shared
    ## circuit breaker would stay open for 60s after three connection refusals
    ## and outlive the 30s discovery deadline.
    let discoveryHttp = newStdHttpAdapter(
      timeout = 2, maxRetries = 1, circuitBreaker = false).toRuntimePort()
    let rawBrowserTimeout = getEnv("DONKEY_BROWSER_TIMEOUT_MS").strip()
    var browserTimeoutMs = BrowserDefaultTimeoutMs
    if rawBrowserTimeout.len > 0:
      try:
        discard parseInt(rawBrowserTimeout)
        browserTimeoutMs = parseBrowserTimeoutMs(rawBrowserTimeout)
      except ValueError:
        log.warn("browser: invalid DONKEY_BROWSER_TIMEOUT_MS='" &
                 rawBrowserTimeout & "'; using " & $BrowserDefaultTimeoutMs)
    let browserRuntime = newBrowserToolRuntime(
      backend = browserBackend,
      executablePath = getEnv("DONKEY_BROWSER_PATH"),
      profileBaseDir = getEnv("DONKEY_BROWSER_PROFILE_DIR"),
      proxyServer = getEnv("DONKEY_BROWSER_PROXY"),
      timeoutMs = browserTimeoutMs,
      http = discoveryHttp,
    )
    result.browserRuntime = browserRuntime
    let browserSchemas = browserRuntime.listTools().valueOr:
      @[]
    for s in browserSchemas:
      result.tools.add(ToolDescription(
        name:        s.name,
        description: s.description,
        schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
      ))
    result.clients.add(browserRuntime.toRuntimePort())

proc makeProviderFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

proc buildGlobalProviderBundle*(): GlobalProviderBundle =
  let openRouter = descriptorOr("openrouter")
  let orKey =
    if openRouter.envNames.len > 0: getEnv(openRouter.envNames[0])
    else: ""
  let orAdapter = newOpenRouterAdapter(orKey)
  result.completeFn = if orKey.len > 0: makeProviderFn(orAdapter) else: nil
  result.streamFn = if orKey.len > 0: orAdapter.makeStreamFn() else: nil

func routeCostProviderIds*(): seq[string] =
  ## Cost hints cover every provider that has a descriptor.
  for descriptor in providerDescriptors():
    result.add descriptor.id

proc buildGlobalSearchFn(memory: MdFileAdapter): SearchFn {.gcsafe.} =
  when defined(withPostgres) or defined(withSqlite):
    result = buildGlobalMagmaSearchFn(memory)
  else:
    discard

func defaultMagmaSqlitePath(home: string): string =
  home / "state" / "magma.sqlite"

func configuredMagmaSqlitePath(home: string): string =
  when defined(withSqlite):
    let configured = getEnv("DONKEY_MAGMA_SQLITE_PATH")
    if configured.len > 0: configured else: defaultMagmaSqlitePath(home)
  else:
    getEnv("DONKEY_MAGMA_SQLITE_PATH")

proc initDaemonServices*(cfg: DonkeyConfig;
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

proc loadDaemonEnv*(cfg: DonkeyConfig; log: Logger): DaemonEnv =
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

proc initDaemonAdapters*(env: DaemonEnv): DaemonAdapters =
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

proc envFloatValue(name: string; default: float): float =
  let raw = getEnv(name).strip()
  if raw.len == 0:
    return default
  try:
    result = parseFloat(raw)
  except ValueError:
    result = default

proc initDaemonRuntime*(home: string): DaemonRuntime =
  new(result)
  initRoutingLock()
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

proc initDaemonContext*(cfg: DonkeyConfig;
                        env: DaemonEnv;
                        log: Logger): DaemonContext =
  new(result)
  result.env = env
  result.adapters = initDaemonAdapters(env)
  result.services = initDaemonServices(cfg, env, log)
  result.runtime = initDaemonRuntime(cfg.home)

proc loadDaemonBootstrap*(cfg: DonkeyConfig;
                          log: Logger): DaemonBootstrap =
  let env = loadDaemonEnv(cfg, log)
  result.memory = env.memory
  result.ctx = initDaemonContext(cfg, env, log)
