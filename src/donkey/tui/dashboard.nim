## Donkey TUI — live terminal dashboard.
##
## Connects to the daemon's Unix socket every RefreshMs to fetch status + logs.
## Three panels cycled with Tab: Sessions · Logs · Stats.
## Keys: q/Q=quit, Tab=next panel, r/R=force refresh.
##
## Requires illwill. Runs in foreground (no Chronos).

import std/[os, strformat, strutils, times]
import illwill
import ../core/pipeops
import ../adapters/ipc/[types, client]

const
  RefreshMs    = 2_000
  MaxLogLines  = 200   ## ring snapshot depth

type
  Panel = enum
    pSessions, pLogs, pStats

  TuiState = object
    status:    DaemonStatus
    logs:      seq[IpcLogEntry]
    sockPath:  string
    panel:     Panel
    lastFetch: float       ## epochTime() of last successful fetch
    fetchErr:  string      ## last error, "" = OK
    width:     int
    height:    int

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
      of pLogs:     "Logs"
      of pStats:    "Stats") & " "
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
  row("Sessions",        $st.status.sessionCount)
  row("Memory backend",  st.status.memoryBackend)
  row("Tools",           $st.status.toolsCount)
  row("Channels",        st.status.channels.join(", "))
  row("Providers",       st.status.providers.join(", "))
  row("Log entries",     $st.logs.len)

proc render(tb: var TerminalBuffer; st: TuiState) =
  tb.clear()
  drawHeader(tb, st)
  drawPanelBar(tb, st.panel)
  tb.drawHorizLine(0, tb.width - 1, 2)
  let y0 = 3
  case st.panel
  of pSessions: drawSessions(tb, st, y0)
  of pLogs:     drawLogs(tb, st, y0)
  of pStats:    drawStats(tb, st, y0)
  drawFooter(tb, st)
  tb.display()

# ── entry point ───────────────────────────────────────────────────────────────

proc runTui*(sockPath: string) =
  illwillInit(fullScreen = true)
  defer: illwillDeinit()

  var st = TuiState(sockPath: sockPath, panel: pSessions)
  fetchData(st)
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

    ## Auto-refresh.
    if epochTime() - lastRefresh >= RefreshMs / 1000.0:
      fetchData(st)
      st.lastFetch = epochTime()
      lastRefresh  = epochTime()

    render(tb, st)

    ## Input (non-blocking, 100ms timeout).
    let key = getKeyWithTimeout(100)
    case key
    of Key.Q, Key.Escape:
      break
    of Key.Tab:
      st.panel = Panel((ord(st.panel) + 1) mod (ord(Panel.high) + 1))
    of Key.R:
      fetchData(st)
      st.lastFetch  = epochTime()
      lastRefresh   = epochTime()
    else:
      discard
