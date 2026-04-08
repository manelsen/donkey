## Admin TUI — comprehensive administration panel.
##
## Sections: Config · Agents · Channels · Providers · Models · Hooks
## Keys: q/ESC=quit, Tab=next, Enter=select, Esc=back, arrows=navigate
##
## Requires illwill. Runs in foreground (no Chronos).

import std/[os, options, strutils, times]
import results
import illwill as ill
import terminal as term
import ../core/types
import ../config/types
import ../adapters/memory/md_file
import ../ports/provider

# Helper for drawing boxes
proc repeatChar*(n: int; c: char): string =
  result = newString(n)
  for i in 0 ..< n:
    result[i] = c

type
  AdminSection* = enum
    asConfig
    asAgents
    asChannels
    asProviders
    asModels
    asHooks
    asPlugins
    asUsers

  AdminItem* = object
    name*: string
    description*: string
    enabled*: bool
    status*: string

  AdminState* = object
    section*: AdminSection
    selectedIndex*: int
    items*: seq[AdminItem]
    selectedUserId*: Option[UserId]
    viewMode*: ViewMode
    confirmMode*: ConfirmMode
    config*: DonkeyConfig
    logLevel*: string
    verbose*: string
    reasoning*: string
    lastRefresh*: float
    catalogLoader*: ModelCatalogLoader
    runtimeProviders*: seq[string]
    runtimeChannels*: seq[string]
    runtimeSessionCount*: int
    memory*: MdFileAdapter
    toast*: Option[Toast]

  ChannelInfo* = object
    name*: string
    enabled*: bool
    adapter*: string

  ChannelItem* = object
    name*: string
    enabled*: bool
    status*: string
    botName*: string
    userCount*: int

  ChannelMetrics* = object
    messagesIn*: int
    messagesOut*: int
    errors*: int
    avgResponseTimeMs*: int

  SparklineTrend* = enum
    stUp
    stStable
    stDown
    stSpike

  SparklineData* = object
    label*: string
    points*: seq[float]
    current*: float
    trend*: SparklineTrend

  HistogramBucket* = object
    label*: string
    count*: int
    percentage*: float

  AlertLevel* = enum
    alInfo
    alWarning
    alCritical

  AlertThreshold* = object
    metric*: string
    warning*: int
    critical*: int
    enabled*: bool

  Alert* = object
    level*: AlertLevel
    message*: string
    timestamp*: int64

  TokenUsage* = object
    inputTokens*: int64
    outputTokens*: int64
    costUsd*: float

  HookItem* = object
    name*: string
    hookType*: string
    enabled*: bool
    execCount*: int
    lastRun*: int64

  ToolItem* = object
    name*: string
    server*: string
    enabled*: bool
    execCount*: int
    errors*: int

  SkillItem* = object
    name*: string
    path*: string
    enabled*: bool
    manifest*: string

  ConfigNodeKind* = enum
    ckString
    ckInt
    ckBool
    ckList

  ConfigNode* = object
    key*: string
    value*: string
    kind*: ConfigNodeKind
    changed*: bool

  ConfigDiff* = object
    key*: string
    oldValue*: string
    newValue*: string

  ConfigSnapshot* = object
    timestamp*: int64
    note*: string
    entries*: seq[(string, string)]

  SessionItem* = object
    sessionId*: string
    userId*: string
    channel*: string
    messageCount*: int
    ageSeconds*: int

  SessionMessage* = object
    role*: string
    text*: string
    timestamp*: int64

  DaemonHealthStatus* = enum
    dhsRunning
    dhsDegraded
    dhsError

  DaemonHealth* = object
    uptimeSec*: int64
    pid*: int32
    version*: string
    memoryMb*: int64
    threadCount*: int
    lastHeartbeat*: float
    status*: DaemonHealthStatus

  LogFilter* = object
    levels*: seq[string]
    subsystem*: string

  ProviderInfo* = object
    name*: string
    enabled*: bool
    models*: seq[string]
    priority*: int

  ProviderItem* = object
    name*: string
    enabled*: bool
    status*: string
    model*: string
    endpoint*: string

  ProviderTestResult* = object
    provider*: string
    success*: bool
    latencyMs*: int
    message*: string

  MetricsTimeRange* = enum
    mtr1h
    mtr24h
    mtr7d

  ProviderMetrics* = object
    totalRequests*: int
    successful*: int
    failed*: int
    avgLatencyMs*: int

  AgentInfo* = object
    name*: string
    personality*: string
    model*: string
    channels*: seq[string]

  ViewMode* = enum
    vmList
    vmDetail

  CommandPalette* = object
    query*: string
    results*: seq[string]
    selectedIndex*: int

  ToastKind* = enum
    tkSuccess
    tkWarning
    tkError
    tkInfo

  Toast* = object
    message*: string
    kind*: ToastKind
    timestamp*: int64

  ConfirmMode* = enum
    cmNone
    cmDelete
    cmRevoke

