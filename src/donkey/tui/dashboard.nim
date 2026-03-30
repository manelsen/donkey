## Donkey TUI — live terminal dashboard.
##
## Connects to the daemon's Unix socket every RefreshMs to fetch status + logs.
## Three panels cycled with Tab: Sessions · Logs · Stats.
## Keys: q/Q=quit, Tab=next panel, r/R=force refresh.
##
## Requires illwill. Runs in foreground (no Chronos).

import std/[os, sequtils, strformat, strutils, times, options]
import illwill
import ../core/pipeops
import ../core/types
import ../adapters/ipc/[types, client]
import ../adapters/memory/md_file
import admin_tui
import ../adapters/provider/model_catalog

const
  RefreshMs    = 10_000
  MaxLogLines  = 200   ## ring snapshot depth

type
  Panel = enum
    pUsers, pSessions, pLogs, pStats, pAdmin

  TuiState = object
    status:    DaemonStatus
    logs:      seq[IpcLogEntry]
    users:     seq[UserSummary]
    sockPath:  string
    panel:     Panel
    lastFetch: float       ## epochTime() of last successful fetch
    fetchErr:  string      ## last error, "" = OK
    width:     int
    height:    int
    admin:     AdminState  ## admin panel state
    memory:    MdFileAdapter

# ── helpers ───────────────────────────────────────────────────────────────────

proc fmtUptime(sec: int64): string =
  let h = sec div 3600
  let m = (sec mod 3600) div 60
  let s = sec mod 60
  if h > 0: &"{h}h {m:02}m"
  elif m > 0: &"{m}m {s:02}s"
  else: &"{s}s"

proc levelColor(level: string): ForegroundColor =
  case level
  of "DBG": fgCyan
  of "WRN": fgYellow
  of "ERR": fgRed
  of "FTL": fgMagenta
  else:     fgGreen     ## INF

# ── data fetch ────────────────────────────────────────────────────────────────

proc fetchData(st: var TuiState) =
  let sr = queryStatus(st.sockPath)
  if sr.isErr:
    st.fetchErr = sr.error
    return
  st.status   = sr.value
  st.fetchErr = ""
  let lr = queryLogs(st.sockPath, MaxLogLines)
  if lr.isOk:
    st.logs = lr.value
  let homeDir = st.sockPath.parentDir()
  let memory = MdFileAdapter(paddocksDir: homeDir / "paddocks")
  st.memory = memory
  st.users = st.memory.listUsers()

  ## Wire IPC status into admin panel state.
  st.admin.runtimeProviders = st.status.providers
  st.admin.runtimeChannels = st.status.channels
  st.admin.runtimeSessionCount = st.status.sessionCount
  st.admin.memory = st.memory

# ── rendering ─────────────────────────────────────────────────────────────────

proc drawHeader(tb: var TerminalBuffer; st: TuiState) =
  let w  = tb.width
  tb.setForegroundColor(fgBlue, bright = true)
  tb.setBackgroundColor(bgBlue)
  let upStr  = "uptime: " & fmtUptime(st.status.uptimeSec)
  let sesStr = "sessions: " & $st.status.sessionCount
  let memStr = "mem: " & st.status.memoryBackend
  let title  = " Donkey  " & upStr & "  " & sesStr & "  " & memStr
  let keys   = " [q]uit [tab]panel [r]refresh "
  let pad    = max(0, w - title.len - keys.len)
  tb.write(0, 0, title & spaces(pad) & keys)
  tb.setBackgroundColor(bgNone)

proc drawPanelBar(tb: var TerminalBuffer; active: Panel) =
  tb.setForegroundColor(fgWhite)
  let y = 1
  var x = 1
  for p in Panel:
    let label = " " & (case p
      of pSessions: "Sessions"
      of pUsers:    "Users"
      of pLogs:     "Logs"
      of pStats:    "Stats"
      of pAdmin:    "Admin") & " "
    if p == active:
      tb.setForegroundColor(fgBlack)
      tb.setBackgroundColor(bgWhite)
    else:
      tb.setForegroundColor(fgWhite)
      tb.setBackgroundColor(bgNone)
    tb.write(x, y, label)
    x += label.len + 1
  tb.setForegroundColor(fgWhite)
  tb.setBackgroundColor(bgNone)

