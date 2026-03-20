## donkey — AI agent system entry point.

import std/[json, os, parseopt, strutils, tables, terminal]
import chronos
import chronos/asyncsync
import donkey/config/loader
import donkey/config/types
import donkey/config/tools_registry
import donkey/config/skills_registry
import donkey/config/clawhub_registry
import donkey/adapters/tool/deno_skill
import donkey/core/log
import donkey/core/pipeops
import donkey/core/app_meta
import donkey/adapters/memory/md_file
when defined(withPostgres):
  import donkey/adapters/memory/postgres_memory
  import donkey/adapters/embedding/openrouter_embed
  import donkey/ports/embedding
import donkey/adapters/provider/openrouter
import donkey/adapters/channel/telegram
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_runtime
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wecom_runtime
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wechat_runtime
import donkey/adapters/channel/qq
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/feishu
import donkey/adapters/channel/feishu_runtime
import donkey/adapters/tool/mcp_client
import donkey/domain/message
import donkey/domain/agent_message
import donkey/ports/provider
import donkey/app/orchestrator
import donkey/app/ipc_server
import donkey/app/outbound_runtime
import donkey/app/session_manager
import donkey/app/session_bootstrap
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
  --config <path>  Path to """ & ConfigFileName & """  (default: ~/""" & HomeDirName & "/" & ConfigFileName & """)

Commands:
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
  ctl memory search <uuid> <q>   Semantic search in user memory  (-d:withPostgres)
  ctl memory import <uuid>       Import .md paddock into Postgres (-d:withPostgres)
  ctl memory export <uuid> [dir] Export Postgres memory view as .md (-d:withPostgres)
  ctl status                     Show daemon status (daemon must be running)
  tui                            Open live TUI dashboard (daemon must be running)
  service install                Install as systemd --user service
  service remove                 Remove the systemd --user service
  service start                  systemctl --user start """ & AppSlug & """
  service stop                   systemctl --user stop """ & AppSlug & """
  service restart                systemctl --user restart """ & AppSlug & """
  service logs [-f] [--cat]      Show service logs (follow with -f, clean output with --cat)
"""

# ── service commands ───────────────────────────────────────────────────────────

const ServiceFileContent = """
[Unit]
Description=Donkey AI Agent Daemon
After=network.target
Wants=network.target

[Service]
Type=simple
EnvironmentFile=%h/.config/""" & ConfigDirName & "/" & EnvFileName & """
ExecStart=%h/.local/bin/""" & AppSlug & """ start --config %h/.config/""" & ConfigDirName & "/" & ConfigFileName & """
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10s

[Install]
WantedBy=default.target
"""

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

ZHIPU_API_KEY=
OPENROUTER_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
MINIMAX_API_KEY=

BRAVE_API_KEY=
# DONKEY_PG_DSN=
"""

const TomlTemplate = """# """ & AppName & """ configuration

[""" & ConfigSectionName & """]
# log_level = "info"    # debug | info | warn | error
# log_file  = ""        # leave empty to log to stderr (journald)

[sandbox]
# mode  = "none"        # "none" or "docker"
# image = "alpine"
"""

proc svcUnitDir(): string = getHomeDir() / ".config" / "systemd" / "user"
proc svcUnitFile(): string = svcUnitDir() / ServiceUnitName
proc svcCfgDir(): string  = getHomeDir() / ".config" / ConfigDirName
proc svcBinPath(): string = getHomeDir() / ".local" / "bin" / AppSlug

proc svcRun(cmd: string): bool =
  execShellCmd(cmd) == 0

proc ctlServiceInstall =
  # Directories
  createDir(svcUnitDir())
  createDir(svcCfgDir())
  createDir(getHomeDir() / ".local" / "bin")

  # Binary — copy current executable
  let src = getAppFilename()
  let dst = svcBinPath()
  copyFile(src, dst)
  discard svcRun("chmod 755 " & dst)
  echo "  binary  → " & dst

  # Service unit file
  writeFile(svcUnitFile(), ServiceFileContent.strip() & "\n")
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
    "ZHIPU_API_KEY", "OPENROUTER_API_KEY", "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY", "MINIMAX_API_KEY",
    "BRAVE_API_KEY", "DONKEY_PG_DSN",
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