func statusColor*(s: string): ill.ForegroundColor =
  case s
  of "healthy", "ok": ill.fgGreen
  of "degraded", "warning": ill.fgYellow
  of "error", "failed": ill.fgRed
  else: ill.fgWhite

const
  BorderColor* = ill.fgBlue
  HeaderColor* = ill.fgCyan
  SelectedBg* = ill.bgCyan
  ItemColor* = ill.fgWhite
  DisabledColor* = ill.fgCyan  ## visible but dimmed on dark terminals
  StatusOk* = ill.fgGreen
  StatusError* = ill.fgRed

proc newAdminState*(cfg: DonkeyConfig = defaultConfig("")): AdminState =
  AdminState(
    section: asConfig,
    selectedIndex: 0,
    items: @[],
    selectedUserId: UserId.none(),
    viewMode: vmList,
    confirmMode: cmNone,
    config: cfg,
    logLevel: "info",
    verbose: "default",
    reasoning: "auto",
  )

# ── Section Labels ───────────────────────────────────────────────────────────

func sectionLabel*(s: AdminSection): string =
  case s
  of asConfig:    "[Config]"
  of asAgents:    "[Agents]"
  of asChannels:  "[Channels]"
  of asProviders: "[Providers]"
  of asModels:    "[Models]"
  of asHooks:     "[Hooks]"
  of asPlugins:    "[Plugins]"
  of asUsers:     "[Users]"

func sectionLabels*(): seq[string] =
  for s in AdminSection:
    result.add(sectionLabel(s))

# ── Load sample data ─────────────────────────────────────────────────────────

proc loadConfigItems*(st: var AdminState) =
  st.items = @[
    AdminItem(name: "home", description: st.config.home, enabled: true, status: ""),
    AdminItem(name: "log_level", description: $st.config.logLevel, enabled: true, status: ""),
    AdminItem(name: "paddocks", description: st.config.paddocks, enabled: true, status: ""),
    AdminItem(name: "sandbox_mode", description: $st.config.sandboxMode, enabled: true, status: ""),
    AdminItem(name: "dm_policy", description: $st.config.dmPolicy, enabled: true, status: ""),
    AdminItem(name: "verbose", description: st.verbose, enabled: true, status: ""),
    AdminItem(name: "reasoning", description: st.reasoning, enabled: true, status: ""),
  ]

proc loadAgentItems*(st: var AdminState) =
  st.items = @[
    AdminItem(name: "default", description: "Default agent", enabled: true, status: "active"),
    AdminItem(name: "coder", description: "Code-specialized agent", enabled: true, status: "active"),
    AdminItem(name: "researcher", description: "Research-focused agent", enabled: false, status: "idle"),
  ]