proc drawFooter(tb: var TerminalBuffer; st: TuiState) =
  let y = tb.height - 1
  if st.fetchErr.len > 0:
    tb.setForegroundColor(fgRed)
    tb.write(1, y, "Error: " & st.fetchErr[0 ..< min(st.fetchErr.len, tb.width - 10)])
  else:
    tb.setForegroundColor(fgBlack, bright = true)
    let ago = int(epochTime() - st.lastFetch)
    tb.write(1, y, &"Last refresh: {ago}s ago")
  tb.setForegroundColor(fgWhite)
  tb.setBackgroundColor(bgNone)

proc drawUsers(tb: var TerminalBuffer; st: TuiState; y0: int) =
  let maxY = tb.height - 2
  var y = y0
  if st.users.len == 0:
    tb.setForegroundColor(fgBlack, bright = true)
    tb.write(2, y, "(no users)")
    return
  for user in st.users:
    if y >= maxY: break
    let name = if user.preferredName.len > 0: user.preferredName else: "-"
    let accessColor = if user.access.toLowerAscii() == "revoked": fgRed else: fgGreen
    tb.setForegroundColor(fgCyan)
    tb.write(2, y, $user.userId)
    tb.setForegroundColor(fgWhite)
    tb.write(40, y, name)
    tb.setForegroundColor(accessColor)
    tb.write(max(60, tb.width - 12), y, user.access)
    inc y

proc drawSessions(tb: var TerminalBuffer; st: TuiState; y0: int) =
  let maxY = tb.height - 2
  var y    = y0
  if st.status.sessions.len == 0:
    tb.setForegroundColor(fgBlack, bright = true)
    tb.write(2, y, "(no active sessions)")
    return
  for s in st.status.sessions:
    if y >= maxY: break
    tb.setForegroundColor(fgCyan)
    tb.write(2, y, s.userId)
    let chans = s.channels.join(", ")
    tb.setForegroundColor(fgWhite)
    tb.write(2 + s.userId.len + 2, y, "[" & chans & "]")
    inc y

proc drawLogs(tb: var TerminalBuffer; st: TuiState; y0: int) =
  let maxY  = tb.height - 2
  let avail = maxY - y0
  if avail <= 0: return
  ## Show last `avail` entries.
  let start = max(0, st.logs.len - avail)
  var y     = y0
  for i in start ..< st.logs.len:
    if y >= maxY: break
    let e = st.logs[i]
    tb.setForegroundColor(fgBlack, bright = true)
    tb.write(1, y, e.ts & " ")
    tb.setForegroundColor(levelColor(e.level))
    tb.write(1 + e.ts.len + 1, y, e.level & " ")
    tb.setForegroundColor(fgBlack, bright = true)
    tb.write(1 + e.ts.len + 1 + e.level.len + 1, y, "[" & e.subsys & "] ")
    let msgX  = 1 + e.ts.len + 1 + e.level.len + 1 + e.subsys.len + 3
    let avW   = max(0, tb.width - msgX - 1)
    let msgTr = if e.msg.len > avW: e.msg[0 ..< avW] else: e.msg
    tb.setForegroundColor(fgWhite)
    tb.write(msgX, y, msgTr)
    inc y

proc drawStats(tb: var TerminalBuffer; st: TuiState; y0: int) =
  var y = y0
  template row(label: string; val: string) {.dirty.} =
    tb.setForegroundColor(fgBlue, bright = true)
    tb.write(2, y, label & ": ")
    tb.setForegroundColor(fgWhite)
    tb.write(2 + label.len + 2, y, val)
    inc y

  row("Uptime",          fmtUptime(st.status.uptimeSec))
  row("Users",           $st.users.len)
  row("Sessions",        $st.status.sessionCount)
  row("Memory backend",  st.status.memoryBackend)
  row("Tools",           $st.status.toolsCount)
  row("Channels",        st.status.channels.join(", "))
  row("Providers",       st.status.providers.join(", "))
  row("Top routes",
      if st.status.routeCounts.len == 0:
        "-"
      else:
        st.status.routeCounts.mapIt(it.route & " (" & $it.count & ")").join(", "))
  row("Route metrics",
      if st.status.routeMetrics.len == 0:
        "-"
      else:
        st.status.routeMetrics.mapIt(
          it.route & " ok:" & $it.okCalls & "/" & $it.calls &
          " err:" & $it.errCalls &
          " avg:" & $it.avgLatencyMs & "ms").join(", "))
  row("Recent route metrics",
      if st.status.recentRouteMetrics.len == 0:
        "-"
      else:
        st.status.recentRouteMetrics.mapIt(
          it.route & " ok:" & $it.okCalls & "/" & $it.calls &
          " err:" & $it.errCalls &
          " avg:" & $it.avgLatencyMs & "ms").join(", "))
  row("Recent provider metrics",
      if st.status.recentProviderMetrics.len == 0:
        "-"
      else:
        st.status.recentProviderMetrics.mapIt(
          it.providerName & " ok:" & $it.okCalls & "/" & $it.calls &
          " err:" & $it.errCalls &
          " avg:" & $it.avgLatencyMs & "ms").join(", "))
  row("Provider cooldowns",
      if st.status.providerCooldowns.len == 0:
        "-"
      else:
        st.status.providerCooldowns.join(", "))
  row("Log entries",     $st.logs.len)