proc ctlServiceLogs(follow: bool; cat: bool) =
  var cmd = "journalctl --user -u " & AppSlug & " --no-pager"
  if follow: cmd.add(" -f")
  if cat:    cmd.add(" -o cat")
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

# ── ctl memory commands ────────────────────────────────────────────────────────

when defined(withPostgres):
  proc echoMemoryExport(entries: seq[MemoryExportEntry]) =
    for i, entry in entries:
      if i > 0:
        echo ""
      echo "# " & entry.fileName
      echo ""
      echo entry.content

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

  proc ctlMemoryExport(pgDsn: string; uuid: string; outDir = "") =
    let embedKey = getEnv("OPENROUTER_API_KEY")
    let embedAdapter = newOpenRouterEmbeddingAdapter(embedKey)
    let embedFn: EmbedFn = proc(text: string): seq[float32] =
      embedAdapter.embed(text)
    let pg = newPostgresMemoryAdapter(pgDsn, embedFn)
    pg.migrate()
    let ctx = pg.loadContext(UserId(uuid))
    let entries = buildMemoryExportEntries(ctx)
    if outDir.len == 0:
      echoMemoryExport(entries)
      return
    exportContextToDir(ctx, outDir)
    echo "Exported " & uuid & " to " & outDir

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

proc makeTgTypingFn(token: string; identityPath: string): TypingFn =
  ## Returns a TypingFn that sends typing indicators to Telegram users.
  ## Uses its own TelegramAdapter instance (token + resolver shared via ref).
  let tg = new TelegramAdapter
  tg[] = newTelegramAdapter(token, identityPath, pollTimeout = 0)
  result = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].} =
    if channel == ckTelegram:
      try:
        {.cast(gcsafe).}: tg[].sendTyping(userId).isOkOr: discard
      except: discard

type DaemonToolBundle = object
  clients: seq[McpClientAdapter]
  tools:   seq[ToolDescription]

type GlobalProviderBundle = object
  completeFn: CompleteFn
  streamFn:   StreamFn

type DaemonEnv = object
  telegramToken: string
  discordToken:  string
  wecomCorpId:   string
  wechatAppId:   string
  feishuAppId:   string
  qqApiBase:     string
  memory:        MdFileAdapter
  identityPath:  string
  wecomAgentId:  int

type DaemonAdapters = object
  tg: TelegramAdapter
  dc: DiscordAdapter
  wc: WeComAdapter
  wch: WeChatAdapter
  qq: QQAdapter
  fs: FeishuAdapter

type DaemonServices = object
  toolClients:      seq[McpClientAdapter]
  tools:            seq[ToolDescription]
  globalCompleteFn: CompleteFn
  globalStreamFn:   StreamFn
  tgTypingFn:       TypingFn
  globalSearchFn:   SearchFn

type DaemonRuntime = ref object
  globalOutbox:         AsyncQueue[OutboundMessage]
  sm:                   SessionManager
  streamMsgIds:         Table[string, string]
  statusMsgIds:         Table[string, string]
  kbdMsgIds:            Table[string, string]
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

proc loadDaemonToolBundle(cfgHome: string): DaemonToolBundle =
  {.cast(gcsafe).}:
    for entry in loadToolRegistry(cfgHome / "tools.toml"):
      var client = buildMcpClient(entry)
      let schemasRes = client.listTools()
      if schemasRes.isOk:
        for s in schemasRes.value:
          result.tools.add(ToolDescription(
            name:        s.name,
            description: s.description,
            schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
          ))
      result.clients.add(client)
    for manifest in loadSkillRegistry(cfgHome / "skills.toml"):
      var client = newDenoSkillAdapter(manifest.script, manifest.permissions)
      let schemasRes = client.listTools()
      if schemasRes.isOk:
        for s in schemasRes.value:
          result.tools.add(ToolDescription(
            name:        s.name,
            description: s.description,
            schemaJson:  if s.inputSchema != nil: $s.inputSchema else: "",
          ))
      result.clients.add(client)