proc loadChannelItems*(st: var AdminState) =
  ## Load channels from runtime daemon status when available.
  if st.runtimeChannels.len > 0:
    st.items = @[]
    for ch in st.runtimeChannels:
      st.items.add(AdminItem(
        name: ch,
        description: ch.capitalizeAscii() & " channel",
        enabled: true,
        status: "connected"
      ))
  else:
    ## Fallback when no daemon is running.
    st.items = @[
      AdminItem(name: "cli", description: "Command-line interface", enabled: true, status: "active"),
    ]

proc loadProviderItems*(st: var AdminState) =
  ## Load providers from runtime daemon status when available,
  ## otherwise fall back to all known providers.
  if st.runtimeProviders.len > 0:
    st.items = @[]
    for p in st.runtimeProviders:
      st.items.add(AdminItem(
        name: p,
        description: "Active provider",
        enabled: true,
        status: "connected"
      ))
  else:
    const knownProviders = ["anthropic", "zai-anthropic", "openai", "openrouter", "gemini",
                           "deepseek", "ollama", "minimax", "zhipu"]
    st.items = @[]
    for p in knownProviders:
      st.items.add(AdminItem(
        name: p,
        description: "Provider",
        enabled: false,
        status: "not configured"
      ))

proc loadModelItems*(st: var AdminState) =
  ## When catalogLoader is wired (dashboard), fetch live models from provider
  ## APIs. Otherwise fall back to a static list.
  if st.catalogLoader != nil:
    var loaded: seq[AdminItem]
    var seenProviders: seq[string]
    # Collect models from runtime providers first
    for prov in st.runtimeProviders:
      seenProviders.add(prov)
      let catalog = st.catalogLoader(prov)
      if catalog.isOk:
        for entry in catalog.get().entries:
          loaded.add(AdminItem(
            name: entry.modelName,
            description: entry.providerName & "/" & entry.label,
            enabled: entry.available,
            status: catalogSourceLabel(catalog.get().source),
          ))
    # Also fetch from known providers not yet covered
    const knownProviders = ["anthropic", "zai-anthropic", "openrouter", "gemini", "deepseek", "ollama", "minimax", "zhipu"]
    for prov in knownProviders:
      if prov in seenProviders: continue
      let catalog = st.catalogLoader(prov)
      if catalog.isOk:
        for entry in catalog.get().entries:
          loaded.add(AdminItem(
            name: entry.modelName,
            description: entry.providerName & "/" & entry.label,
            enabled: entry.available,
            status: catalogSourceLabel(catalog.get().source),
          ))
    if loaded.len > 0:
      st.items = loaded
      return
  # Static fallback — used when catalogLoader is nil (tests) or no data returned
  st.items = @[
    AdminItem(name: "claude-opus-4-6", description: "Anthropic Claude Opus 4", enabled: true, status: "static"),
    AdminItem(name: "claude-sonnet-4-5", description: "Anthropic Claude Sonnet 4.5", enabled: true, status: "static"),
    AdminItem(name: "gpt-4o-mini", description: "OpenAI GPT-4o Mini", enabled: true, status: "static"),
    AdminItem(name: "gpt-4o", description: "OpenAI GPT-4o", enabled: true, status: "static"),
    AdminItem(name: "deepseek-chat", description: "DeepSeek Chat", enabled: false, status: "static"),
    AdminItem(name: "gemini-2.5-flash", description: "Google Gemini 2.0 Flash", enabled: false, status: "static"),
    AdminItem(name: "glm-4.7", description: "Zhipu GLM-4.7", enabled: false, status: "static"),
    AdminItem(name: "llama3", description: "Meta Llama 3 via Ollama", enabled: false, status: "static"),
    AdminItem(name: "abab6.5s-chat", description: "MiniMax ABAB 6.5s", enabled: false, status: "static"),
    AdminItem(name: "openai/gpt-4o-mini", description: "OpenRouter GPT-4o Mini", enabled: true, status: "static"),
  ]

