## donkey — AI agent system entry point.

import std/[algorithm, json, os, parseopt, strutils, tables, terminal, times]
import chronos
import chronos/asyncsync
import chronos/timer as ctimer
import donkey/config/loader
import donkey/config/types
import donkey/config/dotenv
import donkey/config/tools_registry
import donkey/config/skills_registry
import donkey/config/clawhub_registry
import donkey/adapters/tool/runtime_builder
import donkey/core/log
import donkey/core/pipeops
import donkey/core/reliability
import donkey/core/agent_events
import donkey/core/app_meta
import donkey/core/providers/smart_routing
import donkey/core/session/session_ingress
import donkey/adapters/memory/md_file
when defined(withPostgres) or defined(withSqlite):
  import donkey/app/multigraph_runtime
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
import donkey/adapters/channel/matrix
import donkey/adapters/channel/email
import donkey/adapters/channel/slack
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/cli_repl
import donkey/adapters/tool/mcp_client
import donkey/domain/message
import donkey/domain/agent_message
import donkey/ports/provider
import donkey/ports/channel
import donkey/ports/tool
import donkey/app/orchestrator
import donkey/app/sandbox
import donkey/app/ipc_server
import donkey/app/http_gateway
import donkey/app/heartbeat
import donkey/app/outbound_runtime
import donkey/app/session_manager
import donkey/app/session_state
import donkey/app/session_bootstrap
import donkey/app/doctor
import donkey/app/setup_wizard
import donkey/ports/memory
import donkey/adapters/ipc/types    as ipcTypes
import donkey/adapters/ipc/client   as ipcClient
import donkey/tui/dashboard

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
  doctor                         Check external dependencies (container runtime, pgvector, API keys)
"""

# ── service commands ───────────────────────────────────────────────────────────


const EnvFileTemplate = """# """ & AppName & """ environment — fill in the values you need.
# Permissions: chmod 600 ~/.config/""" & ConfigDirName & "/" & EnvFileName & """

TELEGRAM_BOT_TOKEN=
DISCORD_BOT_TOKEN=
WECOM_CORP_ID=
WECOM_CORP_SECRET=
WECOM_AGENT_ID=
WECOM_CALLBACK_TOKEN=
WECHAT_APP_ID=
WECHAT_APP_SECRET=
WECHAT_CALLBACK_TOKEN=
WECHAT_TEMPLATE_ID=
FEISHU_APP_ID=
FEISHU_APP_SECRET=
FEISHU_VERIFICATION_TOKEN=
QQ_ONEBOT_URL=
QQ_ONEBOT_TOKEN=
QQ_OFFICIAL_APP_ID=
QQ_OFFICIAL_CLIENT_SECRET=
# QQ_OFFICIAL_API_BASE=https://api.sgroup.qq.com
# QQ_OFFICIAL_TOKEN_BASE=https://bots.qq.com

ZAI_API_KEY=
ZAI_CODING_API_KEY=
ZHIPU_API_KEY=
OPENROUTER_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
MINIMAX_API_KEY=
OPENCODE_API_KEY=

BRAVE_API_KEY=
# Recommended PostgreSQL for Multigraph Memory:
#   docker compose up -d postgres
#   if 5432 is busy: DONKEY_PG_PORT=5433 docker compose up -d postgres
# DONKEY_PG_DSN=host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432
# DONKEY_MAGMA_SQLITE_PATH=/path/to/donkey-magma.sqlite
# DONKEY_SQLITE_VEC_PATH=/absolute/path/to/vec0
"""

const TomlTemplate = """# """ & AppName & """ configuration

[""" & ConfigSectionName & """]
# log_level = "info"    # debug | info | warn | error
# log_file  = ""        # leave empty to log to stderr (journald)

[security]
# web_allowlist = ["docs.nim-lang.org", "api.github.com"]
# When non-empty, native web tools and Deno skill --allow-net permissions
# must stay within these public hosts/subdomains.