proc buildGlobalProviderBundle(): GlobalProviderBundle =
  let orKey = getEnv("OPENROUTER_API_KEY")
  let orAdapter = newOpenRouterAdapter(orKey)
  result.completeFn = if orKey.len > 0: makeFn(orAdapter) else: nil
  result.streamFn = if orKey.len > 0: orAdapter.makeStreamFn() else: nil

proc buildGlobalSearchFn(): SearchFn

proc initDaemonServices(cfg: DonkeyConfig;
                        env: DaemonEnv;
                        log: Logger): DaemonServices =
  let toolBundle = loadDaemonToolBundle(cfg.home)
  result.toolClients = toolBundle.clients
  result.tools = toolBundle.tools

  let providerBundle = buildGlobalProviderBundle()
  result.globalCompleteFn = providerBundle.completeFn
  result.globalStreamFn = providerBundle.streamFn
  result.tgTypingFn = makeTgTypingFn(env.telegramToken, env.identityPath)
  {.cast(gcsafe).}:
    result.globalSearchFn = buildGlobalSearchFn()
  when defined(withPostgres):
    if result.globalSearchFn != nil:
      log.info("Postgreyskull semantic search enabled")

proc loadDaemonEnv(cfg: DonkeyConfig; log: Logger): DaemonEnv =
  result.telegramToken = getEnv("TELEGRAM_BOT_TOKEN")
  if result.telegramToken.len == 0:
    log.error("TELEGRAM_BOT_TOKEN not set")
    quit(1)

  result.discordToken = getEnv("DISCORD_BOT_TOKEN")
  result.wecomCorpId = getEnv("WECOM_CORP_ID")
  result.wechatAppId = getEnv("WECHAT_APP_ID")
  result.feishuAppId = getEnv("FEISHU_APP_ID")
  result.qqApiBase = getEnv("QQ_ONEBOT_URL")
  result.memory = MdFileAdapter(paddocksDir: cfg.paddocks)
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
  result.qq = newQQAdapter(env.qqApiBase, getEnv("QQ_ONEBOT_TOKEN"),
                           env.identityPath)
  result.fs = newFeishuAdapter(env.feishuAppId, getEnv("FEISHU_APP_SECRET"),
                               env.identityPath)

proc initDaemonRuntime(): DaemonRuntime =
  new(result)
  result.globalOutbox = newAsyncQueue[OutboundMessage]()
  result.sm.init()
  result.daemonStartMs = nowMs()

proc initDaemonContext(cfg: DonkeyConfig;
                       env: DaemonEnv;
                       log: Logger): DaemonContext =
  new(result)
  result.env = env
  result.adapters = initDaemonAdapters(env)
  result.services = initDaemonServices(cfg, env, log)
  result.runtime = initDaemonRuntime()

proc loadDaemonBootstrap(cfg: DonkeyConfig;
                         log: Logger): DaemonBootstrap =
  let env = loadDaemonEnv(cfg, log)
  result.memory = env.memory
  result.ctx = initDaemonContext(cfg, env, log)

proc startOptionalDiscordGateway(dcAdapter: var DiscordAdapter;
                                 discordToken: string;
                                 log: Logger) =
  if discordToken.len == 0:
    log.info("DISCORD_BOT_TOKEN not set — Discord disabled")
    return

  dcAdapter.startGateway()
  let appId = dcAdapter.getAppId().valueOr:
    log.warn("Discord getAppId failed: " & error); ""
  if appId.len > 0:
    dcAdapter.registerSlashCommands(appId).isOkOr:
      log.warn("Discord slash cmd reg failed: " & error)
  log.info("Discord gateway started")