proc loadHookItems*(st: var AdminState) =
  st.items = @[
    AdminItem(name: "rag_context", description: "RAG context injection", enabled: true, status: "active"),
    AdminItem(name: "memory_capture", description: "Memory capture hook", enabled: true, status: "active"),
    AdminItem(name: "context_injection", description: "Context injection", enabled: true, status: "active"),
    AdminItem(name: "spam_filter", description: "Spam detection", enabled: false, status: "disabled"),
  ]

proc loadPluginItems*(st: var AdminState) =
  st.items = @[
    AdminItem(name: "shell", description: "Shell command execution", enabled: true, status: "active"),
    AdminItem(name: "git", description: "Git operations", enabled: true, status: "active"),
    AdminItem(name: "fetch", description: "HTTP fetch tool", enabled: true, status: "active"),
    AdminItem(name: "mcp", description: "MCP client adapter", enabled: false, status: "disabled"),
  ]

proc loadUsersItems*(st: var AdminState) =
  ## Load users from memory adapter into AdminItem list.
  if st.memory.paddocksDir.len == 0: return
  let users = st.memory.listUsers()
  st.items = @[]
  for u in users:
    st.items.add(AdminItem(
      name: $u.userId,
      description: u.preferredName,
      enabled: u.access != "revoked",
      status: u.access
    ))

proc loadSection*(st: var AdminState) =
  case st.section
  of asConfig:    st.loadConfigItems()
  of asAgents:    st.loadAgentItems()
  of asChannels:  st.loadChannelItems()
  of asProviders: st.loadProviderItems()
  of asModels:    st.loadModelItems()
  of asHooks:     st.loadHookItems()
  of asPlugins:   st.loadPluginItems()
  of asUsers:     st.loadUsersItems()

proc showToast*(st: var AdminState; msg: string; kind = tkInfo) =
  st.toast = some(Toast(message: msg, kind: kind, timestamp: int64(times.epochTime())))

proc clearExpiredToast*(st: var AdminState) =
  if st.toast.isSome:
    let age = int64(times.epochTime()) - st.toast.get().timestamp
    if age > 3:
      st.toast = Toast.none()

proc cycleConfigValue*(st: var AdminState; index: int) =
  ## Cycle through valid values for the selected config field.
  if index < 0 or index >= st.items.len: return
  let key = st.items[index].name
  case key
  of "log_level":
    const levels = ["debug", "info", "warn", "error"]
    let cur = st.items[index].description
    var next = 0
    for i, l in levels:
      if l == cur: next = (i + 1) mod levels.len; break
    st.items[index].description = levels[next]
    st.config.logLevel = parseLogLevel(levels[next])
    st.showToast("log_level -> " & levels[next], tkSuccess)
  of "sandbox_mode":
    const modes = ["none", "oci"]
    let cur = st.items[index].description
    var next = 0
    for i, m in modes:
      if m == cur: next = (i + 1) mod modes.len; break
    st.items[index].description = modes[next]
    st.showToast("sandbox_mode -> " & modes[next], tkSuccess)
  of "verbose":
    let cur = st.items[index].description
    let next = if cur == "default": "verbose" else: "default"
    st.items[index].description = next
    st.showToast("verbose -> " & next, tkSuccess)
  of "reasoning":
    const vals = ["auto", "always", "never"]
    let cur = st.items[index].description
    var next = 0
    for i, v in vals:
      if v == cur: next = (i + 1) mod vals.len; break
    st.items[index].description = vals[next]
    st.showToast("reasoning -> " & vals[next], tkSuccess)
  else: discard
# ── Rendering ───────────────────────────────────────────────────────────────

proc drawBorder*(tb: var ill.TerminalBuffer; x, y, w, h: int) =
  tb.setForegroundColor(BorderColor)
  tb.write(x, y, "+" & repeatChar(w - 2, '-') & "+")
  for i in 1 ..< h - 1:
    tb.write(x, y + i, "|" & repeatChar(w - 2, ' ') & "|")
  tb.write(x, y + h - 1, "+" & repeatChar(w - 2, '-') & "+")
  tb.setForegroundColor(ItemColor)