[sandbox]
# mode  = "none"        # "none", "oci" or "wasm"
# runtime = "docker"    # OCI runtime CLI when mode = "oci"
# image = "alpine"
"""

proc svcUnitDir(): string = getHomeDir() / ".config" / "systemd" / "user"
proc svcUnitFile(): string = svcUnitDir() / ServiceUnitName
proc svcCfgDir(): string  = getHomeDir() / ".config" / ConfigDirName

proc svcRun(cmd: string): bool =
  execShellCmd(cmd) == 0

proc buildServiceFileContent(binPath: string): string =
  ## Generates the systemd unit file pointing at the actual binary path.
  ## nimble build takes effect on next service restart — no reinstall needed.
  "[Unit]\n" &
  "Description=Donkey AI Agent Daemon\n" &
  "After=network.target\n" &
  "Wants=network.target\n" &
  "\n[Service]\n" &
  "Type=simple\n" &
  "EnvironmentFile=" & svcCfgDir() / EnvFileName & "\n" &
  "ExecStart=" & binPath & " start --config " & svcCfgDir() / ConfigFileName & "\n" &
  "Restart=on-failure\n" &
  "RestartSec=5s\n" &
  "TimeoutStopSec=10s\n" &
  "\n[Install]\n" &
  "WantedBy=default.target\n"

proc ctlServiceInstall =
  # Directories
  createDir(svcUnitDir())
  createDir(svcCfgDir())

  # Service unit file — points at the actual binary so nimble build takes
  # effect on next restart without reinstalling.
  let binPath = getAppFilename()
  writeFile(svcUnitFile(), buildServiceFileContent(binPath))
  echo "  binary  → " & binPath & " (in-place, no copy)"
  echo "  service → " & svcUnitFile()

  # Env file — create if missing, then inject any keys found in current env
  let envPath = svcCfgDir() / EnvFileName
  if not fileExists(envPath):
    writeFile(envPath, EnvFileTemplate)
    discard svcRun("chmod 600 " & envPath)

  const knownKeys = [
    "TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN",
    "WECOM_CORP_ID", "WECOM_CORP_SECRET", "WECOM_AGENT_ID",
    "WECOM_CALLBACK_TOKEN", "WECHAT_APP_ID", "WECHAT_APP_SECRET",
    "WECHAT_CALLBACK_TOKEN", "WECHAT_TEMPLATE_ID",
    "FEISHU_APP_ID", "FEISHU_APP_SECRET",
    "FEISHU_VERIFICATION_TOKEN",
    "QQ_ONEBOT_URL", "QQ_ONEBOT_TOKEN",
    "QQ_OFFICIAL_APP_ID", "QQ_OFFICIAL_CLIENT_SECRET",
    "QQ_OFFICIAL_API_BASE", "QQ_OFFICIAL_TOKEN_BASE",
    "ZAI_API_KEY", "ZAI_CODING_API_KEY", "ZHIPU_API_KEY",
    "OPENROUTER_API_KEY", "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY", "MINIMAX_API_KEY",
    "OPENCODE_API_KEY",
    "BRAVE_API_KEY", "DONKEY_PG_DSN", "DONKEY_SQLITE_VEC_PATH",
    "DONKEY_SQLITE_VECTOR_PATH",
  ]
  var envContent = readFile(envPath)
  var injected: seq[string]
  for k in knownKeys:
    let v = getEnv(k)
    if v.len == 0: continue
    var lines = envContent.splitLines()
    var found = false
    for i in 0 ..< lines.len:
      if lines[i].startsWith(k & "="):
        lines[i] = k & "=" & v
        found = true
        break
    if not found:
      lines.add(k & "=" & v)
    envContent = lines.join("\n")
    injected.add(k)
  writeFile(envPath, envContent)

  if injected.len > 0:
    echo "  env     → " & envPath & " (injected: " & injected.join(", ") & ")"
  else:
    echo "  env     → " & envPath & " (no keys in current env — fill in manually)"

  # Toml config — create if missing
  let tomlPath = svcCfgDir() / ConfigFileName
  if not fileExists(tomlPath):
    writeFile(tomlPath, TomlTemplate)
    echo "  config  → " & tomlPath
  else:
    echo "  config  → " & tomlPath & " (already exists — kept)"

  # Register with systemd
  discard svcRun("systemctl --user daemon-reload")
  if svcRun("systemctl --user enable " & AppSlug):
    echo ""
    echo "✓ Installed. Run: " & AppSlug & " service start"
    echo "  Logs:         " & AppSlug & " service logs -f"
    echo "  Auto-start:   loginctl enable-linger " & getEnv("USER", "your-user")
  else:
    echo "Warning: systemctl enable failed — is systemd --user running?"

proc ctlServiceRemove =
  discard svcRun("systemctl --user stop " & AppSlug)
  discard svcRun("systemctl --user disable " & AppSlug)
  if fileExists(svcUnitFile()):
    removeFile(svcUnitFile())
    echo "Removed " & svcUnitFile()
  discard svcRun("systemctl --user daemon-reload")
  echo "✓ Service removed. Config preserved at " & svcCfgDir()

proc ctlServiceStart =
  if not svcRun("systemctl --user start " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Started. Logs: " & AppSlug & " service logs -f"

proc ctlServiceStop =
  if not svcRun("systemctl --user stop " & AppSlug):
    echo "Failed."
  else:
    echo "✓ Stopped."

proc ctlServiceRestart =
  if not svcRun("systemctl --user restart " & AppSlug):
    echo "Failed. Check: " & AppSlug & " service logs -f"
  else:
    echo "✓ Restarted. Logs: " & AppSlug & " service logs -f"

proc ctlServiceLogs(follow: bool) =
  var cmd = "journalctl --user -u " & AppSlug & " --no-pager -o cat"
  if follow: cmd.add(" -f")
  discard execShellCmd(cmd)

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

proc ctlUserEdit(memory: MdFileAdapter; uuid, field, value: string) =
  memory.updateUserField(UserId(uuid), field, value)
  echo "Updated " & uuid & ": " & field & " = " & value

proc ctlUserRevoke(memory: MdFileAdapter; uuid: string; revoked: bool) =
  memory.updateUserField(UserId(uuid), "Access", if revoked: "revoked" else: "active")
  echo (if revoked: "Revoked " else: "Restored ") & uuid

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

# ── ctl tool/skill commands ────────────────────────────────────────────────────

proc ctlToolInstall(registryPath: string; command: string; args: seq[string]) =
  let entry = ToolEntry(kind: tkMcp, command: command, args: args)
  saveToolEntry(registryPath, entry)
  echo "Registered MCP server: " & command

func buildSkillRuntimePolicy(cfg: DonkeyConfig;
                             skillName: string): SkillRuntimePolicy =
  SkillRuntimePolicy(allowNetHosts: cfg.effectiveSkillAllowNetHosts(skillName))

func buildSkillRuntimePolicyResolver(cfg: DonkeyConfig): SkillRuntimePolicyResolver =
  result = proc(skillName: string): SkillRuntimePolicy =
    buildSkillRuntimePolicy(cfg, skillName)

proc ctlSkillInstall(cfg: DonkeyConfig; skillsPath: string; name, scriptPath: string;
                     permissions: seq[string]) =
  discard validateSkillPermissions(permissions, cfg.webAllowlist).valueOr:
    echo error
    quit(1)
  let saveRes = saveSkillEntry(skillsPath, SkillManifest(
    name:        name,
    version:     "0.1.0",
    script:      scriptPath,
    permissions: permissions,
  ))
  if saveRes.isErr:
    echo saveRes.error
    quit(1)
  echo "Registered skill: " & name & " (" & scriptPath & ")"

proc ctlSkillList(skillsPath: string) =
  proc echoRemoteSkillInstalls(home: string) =
    let lock = readRemoteSkillLockfile(home)
    if lock.skills.len == 0:
      echo "(no remote installs)"
      return
    for slug, entry in lock.skills.pairs:
      echo slug & " v" & entry.version & "  [remote]"

  let skills = loadSkillRegistry(skillsPath)
  if skills.len == 0:
    echo "(no local skills registered)"
  else:
    for s in skills:
      echo s.name & " v" & s.version & "  " & s.script
      if s.tools.len > 0:       echo "  tools:       " & s.tools.join(", ")
      if s.permissions.len > 0: echo "  permissions: " & s.permissions.join(", ")
  echoRemoteSkillInstalls(parentDir(skillsPath))

proc ctlSkillUpdate(cfg: DonkeyConfig; skillsPath, name, scriptPath: string;
                    permissions: seq[string]) =
  ## Replaces the named skill entry in the registry (re-writes the file).
  discard validateSkillPermissions(permissions, cfg.webAllowlist).valueOr:
    echo error
    quit(1)
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
  for s in skills:
    let sr = saveSkillEntry(skillsPath, s)
    if sr.isErr:
      echo sr.error
      quit(1)
  echo "Updated skill: " & name

proc ctlSkillSearchRemote(registry: string; query: string; limit = 10) =
  let hits = searchRemoteSkills(registry, query, limit).valueOr:
    echo "Error: " & error
    quit(1)
  if hits.len == 0:
    echo "(no results)"
    return
  for hit in hits:
    let version = if hit.version.len > 0: " v" & hit.version else: ""
    let summary = if hit.summary.len > 0: "  " & hit.summary else: ""
    echo hit.slug & version & summary

proc ctlSkillInstallRemote(home, registry, slug: string) =
  let origin = installRemoteSkill(home, registry, slug).valueOr:
    echo "Error: " & error
    quit(1)
  echo "Installed " & origin.slug & "@" & origin.installedVersion

proc ctlSkillUpdateRemote(home, registry, slug: string) =
  if slug.len > 0:
    let version = updateRemoteSkill(home, registry, slug).valueOr:
      echo "Error: " & error
      quit(1)
    echo "Updated " & slug & " -> " & version
    return
  let lock = readRemoteSkillLockfile(home)
  if lock.skills.len == 0:
    echo "(no remote installs)"
    return
  for installedSlug, _ in lock.skills.pairs:
    let version = updateRemoteSkill(home, registry, installedSlug).valueOr:
      echo "Error updating " & installedSlug & ": " & error
      quit(1)
    echo "Updated " & installedSlug & " -> " & version

# ── ctl provider test ──────────────────────────────────────────────────────────

proc ctlProviderTest(name: string) =
  let fn = buildCompleteFn("provider = \"" & name & "\"", buildProviderBundle)
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
##   presentationState.streamMsgIds[channel|user|stream] = channelMsgId:
##     - first partial: send new message, store id
##     - subsequent partials: editMessage
##     - isPartial=false: editMessage + delete from presentationState

proc makeTgTypingFn(token: string; identityPath: string): TypingFn =
  ## Returns a TypingFn that sends typing indicators to Telegram users.
  ## Uses its own TelegramAdapter instance (token + resolver shared via ref).
  let tg = new TelegramAdapter
  tg[] = newTelegramAdapter(token, identityPath, pollTimeout = 0)
  result = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].} =
    if channel == ckTelegram:
      try:
        tg[].sendTyping(userId).isOkOr: discard
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
  cli: CliAdapter

proc buildRuntimeOutboundPorts(adapters: var DaemonAdapters): OutboundChannelPorts =
  buildOutboundPorts(
    addr adapters.tg, addr adapters.dc, addr adapters.wc,
    addr adapters.wch, addr adapters.qq, addr adapters.fs, addr adapters.mx,
    addr adapters.em, addr adapters.sl, addr adapters.dt, addr adapters.cli)

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

type DaemonRuntime = ref object
  globalOutbox:         AsyncQueue[OutboundMessage]
  sm:                   SessionManager
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
  result.tgTypingFn = makeTgTypingFn(env.telegramToken, env.identityPath)
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

proc initDaemonRuntime(home: string): DaemonRuntime =
  new(result)
  result.globalOutbox = newAsyncQueue[OutboundMessage]()
  result.sm.init()
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
  wchAdapter.startWebhook(port)
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
    qqAdapter.startWebhook(oneBotPort)
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
      providers:     @["openrouter"],
      routeCounts:   runtime.topRouteCounts(),
      routeMetrics:  runtime.topRouteMetrics(),
      recentRouteMetrics: runtime.topRecentRouteMetrics(),
      recentProviderMetrics: runtime.topRecentProviderMetrics(),
      providerCooldowns: runtime.activeProviderCooldowns(),
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
  startIpcServer(sockPath, ipcStatusFn, ipcLogFn)
  log.info("IPC socket: " & sockPath)
  let httpPort = resolveGatewayPort(getEnv("DONKEY_HTTP_PORT"))
  let gwStatusFn: GatewayStatusFn = proc(): DaemonStatus {.gcsafe.} =
    ipcStatusFn()
  let gwLogFn: GatewayLogFn = proc(n: int): seq[IpcLogEntry] {.gcsafe.} =
    ipcLogFn(n)
  let gwEventFn: GatewayEventFn = proc(n: int): seq[AgentEvent] {.gcsafe.} =
    agentEventSnapshot(n)
  if httpPort > 0:
    startHttpGateway(httpPort, gwStatusFn, gwLogFn, gwEventFn, gwInboundFn)
    log.info("HTTP gateway: http://0.0.0.0:" & $httpPort & " (bidirectional SSE enabled)")
  else:
    log.info("HTTP gateway: disabled")

type EnsureSessionPlan = object
  uid*:      string
  decision*: SessionIngressDecision
  oldInbox*: AsyncQueue[AgentMessage]
  oldAskInbox*: AsyncQueue[string]
  entry*:    ptr SessionEntry

type SessionIngressContext* = object
  plan*: EnsureSessionPlan
  msgId*: string

type SessionIngressServices = object
  cfg:          DonkeyConfig
  memory:       MdFileAdapter
  completeFn:   CompleteFn
  streamFn:     StreamFn
  toolClients:  seq[ToolRuntimePort]
  tools:        seq[ToolDescription]
  globalOutbox: AsyncQueue[OutboundMessage]
  log:          Logger
  sandboxMode:  SandboxMode
  sandboxRuntimeCmd: string
  sandboxImage: string
  typingFn:     TypingFn
  searchFn:     SearchFn
  routeRecordHook: proc(selection: ProviderSelection) {.gcsafe.}
  routeResultHook: proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.}
  routeFeedbackHook: proc(): seq[RouteFeedback] {.gcsafe.}
  routeCostHook: proc(): seq[RouteCostHint] {.gcsafe.}
  routeProviderCooldownHook: proc(): seq[ProviderCooldown] {.gcsafe.}

func toolCatalogSignature*(tools: seq[ToolDescription];
                           providerLabel: string;
                           paddockDir: string;
                           skillPrompt = ""): SessionRuntimeSignature =
  var signature = newStringOfCap(256)
  signature.add(providerLabel)
  signature.add('\n')
  signature.add(paddockDir)
  signature.add('\n')
  signature.add(skillPrompt)
  signature.add('\n')
  for tool in tools:
    signature.add(tool.name)
    signature.add('\t')
    signature.add(tool.description)
    signature.add('\t')
    signature.add(tool.schemaJson)
    signature.add('\n')
  result = SessionRuntimeSignature(signature)

proc buildEnsureSessionPlan*(sm: var SessionManager;
                             userId: UserId;
                             toolCatalogSignature: SessionRuntimeSignature): EnsureSessionPlan =
  let decision = decideSessionIngress(SessionIngressRequest(
    userId: userId,
    state: sm.snapshot(userId),
    nextSignature: toolCatalogSignature,
  ))
  let lease = sm.applyIngressDecision(userId, decision, toolCatalogSignature)
  EnsureSessionPlan(
    uid: $userId,
    decision: decision,
    oldInbox: lease.oldInbox,
    oldAskInbox: lease.oldAskInbox,
    entry: lease.entry,
  )

proc buildSessionIngressContext*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 toolCatalogSignature: SessionRuntimeSignature;
                                 msgSeq: var int): SessionIngressContext =
  result.plan = sm.buildEnsureSessionPlan(msg.userId, toolCatalogSignature)
  inc msgSeq
  result.msgId = $msg.userId & "-" & $msgSeq

func buildSessionIngressServices*(memory: MdFileAdapter;
                                  cfg: DonkeyConfig;
                                  completeFn: CompleteFn;
                                  streamFn: StreamFn;
                                  toolClients: seq[ToolRuntimePort];
                                  tools: seq[ToolDescription];
                                  globalOutbox: AsyncQueue[OutboundMessage];
                                  log: Logger;
                                  sandboxMode: SandboxMode;
                                  sandboxRuntimeCmd: string;
                                  sandboxImage: string;
                                  typingFn: TypingFn;
                                  searchFn: SearchFn;
                                  routeRecordHook: proc(selection: ProviderSelection) {.gcsafe.} = nil;
                                  routeResultHook: proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.} = nil;
                                  routeFeedbackHook: proc(): seq[RouteFeedback] {.gcsafe.} = nil;
                                  routeCostHook: proc(): seq[RouteCostHint] {.gcsafe.} = nil;
                                  routeProviderCooldownHook: proc(): seq[ProviderCooldown] {.gcsafe.} = nil): SessionIngressServices =
  SessionIngressServices(
    cfg: cfg,
    memory: memory,
    completeFn: completeFn,
    streamFn: streamFn,
    toolClients: toolClients,
    tools: tools,
    globalOutbox: globalOutbox,
    log: log,
    sandboxMode: sandboxMode,
    sandboxRuntimeCmd: sandboxRuntimeCmd,
    sandboxImage: sandboxImage,
    typingFn: typingFn,
    searchFn: searchFn,
    routeRecordHook: routeRecordHook,
    routeResultHook: routeResultHook,
    routeFeedbackHook: routeFeedbackHook,
    routeCostHook: routeCostHook,
    routeProviderCooldownHook: routeProviderCooldownHook,
  )

func withTypingFn*(typingFn: TypingFn;
                   services: SessionIngressServices): SessionIngressServices =
  result = services
  result.typingFn = typingFn

func buildDaemonSessionServices(ctx: DaemonContext;
                                cfg: DonkeyConfig;
                                memory: MdFileAdapter;
                                log: Logger): SessionIngressServices =
  buildSessionIngressServices(
    memory,
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
    proc(selection: ProviderSelection) {.gcsafe.} =
      ctx.runtime.recordRouteChoice(selection),
    proc(selection: ProviderSelection; elapsedMs: int64; ok: bool) {.gcsafe.} =
      ctx.runtime.recordRouteResult(selection, elapsedMs, ok),
    proc(): seq[RouteFeedback] {.gcsafe.} =
      ctx.runtime.currentRouteFeedback(),
    proc(): seq[RouteCostHint] {.gcsafe.} =
      loadRouteCostHints(@["openrouter", "groq", "anthropic", "zai-anthropic", "gemini",
                           "minimax", "zai", "zai-coding", "zen"]),
    proc(): seq[ProviderCooldown] {.gcsafe.} =
      ctx.runtime.currentProviderCooldowns(),
  )

proc startSessionOrchestrator*(plan: EnsureSessionPlan;
                               cfg: DonkeyConfig;
                               memory: MdFileAdapter;
                               streamFn: StreamFn;
                               bootstrap: SessionBootstrap;
                               globalOutbox: AsyncQueue[OutboundMessage];
                               log: Logger;
                               sandboxMode: SandboxMode;
                               sandboxRuntimeCmd: string;
                               sandboxImage: string;
                               typingFn: TypingFn;
                               searchFn: SearchFn) {.gcsafe.} =
  if not plan.decision.startsSessionRuntime:
    return
  let state = newSessionState()
  if plan.decision.rebuildsSessionRuntime and not plan.oldAskInbox.isNil:
    plan.oldAskInbox.addLastNoWait("__DONKEY_ASK_CANCELLED__")
  if plan.decision.rebuildsSessionRuntime and not plan.oldInbox.isNil:
    plan.oldInbox.addLastNoWait(newCancelMsg())
  asyncSpawn runOrchestrator(plan.entry[].inbox, plan.entry, globalOutbox, memory.toRuntimePort(),
                             bootstrap.completeFn,
                             newStdHttpAdapter(allowlist = cfg.webAllowlist).toRuntimePort(), streamFn,
                             bootstrap.clients, bootstrap.tools,
                             bootstrap.paddockDir, state,
                             typingFn, searchFn, log.child("orch"), bootstrap.providerLabel,
                             bootstrap.skillPrompt,
                             sandboxMode, sandboxRuntimeCmd, sandboxImage,
                             cfg.webAllowlist, cfg.toolWebPolicy,
                             errorExplainFn = bootstrap.errorExplainFn)

proc enqueueSessionMessage*(entry: var SessionEntry;
                            msg: InboundMessage;
                            msgId: string;
                            target: SessionIngressTarget) =
  case target
  of sitAskInbox:
    entry.awaitingAsk = false
    entry.askInbox.addLastNoWait(msg.text)
  of sitActorInbox:
    entry.inbox.addLastNoWait(buildSessionTaskMsg(msg, msgId))

proc startSessionIngress*(sm: var SessionManager;
                          msg: InboundMessage;
                          services: SessionIngressServices;
                          msgSeq: var int;
                          taskKind: TaskKind = tkUserMsg;
                          taskPayload: string = ""): SessionIngressContext {.gcsafe.} =
  let routingHook: RoutingTelemetryHook =
    proc(selection: ProviderSelection;
         prefs: SmartRoutingPrefs;
         req: CompletionRequest) {.gcsafe.} =
      if prefs.usesSmartRouting:
        if services.routeRecordHook != nil:
          services.routeRecordHook(selection)
        var hasImage = false
        for turn in req.messages:
          if turn.imageUrl.len > 0:
            hasImage = true
            break
        services.log.info("[route] " & $msg.userId & " -> " &
                          selection.formatSelection &
                          " | thinking=" & prefs.thinking &
                          " tools=" & $req.tools.len &
                          " image=" & $hasImage &
                          " chars=" & $requestApproxChars(req))
  let bootstrap = buildSessionBootstrap(
    services.memory.toRuntimePort(), msg.userId, services.completeFn, buildProviderBundle,
    normalizeProviderDefaults(services.cfg.defaultProvider, services.cfg.defaultModel),
    buildDenoSkillRuntime, buildSkillRuntimePolicyResolver(services.cfg),
    services.toolClients, services.tools,
    routingHook, services.routeResultHook, services.routeFeedbackHook,
    services.routeCostHook, services.routeProviderCooldownHook)
  let signature = toolCatalogSignature(
    bootstrap.tools, bootstrap.providerLabel, bootstrap.paddockDir, bootstrap.skillPrompt)
  result = sm.buildSessionIngressContext(msg, signature, msgSeq)
  if result.plan.decision.shouldRecordChannel:
    sm.recordChannel(msg.userId, msg.channel, msg.channelId)
  ## Enqueue task message BEFORE starting the new orchestrator.
  ## This prevents the orchestrator from receiving a cancel message
  ## (from the old orchestrator's inbox) before the task.
  case result.plan.decision.target
  of sitActorInbox:
    if taskKind == tkUserMsg:
      result.plan.entry[].inbox.addLastNoWait(buildSessionTaskMsg(msg, result.msgId))
    else:
      result.plan.entry[].inbox.addLastNoWait(newTaskMsg(
        result.msgId, taskKind, $msg.userId, taskPayload,
        msg.channel, sessionReplyTo(msg)))
  of sitAskInbox:
    if taskKind == tkUserMsg:
      result.plan.entry[].awaitingAsk = false
      result.plan.entry[].askInbox.addLastNoWait(msg.text)
    else:
      result.plan.entry[].inbox.addLastNoWait(newTaskMsg(
        result.msgId, taskKind, $msg.userId, taskPayload,
        msg.channel, sessionReplyTo(msg)))
  startSessionOrchestrator(result.plan, services.cfg,
                           services.memory,
                           services.streamFn, bootstrap,
                           services.globalOutbox, services.log,
                           services.sandboxMode, services.sandboxRuntimeCmd, services.sandboxImage,
                           services.typingFn, services.searchFn)
  if result.plan.decision.startsNewSession:
    services.log.info("new session: " & result.plan.uid)
  elif result.plan.decision.rebuildsSessionRuntime:
    services.log.info("rebuilt session runtime after tool catalog change: " & result.plan.uid)

proc ensureSession(sm:       var SessionManager;
                   msg:      InboundMessage;
                   services: SessionIngressServices;
                   msgSeq:   var int) {.gcsafe.} =
  discard startSessionIngress(sm, msg, services, msgSeq)

proc ensureSessionTask(sm:       var SessionManager;
                       msg:      InboundMessage;
                       services: SessionIngressServices;
                       msgSeq:   var int;
                       taskKind: TaskKind;
                       payload:  string) {.gcsafe.} =
  discard startSessionIngress(sm, msg, services, msgSeq, taskKind, payload)

proc handleSessionFallback(runtime:      var DaemonRuntime;
                           msg:          InboundMessage;
                           services:     SessionIngressServices) =
  if services.memory.isRevoked(msg.userId):
    runtime.globalOutbox.putNoWait(OutboundMessage(
      userId: msg.userId,
      channel: msg.channel,
      replyTo: if msg.channel == ckTelegram: msg.channelId else: "",
      text: "Acesso revogado pelo administrador.",
    ))
    return
  ensureSession(runtime.sm, msg, services, runtime.msgSeq)

func shouldStageInboundReaction(msg: InboundMessage): bool =
  supportsMessageReactions(msg.channel) and
    msg.callbackId.len == 0 and
    msg.channelId.len > 0

proc stageInboundReactionStatus(runtime: var DaemonRuntime;
                                outboundPorts: OutboundChannelPorts;
                                msg: InboundMessage) =
  if not shouldStageInboundReaction(msg):
    return
  discard setOutboundReaction(msg.channel, msg.userId, msg.channelId, "⏳", outboundPorts, newLogger("status.reaction"))
  runtime.presentationState.rememberStatus(msg.channel, msg.userId, "turn", msg.channelId)

proc completeInboundReactionStatus(runtime: var DaemonRuntime;
                                   outboundPorts: OutboundChannelPorts;
                                   channel: ChannelKind;
                                   userId: UserId;
                                   msgId: string;
                                   isError: bool) =
  if not supportsMessageReactions(channel) or msgId.len == 0:
    return
  runtime.presentationState.clearStatus(channel, userId, "turn")
  let finalEmoji = if isError: "❌" else: "✅"
  discard setOutboundReaction(channel, userId, msgId, finalEmoji, outboundPorts, newLogger("status.reaction"))

proc handleTelegramFallback(runtime:      var DaemonRuntime;
                            msg:          InboundMessage;
                            services:     SessionIngressServices) =
  handleSessionFallback(runtime, msg, services)

proc drainTelegramEvents(runtime:      var DaemonRuntime;
                         tgAdapter:    var TelegramAdapter;
                         outboundPorts: OutboundChannelPorts;
                         services:     SessionIngressServices;
                         log:          Logger): bool =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  let runtimePtr = addr runtime
  let tgMsgs = tgAdapter.receive().valueOr:
    log.error("telegram receive: " & error)
    return false

  for msg in tgMsgs:
    let stagedReaction = shouldStageInboundReaction(msg)
    if stagedReaction:
      tgAdapter.sendTyping(msg.userId).isOkOr: discard
      stageInboundReactionStatus(runtime, outboundPorts, msg)
    if telegram_runtime.handleTelegramMessage(
      msg, runtime.sm, tgAdapter, runtime.presentationState, services.memory, completeBuilder,
      modelCatalogLoader,
      services.toolClients.len, services.tools.len + nativeSessionTools().len, runtime.msgSeq, runtime.daemonStartMs, log,
      proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} =
        ensureSessionTask(runtimePtr[].sm, msg, services, runtimePtr[].msgSeq, taskKind, payload)):
      if stagedReaction:
        completeInboundReactionStatus(runtime, outboundPorts, msg.channel, msg.userId, msg.channelId, false)
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

  let isError = outMsg.text.startsWith("Desculpe") or
                outMsg.text.startsWith("Tool call loop")
  completeInboundReactionStatus(runtime, outboundPorts, outMsg.channel, outMsg.userId, msgId, isError)

proc drainGlobalOutbox(runtime:  var DaemonRuntime;
                       adapters: var DaemonAdapters;
                       log:      Logger) =
  let outboundPorts = buildRuntimeOutboundPorts(adapters)
  while runtime.globalOutbox.len > 0:
    let outMsg = runtime.globalOutbox.getNoWait()
    completeInboundReactionStatus(runtime, outboundPorts, outMsg)
    routeOutbound(outMsg, outboundPorts, log, runtime.presentationState)

proc startDaemonIngress(ctx: DaemonContext;
                        log: Logger) =
  startOptionalDiscordGateway(ctx.adapters.dc, ctx.env.discordToken, ctx.env.discordGuildId, log)
  startOptionalWeComGateway(ctx.adapters.wc, ctx.env.wecomCorpId, log)
  startOptionalWeChatGateway(ctx.adapters.wch, ctx.env.wechatAppId, log)
  startOptionalFeishuGateway(ctx.adapters.fs, ctx.env.feishuAppId, log)
  startOptionalSlackGateway(ctx.adapters.sl, ctx.env.slackBotToken, log)
  startOptionalDingTalkGateway(ctx.adapters.dt, ctx.env.dingTalkAppKey, log)
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
  handleSessionFallback(
    ctx.runtime,
    msg,
    buildDaemonSessionServices(ctx, cfg, memory, log),
  )

proc drainDiscordGateway(ctx: DaemonContext;
                         cfg: DonkeyConfig;
                         memory: MdFileAdapter;
                         log: Logger) =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  let outboundPorts = buildRuntimeOutboundPorts(ctx.adapters)
  discord_runtime.drainDiscordEvents(
    ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, ctx.runtime.presentationState, memory, completeBuilder, modelCatalogLoader,
    ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
    ctx.runtime.msgSeq, log,
    proc(msg: InboundMessage) =
      stageInboundReactionStatus(ctx.runtime, outboundPorts, msg),
    proc(msg: InboundMessage) =
      completeInboundReactionStatus(ctx.runtime, outboundPorts, msg.channel, msg.userId, msg.channelId, false),
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainWeComGateway(ctx: DaemonContext;
                       cfg: DonkeyConfig;
                       memory: MdFileAdapter;
                       log: Logger) =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  wecom_runtime.drainWeComEvents(
    ctx.adapters.wc, ctx.env.wecomCorpId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
    ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
    ctx.runtime.msgSeq, log,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainWeChatGateway(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  wechat_runtime.drainWeChatEvents(
    ctx.adapters.wch, ctx.env.wechatAppId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
    ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
    ctx.runtime.msgSeq,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainQQGateway(ctx: DaemonContext;
                    cfg: DonkeyConfig;
                    memory: MdFileAdapter;
                    log: Logger) =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  qq_runtime.drainQQEvents(
    ctx.adapters.qq, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
    ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
    ctx.runtime.msgSeq,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainFeishuGateway(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
    buildCompleteFn(preferencesMd, buildProviderBundle)
  let modelCatalogLoader = buildModelCatalogLoader()
  feishu_runtime.drainFeishuEvents(
    ctx.adapters.fs, ctx.env.feishuAppId, ctx.runtime.sm, memory, completeBuilder, modelCatalogLoader,
    ctx.services.tools.len + nativeSessionTools().len, ctx.services.toolClients.len, ctx.runtime.daemonStartMs,
    ctx.runtime.msgSeq,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainTelegramGateway(ctx: DaemonContext;
                          cfg: DonkeyConfig;
                          memory: MdFileAdapter;
                          log: Logger): bool =
  let services =
    buildDaemonSessionServices(ctx, cfg, memory, log) |>->
    withTypingFn(ctx.services.tgTypingFn)
  drainTelegramEvents(ctx.runtime, ctx.adapters.tg, buildRuntimeOutboundPorts(ctx.adapters), services, log)

proc drainGatewayEvents(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger): bool =
  drainDiscordGateway(ctx, cfg, memory, log)
  drainWeComGateway(ctx, cfg, memory, log)
  drainWeChatGateway(ctx, cfg, memory, log)
  drainFeishuGateway(ctx, cfg, memory, log)
  drainQQGateway(ctx, cfg, memory, log)
  drainTelegramGateway(ctx, cfg, memory, log)

proc withOutboxDrain(ctx: DaemonContext;
                     log: Logger;
                     tick: DaemonTickResult): DaemonTickResult =
  result = tick
  drainGlobalOutbox(ctx.runtime, ctx.adapters, log)

proc withGatewayDrain(ctx: DaemonContext;
                      cfg: DonkeyConfig;
                      memory: MdFileAdapter;
                      log: Logger;
                      tick: DaemonTickResult): DaemonTickResult =
  result = tick
  result.ok = drainGatewayEvents(ctx, cfg, memory, log)

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
                   cfg: DonkeyConfig;
                   memory: MdFileAdapter;
                   log: Logger): DaemonTickResult =
  result =
    DaemonTickResult(ok: true, remindersChecked: false) |>->
    withOutboxDrain(ctx, log) |>->
    withGatewayDrain(ctx, cfg, memory, log) |>->
    withReminderCheck(ctx, memory, log)

proc runDaemonLoop(ctx: DaemonContext;
                   cfg: DonkeyConfig;
                   memory: MdFileAdapter;
                   log: Logger): DaemonLoopResult =
  let tick = runDaemonTick(ctx, cfg, memory, log)
  DaemonLoopResult(
    sleepMs: if tick.ok: 100 else: 500,
  )

proc startDaemon(cfg: DonkeyConfig; log: Logger) {.async: (raises: [Exception]).} =
  ## Async daemon: Telegram (pollTimeout=0) + Discord (gateway thread) + WeCom (webhook thread).
  ## Loop: drain globalOutbox → drain Discord → drain WeCom → poll Telegram → sleepAsync(100ms)
  log.info("daemon starting — Telegram + Discord + WeCom")

  let bootstrap = loadDaemonBootstrap(cfg, log)
  let memory = bootstrap.memory
  let ctx = bootstrap.ctx
  activateDaemonBootstrap(ctx, cfg, memory, log)
  let sessionServices = buildDaemonSessionServices(ctx, cfg, memory, log)

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
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      buildCompleteFn(preferencesMd, buildProviderBundle)
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
        completeInboundReactionStatus(ctx.runtime, outboundPorts, msg.channel, msg.userId, msg.channelId, false),
      proc(msg: InboundMessage) {.gcsafe.} =
        handleGatewayFallback(ctx, cfg, memory, msg, log))

  log.info("polling for messages…")
  while true:
    let loopResult = runDaemonLoop(ctx, cfg, memory, log)
    await sleepAsync(ctimer.milliseconds(loopResult.sleepMs.int64))

# ── main ───────────────────────────────────────────────────────────────────────

proc main =
  var configPath = ""
  var args: seq[string] = @[]
  var logsFollow = false
  var logsCat    = false
  var devMode    = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "version": printVersion(); quit(0)
      of "help":    printHelp();    quit(0)
      of "config":  configPath = val
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
      args.add key
    of cmdEnd:
      break

  if args.len >= 3 and args[0] == SandboxExecCommand:
    quit(runSandboxWorker(args[1], args[2]))

  if args.len >= 1 and args[0] == "setup":
    let home = resolveHome()
    runSetupWizard(home)
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

  if args.len >= 1 and args[0] == "ctl":
    if args.len >= 3 and args[1] == "user" and args[2] == "list":
      ctlUserList(memory); quit(0)
    elif args.len >= 4 and args[1] == "user" and args[2] == "show":
      ctlUserShow(memory, args[3]); quit(0)
    elif args.len >= 6 and args[1] == "user" and args[2] == "edit":
      ctlUserEdit(memory, args[3], args[4], args[5 .. ^1].join(" ")); quit(0)
    elif args.len >= 4 and args[1] == "user" and args[2] == "revoke":
      ctlUserRevoke(memory, args[3], true); quit(0)
    elif args.len >= 4 and args[1] == "user" and args[2] == "allow":
      ctlUserRevoke(memory, args[3], false); quit(0)
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
      ctlSkillInstall(cfg, skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 4 and args[1] == "skill" and args[2] == "search":
      ctlSkillSearchRemote(getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3]); quit(0)
    elif args.len == 4 and args[1] == "skill" and args[2] == "install":
      ctlSkillInstallRemote(cfg.home, getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3]); quit(0)
    elif args.len >= 3 and args[1] == "skill" and args[2] == "list":
      ctlSkillList(cfg.home / "skills.toml"); quit(0)
    elif args.len >= 5 and args[1] == "skill" and args[2] == "update":
      let skillsPath = cfg.home / "skills.toml"
      ctlSkillUpdate(cfg, skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 3 and args[1] == "skill" and args[2] == "update":
      let slug = if args.len >= 4: args[3] else: ""
      ctlSkillUpdateRemote(cfg.home, getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), slug); quit(0)
    elif args.len >= 4 and args[1] == "provider" and args[2] == "test":
      ctlProviderTest(args[3]); quit(0)
    elif args.len >= 5 and args[1] == "memory" and args[2] == "search":
      when defined(withPostgres) or defined(withSqlite):
        let memory = MdFileAdapter(
          paddocksDir: cfg.paddocks,
          magmaDsn: getEnv("DONKEY_PG_DSN"),
          magmaSqlitePath: configuredMagmaSqlitePath(cfg.home),
          magmaSqliteVectorPath:
            block:
              let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
              if vecPath.len > 0: vecPath else: getEnv("DONKEY_SQLITE_VECTOR_PATH"),
        )
        ctlMemorySearch(memory, args[3], args[4]); quit(0)
      else:
        echo "This build disabled MAGMA support; rebuild with -d:withPostgres or -d:withSqlite"; quit(1)
    elif args.len >= 4 and args[1] == "memory" and args[2] == "import":
      when defined(withPostgres) or defined(withSqlite):
        let memory = MdFileAdapter(
          paddocksDir: cfg.paddocks,
          magmaDsn: getEnv("DONKEY_PG_DSN"),
          magmaSqlitePath: configuredMagmaSqlitePath(cfg.home),
          magmaSqliteVectorPath:
            block:
              let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
              if vecPath.len > 0: vecPath else: getEnv("DONKEY_SQLITE_VECTOR_PATH"),
        )
        ctlMemoryImport(memory, args[3]); quit(0)
      else:
        echo "This build disabled MAGMA support; rebuild with -d:withPostgres or -d:withSqlite"; quit(1)
    elif args.len >= 4 and args[1] == "memory" and args[2] == "export":
      when defined(withPostgres) or defined(withSqlite):
        let memory = MdFileAdapter(
          paddocksDir: cfg.paddocks,
          magmaDsn: getEnv("DONKEY_PG_DSN"),
          magmaSqlitePath: configuredMagmaSqlitePath(cfg.home),
          magmaSqliteVectorPath:
            block:
              let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
              if vecPath.len > 0: vecPath else: getEnv("DONKEY_SQLITE_VECTOR_PATH"),
        )
        let outDir = if args.len >= 5: args[4] else: ""
        ctlMemoryExport(memory, args[3], outDir); quit(0)
      else:
        echo "This build disabled MAGMA support; rebuild with -d:withPostgres or -d:withSqlite"; quit(1)
    elif args.len >= 2 and args[1] == "status":
      let sockPath = cfg.home / SockFileName
      let sr = ipcClient.queryStatus(sockPath)
      if sr.isErr:
        echo "Error: " & sr.error; quit(1)
      let st = sr.value
      echo formatDaemonStatus(st)
      quit(0)
    else:
      printHelp(); quit(1)

  if args.len >= 2 and args[0] == "service":
    case args[1]
    of "install": ctlServiceInstall(); quit(0)
    of "remove":  ctlServiceRemove();  quit(0)
    of "start":   ctlServiceStart();   quit(0)
    of "stop":    ctlServiceStop();    quit(0)
    of "restart": ctlServiceRestart(); quit(0)
    of "logs":
      ctlServiceLogs(logsFollow); quit(0)
    else: printHelp(); quit(1)

  if args.len >= 1 and args[0] == "tui":
    let sockPath = cfg.home / SockFileName
    runTui(sockPath)
    quit(0)

  if args.len >= 1 and args[0] == "doctor":
    quit(runDoctor(cfg, devMode))

  log.info(AppSlug & " " & Version & " starting")
  log.info("home: " & cfg.home)

  waitFor startDaemon(cfg, log)

when isMainModule:
  main()