proc startOptionalWeComGateway(wcAdapter: var WeComAdapter;
                               wecomCorpId: string;
                               log: Logger) =
  if wecomCorpId.len == 0:
    log.info("WECOM_CORP_ID not set — WeCom disabled")
    return

  let wcPort = Port(parseInt(if getEnv("WECOM_WEBHOOK_PORT").len > 0:
                               getEnv("WECOM_WEBHOOK_PORT") else: "8080"))
  wcAdapter.startWebhook(wcPort)
  log.info("WeCom webhook listener started on port " & $wcPort)

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

proc startOptionalQQGateway(qqAdapter: var QQAdapter;
                            qqApiBase: string;
                            log: Logger) =
  if qqApiBase.len == 0:
    log.info("QQ_ONEBOT_URL not set — QQ disabled")
    return
  log.info("QQ OneBot HTTP client enabled: " & qqApiBase)

proc buildGlobalSearchFn(): SearchFn =
  when defined(withPostgres):
    let pgDsnRuntime = getEnv("DONKEY_PG_DSN")
    if pgDsnRuntime.len > 0:
      let orEmbedKey = getEnv("OPENROUTER_API_KEY")
      let embedAdapter = newOpenRouterEmbeddingAdapter(orEmbedKey)
      let embedFn: EmbedFn = proc(text: string): seq[float32] =
        {.cast(gcsafe).}: embedAdapter.embed(text)
      let pgSearch = newPostgresMemoryAdapter(pgDsnRuntime, embedFn)
      pgSearch.migrate()
      result = proc(userId: UserId; query: string; limit: int): seq[MemoryHit]
                    {.gcsafe, raises: [].} =
        try: {.cast(gcsafe).}: pgSearch.search(userId, query, limit)
        except: @[]
  else:
    discard

proc setupIpcServer(cfg: DonkeyConfig;
                    sm: SessionManager;
                    toolsCount: int;
                    daemonStartMs: int64;
                    telegramToken: string;
                    discordToken: string;
                    wecomCorpId: string;
                    wechatAppId: string;
                    feishuAppId: string;
                    qqApiBase: string;
                    log: Logger) =
  let sockPath = cfg.home / SockFileName
  let ipcStatusFn: StatusProvider = proc(): DaemonStatus {.gcsafe, raises: [].} =
    var sessions: seq[SessionInfo]
    {.cast(gcsafe).}:
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
    if qqApiBase.len > 0: activeChannels.add("qq")
    DaemonStatus(
      uptimeSec:     (nowMs() - daemonStartMs) div 1000,
      sessionCount:  sm.sessionCount(),
      sessions:      sessions,
      channels:      activeChannels,
      providers:     @["openrouter"],
      toolsCount:    toolsCount,
      memoryBackend: when defined(withPostgres): "postgres" else: "md",
    )
  let ipcLogFn: LogProvider = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [].} =
    for e in ringSnapshot(n):
      result.add(IpcLogEntry(ts: e.ts, level: e.level, subsys: e.sub, msg: e.msg))
  {.cast(gcsafe).}: startIpcServer(sockPath, ipcStatusFn, ipcLogFn)
  log.info("IPC socket: " & sockPath)

type EnsureSessionPlan = object
  uid*:      string
  isNew*:    bool
  rebuilt*:  bool
  oldInbox*: AsyncQueue[AgentMessage]
  oldAskInbox*: AsyncQueue[string]
  entry*:    ptr SessionEntry

type SessionIngressContext* = object
  plan*: EnsureSessionPlan
  msgId*: string

type SessionIngressServices = object
  memory:       MdFileAdapter
  completeFn:   CompleteFn
  streamFn:     StreamFn
  toolClients:  seq[McpClientAdapter]
  tools:        seq[ToolDescription]
  globalOutbox: AsyncQueue[OutboundMessage]
  log:          Logger
  sandboxMode:  SandboxMode
  sandboxImage: string
  typingFn:     TypingFn
  searchFn:     SearchFn