proc drawAdmin(tb: var TerminalBuffer; st: TuiState; y0: int) =
  let admin = st.admin
  let width = tb.width
  let height = tb.height

  ## Section tabs
  var currentX = 2
  for i in 0 ..< (high(AdminSection).ord + 1):
    let s = AdminSection(i)
    if i == ord(admin.section):
      tb.setForegroundColor(fgBlack)
      tb.setBackgroundColor(bgCyan)
    else:
      tb.setForegroundColor(fgWhite)
      tb.setBackgroundColor(bgNone)
    let label = " " & sectionLabel(s) & " "
    tb.write(currentX, y0, label)
    inc currentX, label.len
  tb.setBackgroundColor(bgNone)
  tb.setForegroundColor(fgWhite)

  ## Items list
  let listY = y0 + 2
  let listH = height - listY - 3

  if admin.viewMode == vmDetail and admin.selectedUserId.isSome:
    drawUserDetail(tb, admin, st.memory, listY, width, height)
  else:
    for i in 0 ..< min(admin.items.len, listH):
      let item = admin.items[i]
      let selected = i == admin.selectedIndex
      let y = listY + i
      if y >= height - 3: break
      if selected:
        tb.setForegroundColor(fgBlack)
        tb.setBackgroundColor(bgCyan)
        tb.write(2, y, "> ")
      else:
        tb.setBackgroundColor(bgNone)
        tb.setForegroundColor(fgWhite)
        tb.write(2, y, "  ")
      let nameStr = item.name & repeatChar(20 - min(item.name.len, 20), ' ')
      tb.setForegroundColor(if item.enabled: fgWhite else: DisabledColor)
      tb.write(4, y, nameStr)
      let maxDesc = width - 4 - 20 - 16
      let descTrunc = if maxDesc > 3 and item.description.len > maxDesc:
                        item.description[0 ..< maxDesc - 3] & "..."
                      elif maxDesc > 0:
                        item.description
                      else:
                        ""
      tb.setForegroundColor(if item.enabled: fgWhite else: DisabledColor)
      tb.write(26, y, descTrunc)
      let statusStr = "[" & item.status & "]"
      tb.setForegroundColor(if item.status == "connected" or item.status == "active" or
                              item.status == "healthy" or item.status == "default": fgGreen
                            elif item.status == "not configured" or item.status == "disabled": fgYellow
                            else: fgRed)
      tb.write(width - statusStr.len - 2, y, statusStr)
      if not item.enabled:
        tb.setForegroundColor(fgYellow)
        tb.write(width - 3, y, "X")
      tb.setBackgroundColor(bgNone)
      tb.setForegroundColor(fgWhite)

  ## Toast notification
  if admin.toast.isSome:
    let t = admin.toast.get()
    let toastColor = case t.kind
      of tkSuccess: fgGreen
      of tkWarning: fgYellow
      of tkError: fgRed
      of tkInfo: fgCyan
    tb.setForegroundColor(toastColor)
    tb.write(2, height - 3, t.message[0 ..< min(t.message.len, width - 4)])
    tb.setForegroundColor(fgWhite)

  ## Footer
  tb.setForegroundColor(fgCyan)
  let footerHint = case admin.section
    of asConfig: "[Enter] cycle value  [^ v] navigate"
    of asUsers: "[Enter] view detail  [Esc] back"
    else: "[Enter] toggle  [^ v] navigate  [<- ->] section"
  tb.write(2, height - 2, footerHint)