proc drawHeader*(tb: var ill.TerminalBuffer; width: int) =
  tb.setForegroundColor(ill.fgBlack)
  tb.setBackgroundColor(ill.bgCyan)
  let title = " Donkey Admin Panel "
  let keys = " [q]uit  [<- ->]section  [^ v]navigate  [Enter]toggle "
  tb.write(0, 0, title & repeatChar(width - title.len - keys.len, ' ') & keys)
  tb.setBackgroundColor(ill.bgNone)
  tb.setForegroundColor(ItemColor)

proc drawSections*(tb: var ill.TerminalBuffer; st: AdminState; y: int) =
  let x = 1
  var currentX = x
  for i in 0 ..< (high(AdminSection).ord + 1):
    let s = AdminSection(i)
    if i == ord(st.section):
      tb.setForegroundColor(ill.fgBlack)
      tb.setBackgroundColor(ill.bgCyan)
    else:
      tb.setForegroundColor(ill.fgWhite)
      tb.setBackgroundColor(ill.bgNone)
    let label = " " & sectionLabel(s) & " "
    tb.write(currentX, y, label)
    inc currentX, label.len
    tb.setBackgroundColor(ill.bgNone)

proc drawItem*(tb: var ill.TerminalBuffer; item: AdminItem; x, y, w: int; selected: bool; index: int) =
  if selected:
    tb.setForegroundColor(ill.fgBlack)
    tb.setBackgroundColor(ill.bgCyan)
    tb.write(x, y, "> ")
  else:
    tb.setForegroundColor(ItemColor)
    tb.write(x, y, "  ")

  let nameStr = item.name & repeatChar(18 - item.name.len, ' ')
  let statusColor = if item.status == "error" or item.status == "disconnected": StatusError
                     elif item.enabled: StatusOk
                     else: DisabledColor
  tb.setForegroundColor(if item.enabled: ItemColor else: DisabledColor)
  tb.write(x + 2, y, nameStr)
  tb.setForegroundColor(ill.fgCyan)
  tb.write(x + 22, y, "| ")
  tb.setForegroundColor(if item.enabled: ill.fgWhite else: ill.fgCyan)
  let descTrunc = if item.description.len > 30: item.description[0 .. 27] & "..."
                  else: item.description
  tb.write(x + 24, y, descTrunc)
  tb.setForegroundColor(statusColor)
  tb.write(x + w - 12, y, "[" & item.status & "]")
  if not item.enabled:
    tb.setForegroundColor(DisabledColor)
    tb.write(x + w - 4, y, "X")
  tb.setBackgroundColor(ill.bgNone)
  tb.setForegroundColor(ItemColor)

proc deleteUserPaddock*(paddockDir: string) =
  ## Delete a user's paddock directory.
  removeDir(paddockDir)

proc drawUserDetail*(tb: var ill.TerminalBuffer; st: AdminState; adapter: MdFileAdapter; startY: int; width, height: int) =
  if st.selectedUserId.isNone:
    tb.setForegroundColor(ill.fgYellow)
    tb.write(2, startY, "Select a user and press Enter to view details")
    return

  let userId = st.selectedUserId.get()
  let ctx = adapter.loadContext(userId)
  var y = startY

  tb.setForegroundColor(ill.fgCyan)
  tb.write(2, y, "+- User Details -")
  tb.setForegroundColor(ill.fgWhite)
  tb.write(width - 3, y, "-+")
  inc y, 2

  tb.setForegroundColor(ill.fgBlue)
  tb.write(2, y, "UUID: ")
  tb.setForegroundColor(ill.fgWhite)
  tb.write(8, y, $userId)
  inc y

  if ctx.userMd.len > 0:
    tb.setForegroundColor(ill.fgBlue)
    tb.write(2, y, "Profile:")
    inc y
    for line in ctx.userMd.splitLines:
      if y >= height - 2: break
      tb.setForegroundColor(ill.fgWhite)
      tb.write(4, y, line[0 .. min(line.high, width - 6)])
      inc y
    inc y

  if ctx.memoryMd.len > 0:
    tb.setForegroundColor(ill.fgBlue)
    tb.write(2, y, "Memory:")
    inc y
    for line in ctx.memoryMd.splitLines:
      if y >= height - 2: break
      tb.setForegroundColor(ill.fgWhite)
      tb.write(4, y, line[0 .. min(line.high, width - 6)])
      inc y
    inc y

  if ctx.preferencesMd.len > 0:
    tb.setForegroundColor(ill.fgBlue)
    tb.write(2, y, "Preferences:")
    inc y
    for line in ctx.preferencesMd.splitLines:
      if y >= height - 2: break
      tb.setForegroundColor(ill.fgWhite)
      tb.write(4, y, line[0 .. min(line.high, width - 6)])
      inc y

  tb.setForegroundColor(ill.fgCyan)
  tb.write(2, height - 2, "[Enter] toggle access  [D] delete  [Esc] back to list")