func toolCatalogSignature*(tools: seq[ToolDescription];
                           providerLabel: string;
                           paddockDir: string;
                           skillPrompt = ""): string =
  result.add(providerLabel)
  result.add('\n')
  result.add(paddockDir)
  result.add('\n')
  result.add(skillPrompt)
  result.add('\n')
  for tool in tools:
    result.add(tool.name)
    result.add('\t')
    result.add(tool.description)
    result.add('\t')
    result.add(tool.schemaJson)
    result.add('\n')

proc buildEnsureSessionPlan*(sm: var SessionManager;
                             userId: UserId;
                             toolCatalogSignature: string): EnsureSessionPlan =
  let lease = sm.prepareEntry(userId, toolCatalogSignature)
  EnsureSessionPlan(
    uid: $userId,
    isNew: lease.isNew,
    rebuilt: lease.rebuilt,
    oldInbox: lease.oldInbox,
    oldAskInbox: lease.oldAskInbox,
    entry: lease.entry,
  )

proc buildSessionIngressContext*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 toolCatalogSignature: string;
                                 msgSeq: var int): SessionIngressContext =
  result.plan = sm.buildEnsureSessionPlan(msg.userId, toolCatalogSignature)
  inc msgSeq
  result.msgId = $msg.userId & "-" & $msgSeq

func buildSessionIngressServices*(memory: MdFileAdapter;
                                  completeFn: CompleteFn;
                                  streamFn: StreamFn;
                                  toolClients: seq[McpClientAdapter];
                                  tools: seq[ToolDescription];
                                  globalOutbox: AsyncQueue[OutboundMessage];
                                  log: Logger;
                                  sandboxMode: SandboxMode;
                                  sandboxImage: string;
                                  typingFn: TypingFn;
                                  searchFn: SearchFn): SessionIngressServices =
  SessionIngressServices(
    memory: memory,
    completeFn: completeFn,
    streamFn: streamFn,
    toolClients: toolClients,
    tools: tools,
    globalOutbox: globalOutbox,
    log: log,
    sandboxMode: sandboxMode,
    sandboxImage: sandboxImage,
    typingFn: typingFn,
    searchFn: searchFn,
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
    ctx.services.globalCompleteFn,
    ctx.services.globalStreamFn,
    ctx.services.toolClients,
    ctx.services.tools,
    ctx.runtime.globalOutbox,
    log,
    cfg.sandboxMode,
    cfg.sandboxImage,
    nil,
    ctx.services.globalSearchFn,
  )

proc startSessionOrchestrator*(plan: EnsureSessionPlan;
                               memory: MdFileAdapter;
                               streamFn: StreamFn;
                               bootstrap: SessionBootstrap;
                               globalOutbox: AsyncQueue[OutboundMessage];
                               log: Logger;
                               sandboxMode: SandboxMode;
                               sandboxImage: string;
                               typingFn: TypingFn;
                               searchFn: SearchFn) {.gcsafe.} =
  if not (plan.isNew or plan.rebuilt):
    return
  if plan.rebuilt and not plan.oldAskInbox.isNil:
    plan.oldAskInbox.addLastNoWait("__DONKEY_ASK_CANCELLED__")
  if plan.rebuilt and not plan.oldInbox.isNil:
    plan.oldInbox.addLastNoWait(newCancelMsg())
  asyncSpawn runOrchestrator(plan.entry[].inbox, plan.entry, globalOutbox, memory,
                             bootstrap.completeFn, streamFn,
                             bootstrap.clients, bootstrap.tools,
                             bootstrap.paddockDir,
                             typingFn, searchFn, log.child("orch"), bootstrap.providerLabel,
                             bootstrap.skillPrompt,
                             sandboxMode, sandboxImage)

proc enqueueSessionMessage*(entry: var SessionEntry;
                            msg: InboundMessage;
                            msgId: string) =
  if entry.awaitingAsk:
    entry.awaitingAsk = false
    entry.askInbox.addLastNoWait(msg.text)
  else:
    entry.inbox.addLastNoWait(buildSessionTaskMsg(msg, msgId))

