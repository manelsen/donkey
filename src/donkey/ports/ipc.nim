## IPC contract types shared between daemon server and ctl client.
##
## Protocol: newline-terminated JSON, one request/response per connection.
## Commands:
##   {"cmd":"status"}       -> DaemonStatus
##   {"cmd":"logs","n":50}  -> last N IpcLogEntry records

import std/json

type
  SessionInfo* = object
    userId*:   string
    channels*: seq[string]

  RouteCount* = object
    route*: string
    count*: int

  RouteMetric* = object
    route*: string
    calls*: int
    okCalls*: int
    errCalls*: int
    avgLatencyMs*: int

  DaemonStatus* = object
    uptimeSec*:     int64
    sessionCount*:  int
    sessions*:      seq[SessionInfo]
    channels*:      seq[string]
    providers*:     seq[string]
    routeCounts*:   seq[RouteCount]
    routeMetrics*:  seq[RouteMetric]
    recentRouteMetrics*: seq[RouteMetric]
    toolsCount*:    int
    memoryBackend*: string

  IpcLogEntry* = object
    ts*:     string
    level*:  string
    subsys*: string
    msg*:    string

func toJson*(st: DaemonStatus): JsonNode =
  var sessions = newJArray()
  for s in st.sessions:
    var chans = newJArray()
    for c in s.channels:
      chans.add(%c)
    sessions.add(%*{"userId": s.userId, "channels": chans})
  var channels = newJArray()
  for c in st.channels:
    channels.add(%c)
  var providers = newJArray()
  for p in st.providers:
    providers.add(%p)
  var routeCounts = newJArray()
  for rc in st.routeCounts:
    routeCounts.add(%*{"route": rc.route, "count": rc.count})
  var routeMetrics = newJArray()
  for rm in st.routeMetrics:
    routeMetrics.add(%*{
      "route": rm.route,
      "calls": rm.calls,
      "okCalls": rm.okCalls,
      "errCalls": rm.errCalls,
      "avgLatencyMs": rm.avgLatencyMs,
    })
  var recentRouteMetrics = newJArray()
  for rm in st.recentRouteMetrics:
    recentRouteMetrics.add(%*{
      "route": rm.route,
      "calls": rm.calls,
      "okCalls": rm.okCalls,
      "errCalls": rm.errCalls,
      "avgLatencyMs": rm.avgLatencyMs,
    })
  %*{
    "uptimeSec":     st.uptimeSec,
    "sessionCount":  st.sessionCount,
    "sessions":      sessions,
    "channels":      channels,
    "providers":     providers,
    "routeCounts":   routeCounts,
    "routeMetrics":  routeMetrics,
    "recentRouteMetrics": recentRouteMetrics,
    "toolsCount":    st.toolsCount,
    "memoryBackend": st.memoryBackend,
  }

func fromJsonStatus*(j: JsonNode): DaemonStatus =
  result.uptimeSec     = j{"uptimeSec"}.getBiggestInt(0)
  result.sessionCount  = j{"sessionCount"}.getInt(0)
  result.toolsCount    = j{"toolsCount"}.getInt(0)
  result.memoryBackend = j{"memoryBackend"}.getStr("md")
  for c in j{"channels"}:
    result.channels.add(c.getStr())
  for p in j{"providers"}:
    result.providers.add(p.getStr())
  for rc in j{"routeCounts"}:
    result.routeCounts.add(RouteCount(
      route: rc{"route"}.getStr(),
      count: rc{"count"}.getInt(0),
    ))
  for rm in j{"routeMetrics"}:
    result.routeMetrics.add(RouteMetric(
      route: rm{"route"}.getStr(),
      calls: rm{"calls"}.getInt(0),
      okCalls: rm{"okCalls"}.getInt(0),
      errCalls: rm{"errCalls"}.getInt(0),
      avgLatencyMs: rm{"avgLatencyMs"}.getInt(0),
    ))
  for rm in j{"recentRouteMetrics"}:
    result.recentRouteMetrics.add(RouteMetric(
      route: rm{"route"}.getStr(),
      calls: rm{"calls"}.getInt(0),
      okCalls: rm{"okCalls"}.getInt(0),
      errCalls: rm{"errCalls"}.getInt(0),
      avgLatencyMs: rm{"avgLatencyMs"}.getInt(0),
    ))
  for s in j{"sessions"}:
    var si = SessionInfo(userId: s{"userId"}.getStr())
    for ch in s{"channels"}:
      si.channels.add(ch.getStr())
    result.sessions.add(si)

func toJson*(e: IpcLogEntry): JsonNode =
  %*{"ts": e.ts, "level": e.level, "subsys": e.subsys, "msg": e.msg}

func fromJsonLogEntry*(j: JsonNode): IpcLogEntry =
  IpcLogEntry(
    ts:     j{"ts"}.getStr(),
    level:  j{"level"}.getStr(),
    subsys: j{"subsys"}.getStr(),
    msg:    j{"msg"}.getStr(),
  )