proc render(tb: var TerminalBuffer; st: TuiState) =
  tb.clear()
  drawHeader(tb, st)
  drawPanelBar(tb, st.panel)
  tb.drawHorizLine(0, tb.width - 1, 2)
  let y0 = 3
  case st.panel
  of pUsers:    drawUsers(tb, st, y0)
  of pSessions: drawSessions(tb, st, y0)
  of pLogs:     drawLogs(tb, st, y0)
  of pStats:    drawStats(tb, st, y0)
  of pAdmin:    drawAdmin(tb, st, y0)
  drawFooter(tb, st)
  tb.display()

# ── entry point ───────────────────────────────────────────────────────────────

proc runTui*(sockPath: string) =
  illwillInit(fullScreen = true)
  defer: illwillDeinit()

  var st = TuiState(sockPath: sockPath, panel: pSessions, admin: newAdminState(), memory: MdFileAdapter(paddocksDir: sockPath.parentDir() / "paddocks"))
  fetchData(st)
  st.admin.catalogLoader = buildModelCatalogLoader()
  st.lastFetch = epochTime()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  var lastRefresh = epochTime()

  while true:
    ## Handle resize.
    let w = terminalWidth()
    let h = terminalHeight()
    if w != st.width or h != st.height:
      st.width  = w
      st.height = h
      tb = newTerminalBuffer(w, h)

    ## Auto-refresh (fetch data before render).
    if epochTime() - lastRefresh >= RefreshMs / 1000.0:
      fetchData(st)
      st.lastFetch = epochTime()
      lastRefresh  = epochTime()

    ## Input (non-blocking, 100ms timeout).
    let key = getKeyWithTimeout(100)
    case key
    of Key.Q:
      break
    of Key.Escape:
      if st.panel == pAdmin:
        if st.admin.viewMode == vmDetail:
          st.admin.viewMode = vmList
          st.admin.selectedUserId = UserId.none()
        elif st.admin.confirmMode != cmNone:
          st.admin.confirmMode = cmNone
        else:
          break
      else:
        break
    of Key.Tab:
      st.panel = Panel((ord(st.panel) + 1) mod (ord(Panel.high) + 1))
      if st.panel == pAdmin:
        st.admin.loadSection()
    of Key.R:
      fetchData(st)
      st.lastFetch = epochTime()
      lastRefresh  = epochTime()
    of Key.Left:
      if st.panel == pAdmin:
        st.admin.section = AdminSection((ord(st.admin.section) - 1 + (high(AdminSection).ord + 1)) mod (high(AdminSection).ord + 1))
        st.admin.selectedIndex = 0
        st.admin.loadSection()
    of Key.Right:
      if st.panel == pAdmin:
        st.admin.section = AdminSection((ord(st.admin.section) + 1) mod (high(AdminSection).ord + 1))
        st.admin.selectedIndex = 0
        st.admin.loadSection()
    of Key.Up:
      if st.panel == pAdmin:
        if st.admin.selectedIndex > 0:
          dec st.admin.selectedIndex
    of Key.Down:
      if st.panel == pAdmin:
        if st.admin.selectedIndex < st.admin.items.high:
          inc st.admin.selectedIndex
    of Key.Enter:
      if st.panel == pAdmin:
        if st.admin.section == asUsers and st.admin.items.len > 0 and st.admin.selectedIndex < st.admin.items.len:
          if st.admin.viewMode == vmList:
            st.admin.selectedUserId = some(UserId(st.admin.items[st.admin.selectedIndex].name))
            st.admin.viewMode = vmDetail
          else:
            ## Toggle access
            st.admin.items[st.admin.selectedIndex].enabled = not st.admin.items[st.admin.selectedIndex].enabled
        elif st.admin.items.len > 0 and st.admin.selectedIndex < st.admin.items.len:
          st.admin.items[st.admin.selectedIndex].enabled = not st.admin.items[st.admin.selectedIndex].enabled
    of Key.D:
      if st.panel == pAdmin:
        if st.admin.viewMode == vmDetail and st.admin.selectedUserId.isSome:
          st.admin.confirmMode = cmDelete
    of Key.A:
      if st.panel != pAdmin:
        st.panel = pAdmin
        st.admin.loadSection()
    else:
      discard

    render(tb, st)