proc startSessionIngress*(sm: var SessionManager;
                          msg: InboundMessage;
                          services: SessionIngressServices;
                          msgSeq: var int): SessionIngressContext {.gcsafe.} =
  let bootstrap = buildSessionBootstrap(
    services.memory, msg.userId, services.completeFn, services.toolClients, services.tools)
  let signature = toolCatalogSignature(
    bootstrap.tools, bootstrap.providerLabel, bootstrap.paddockDir, bootstrap.skillPrompt)
  result = sm.buildSessionIngressContext(msg, signature, msgSeq)
  startSessionOrchestrator(result.plan, services.memory,
                           services.streamFn, bootstrap,
                           services.globalOutbox, services.log,
                           services.sandboxMode, services.sandboxImage,
                           services.typingFn, services.searchFn)
  if result.plan.isNew:
    services.log.info("new session: " & result.plan.uid)
  elif result.plan.rebuilt:
    services.log.info("rebuilt session runtime after tool catalog change: " & result.plan.uid)

proc finalizeSessionIngress*(sm: var SessionManager;
                             ingress: SessionIngressContext;
                             msg: InboundMessage) =
  sm.recordChannel(msg.userId, msg.channel, msg.channelId)
  enqueueSessionMessage(ingress.plan.entry[], msg, ingress.msgId)

proc ensureSession(sm:       var SessionManager;
                   msg:      InboundMessage;
                   services: SessionIngressServices;
                   msgSeq:   var int) {.gcsafe.} =
  ## Creates session + orchestrator on first contact; then enqueues message.
  ## Fire-and-forget: does NOT wait for reply.
  let ingress = startSessionIngress(sm, msg, services, msgSeq)
  finalizeSessionIngress(sm, ingress, msg)

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

proc stageTelegramFallbackStatus(runtime: var DaemonRuntime;
                                 tgAdapter: var TelegramAdapter;
                                 msg: InboundMessage) =
  tgAdapter.sendTyping(msg.userId).isOkOr: discard
  let statusId = tgAdapter.sendStatus(msg.userId, "⚙️",
                                      replyTo = msg.channelId).valueOr: ""
  if statusId.len > 0:
    runtime.statusMsgIds[$msg.userId] = statusId

proc handleTelegramFallback(runtime:      var DaemonRuntime;
                            tgAdapter:    var TelegramAdapter;
                            msg:          InboundMessage;
                            services:     SessionIngressServices) =
  stageTelegramFallbackStatus(runtime, tgAdapter, msg)
  handleSessionFallback(runtime, msg, services)

proc drainTelegramEvents(runtime:      var DaemonRuntime;
                         tgAdapter:    var TelegramAdapter;
                         services:     SessionIngressServices;
                         log:          Logger): bool =
  let tgMsgs = tgAdapter.receive().valueOr:
    log.error("telegram receive: " & error)
    return false

  for msg in tgMsgs:
    if not telegram_runtime.handleTelegramMessage(
      msg, runtime.sm, tgAdapter, runtime.kbdMsgIds, services.memory, buildCompleteFn,
      services.toolClients.len, services.tools.len, runtime.msgSeq, runtime.daemonStartMs):
      handleTelegramFallback(runtime, tgAdapter, msg, services)
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

proc clearTelegramStatus(runtime:   var DaemonRuntime;
                         tgAdapter: var TelegramAdapter;
                         outMsg:    OutboundMessage) =
  let uidStr = $outMsg.userId
  if outMsg.channel != ckTelegram or outMsg.isPartial or uidStr notin runtime.statusMsgIds:
    return

  let isError = outMsg.text.startsWith("Desculpe") or
                outMsg.text.startsWith("Tool call loop")
  if isError:
    tgAdapter.editStatus(outMsg.userId, runtime.statusMsgIds[uidStr], "❌").isOkOr: discard
  else:
    tgAdapter.deleteMessage(outMsg.userId, runtime.statusMsgIds[uidStr]).isOkOr: discard
  runtime.statusMsgIds.del(uidStr)