proc drawList*(tb: var ill.TerminalBuffer; st: AdminState; startY: int; width, height: int) =
  let listHeight = height - 4
  for i in 0 ..< min(st.items.len, listHeight):
    let item = st.items[i]
    let selected = i == st.selectedIndex
    let y = startY + 2 + i
    if y < height - 2:
      drawItem(tb, item, 2, y, width, selected, i)

proc drawFooter*(tb: var ill.TerminalBuffer; st: AdminState; y, width: int) =
  tb.setForegroundColor(ill.fgCyan)
  tb.write(2, y, "Items: " & $st.items.len & "  |  Selected: " & $st.selectedIndex)
  tb.write(width - 20, y, "ESC: back  Enter: toggle")

# ── Main TUI loop ───────────────────────────────────────────────────────────

proc runAdminTui*(cfg: DonkeyConfig = defaultConfig("")) =
  ill.illwillInit(fullScreen = true)
  defer: ill.illwillDeinit()

  var st = newAdminState(cfg)
  st.loadSection()

  var tb = ill.newTerminalBuffer(term.terminalHeight(), term.terminalWidth())

  while true:
    let height = tb.height
    let width = tb.width

    tb.clear()
    drawHeader(tb, width)
    drawSections(tb, st, 2)

    let titleY = 4
    tb.setForegroundColor(HeaderColor)
    tb.write(2, titleY, "+- " & sectionLabel(st.section) & " -")
    tb.setForegroundColor(ItemColor)
    tb.write(width - 3, titleY, "-+")

    drawList(tb, st, titleY, width, height - 3)
    drawFooter(tb, st, height - 2, width)

    tb.display()

    let key = ill.getKey()
    case key
    of ill.Key.Escape, ill.Key.Q:
      break
    of ill.Key.Left:
      st.section = AdminSection((ord(st.section) - 1 + (high(AdminSection).ord + 1)) mod (high(AdminSection).ord + 1))
      st.selectedIndex = 0
      st.loadSection()
    of ill.Key.Right:
      st.section = AdminSection((ord(st.section) + 1) mod (high(AdminSection).ord + 1))
      st.selectedIndex = 0
      st.loadSection()
    of ill.Key.Up:
      if st.selectedIndex > 0:
        dec st.selectedIndex
    of ill.Key.Down:
      if st.selectedIndex < st.items.high:
        inc st.selectedIndex
    of ill.Key.Enter:
      if st.items.len > 0 and st.selectedIndex < st.items.len:
        st.items[st.selectedIndex].enabled = not st.items[st.selectedIndex].enabled
    of ill.Key.Tab:
      st.section = AdminSection((ord(st.section) + 1) mod (high(AdminSection).ord + 1))
      st.selectedIndex = 0
      st.loadSection()
    of ill.Key.R:
      st.loadSection()
    else:
      discard

when isMainModule:
  runAdminTui()