proc drainGlobalOutbox(runtime:  var DaemonRuntime;
                       adapters: var DaemonAdapters;
                       log:      Logger) =
  while runtime.globalOutbox.len > 0:
    let outMsg = runtime.globalOutbox.getNoWait()
    clearTelegramStatus(runtime, adapters.tg, outMsg)
    routeOutbound(outMsg, adapters.tg, adapters.dc, adapters.wc, adapters.wch,
                  adapters.qq, adapters.fs,
                  log, runtime.streamMsgIds)

proc startDaemonIngress(ctx: DaemonContext;
                        log: Logger) =
  startOptionalDiscordGateway(ctx.adapters.dc, ctx.env.discordToken, log)
  startOptionalWeComGateway(ctx.adapters.wc, ctx.env.wecomCorpId, log)
  startOptionalWeChatGateway(ctx.adapters.wch, ctx.env.wechatAppId, log)
  startOptionalFeishuGateway(ctx.adapters.fs, ctx.env.feishuAppId, log)
  startOptionalQQGateway(ctx.adapters.qq, ctx.env.qqApiBase, log)
  ctx.adapters.tg.setMyCommands().isOkOr:
    log.warn("setMyCommands failed: " & error)

proc setupDaemonRuntime(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        log: Logger) =
  setupIpcServer(cfg, ctx.runtime.sm, ctx.services.tools.len, ctx.runtime.daemonStartMs,
                 ctx.env.telegramToken, ctx.env.discordToken, ctx.env.wecomCorpId,
                 ctx.env.wechatAppId, ctx.env.feishuAppId, ctx.env.qqApiBase, log)

proc activateDaemonBootstrap(ctx: DaemonContext;
                             cfg: DonkeyConfig;
                             log: Logger) =
  startDaemonIngress(ctx, log)
  setupDaemonRuntime(ctx, cfg, log)

proc handleGatewayFallback(ctx: DaemonContext;
                           cfg: DonkeyConfig;
                           memory: MdFileAdapter;
                           msg: InboundMessage;
                           log: Logger) =
  handleSessionFallback(
    ctx.runtime,
    msg,
    buildDaemonSessionServices(ctx, cfg, memory, log),
  )

proc drainDiscordGateway(ctx: DaemonContext;
                         cfg: DonkeyConfig;
                         memory: MdFileAdapter;
                         log: Logger) =
  discord_runtime.drainDiscordEvents(
    ctx.runtime.sm, ctx.adapters.dc, ctx.env.discordToken, memory, buildCompleteFn,
    ctx.services.tools.len, ctx.services.toolClients.len, ctx.runtime.msgSeq, log,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainWeComGateway(ctx: DaemonContext;
                       cfg: DonkeyConfig;
                       memory: MdFileAdapter;
                       log: Logger) =
  wecom_runtime.drainWeComEvents(
    ctx.adapters.wc, ctx.env.wecomCorpId, memory,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainWeChatGateway(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  wechat_runtime.drainWeChatEvents(
    ctx.adapters.wch, ctx.env.wechatAppId,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainQQGateway(ctx: DaemonContext;
                    cfg: DonkeyConfig;
                    memory: MdFileAdapter;
                    log: Logger) =
  qq_runtime.drainQQEvents(
    ctx.adapters.qq, ctx.env.qqApiBase,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainFeishuGateway(ctx: DaemonContext;
                        cfg: DonkeyConfig;
                        memory: MdFileAdapter;
                        log: Logger) =
  feishu_runtime.drainFeishuEvents(
    ctx.adapters.fs, ctx.env.feishuAppId, memory,
    proc(msg: InboundMessage) =
      handleGatewayFallback(ctx, cfg, memory, msg, log))

proc drainTelegramGateway(ctx: DaemonContext;
                          cfg: DonkeyConfig;
                          memory: MdFileAdapter;
                          log: Logger): bool =
  let services =
    buildDaemonSessionServices(ctx, cfg, memory, log) |>->
    withTypingFn(ctx.services.tgTypingFn)
  drainTelegramEvents(ctx.runtime, ctx.adapters.tg, services, log)

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
  activateDaemonBootstrap(ctx, cfg, log)

  log.info("polling for messages…")
  while true:
    let loopResult = runDaemonLoop(ctx, cfg, memory, log)
    await sleepAsync(milliseconds(loopResult.sleepMs))

# ── main ───────────────────────────────────────────────────────────────────────

proc main =
  var configPath = ""
  var args: seq[string] = @[]
  var logsFollow = false
  var logsCat    = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "version": printVersion(); quit(0)
      of "help":    printHelp();    quit(0)
      of "config":  configPath = val
      of "cat":     logsCat    = true
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

  if configPath.len == 0:
    let home = resolveHome()
    configPath = home / ConfigFileName

  let cfg = loadConfig(configPath)
  ringInit()   ## enable ring buffer before the first Logger is created
  if isatty(stderr): enableHumanLog()
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
      ctlSkillInstall(skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 4 and args[1] == "skill" and args[2] == "search":
      ctlSkillSearchRemote(getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3]); quit(0)
    elif args.len == 4 and args[1] == "skill" and args[2] == "install":
      ctlSkillInstallRemote(cfg.home, getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), args[3]); quit(0)
    elif args.len >= 3 and args[1] == "skill" and args[2] == "list":
      ctlSkillList(cfg.home / "skills.toml"); quit(0)
    elif args.len >= 5 and args[1] == "skill" and args[2] == "update":
      let skillsPath = cfg.home / "skills.toml"
      ctlSkillUpdate(skillsPath, args[3], args[4], args[5 ..^ 1]); quit(0)
    elif args.len >= 3 and args[1] == "skill" and args[2] == "update":
      let slug = if args.len >= 4: args[3] else: ""
      ctlSkillUpdateRemote(cfg.home, getEnv("CLAWHUB_REGISTRY", ClawhubDefaultRegistry), slug); quit(0)
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
    elif args.len >= 4 and args[1] == "memory" and args[2] == "export":
      when defined(withPostgres):
        let pgDsn = getEnv("DONKEY_PG_DSN")
        if pgDsn.len == 0: echo "DONKEY_PG_DSN not set"; quit(1)
        let outDir = if args.len >= 5: args[4] else: ""
        ctlMemoryExport(pgDsn, args[3], outDir); quit(0)
      else:
        echo "Recompile with -d:withPostgres to use memory export"; quit(1)
    elif args.len >= 2 and args[1] == "status":
      let sockPath = cfg.home / SockFileName
      let sr = ipcClient.queryStatus(sockPath)
      if sr.isErr:
        echo "Error: " & sr.error; quit(1)
      let st = sr.value
      echo "Donkey status"
      echo "  Uptime:   " & $st.uptimeSec & "s"
      echo "  Sessions: " & $st.sessionCount
      echo "  Channels: " & st.channels.join(", ")
      echo "  Providers:" & st.providers.join(", ")
      echo "  Tools:    " & $st.toolsCount
      echo "  Memory:   " & st.memoryBackend
      if st.sessions.len > 0:
        echo "  Active sessions:"
        for s in st.sessions:
          echo "    " & s.userId & " [" & s.channels.join(", ") & "]"
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
      ctlServiceLogs(logsFollow, logsCat); quit(0)
    else: printHelp(); quit(1)

  if args.len >= 1 and args[0] == "tui":
    let sockPath = cfg.home / SockFileName
    runTui(sockPath)
    quit(0)

  log.info(AppSlug & " " & Version & " starting")
  log.info("home: " & cfg.home)

  waitFor startDaemon(cfg, log)

when isMainModule:
  main()
