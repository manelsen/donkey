## IPC contract types shared between daemon server and ctl client.
##
## Protocol: newline-terminated JSON, one request/response per connection.
## Commands:
##   {"cmd":"status"}       -> DaemonStatus
##   {"cmd":"logs","n":50}  -> last N IpcLogEntry records

import std/[json, strutils]

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

  ProviderMetric* = object
    providerName*: string
    calls*: int
    okCalls*: int
    errCalls*: int
    avgLatencyMs*: int

  MemoryStats* = object
    totalNodes*: int
    memoryNodes*: int
    profileNodes*: int
    preferenceNodes*: int
    entityNodes*: int
    embeddingNodes*: int
    totalEdges*: int

  DaemonStatus* = object
    uptimeSec*:     int64
    sessionCount*:  int
    sessions*:      seq[SessionInfo]
    channels*:      seq[string]
    providers*:     seq[string]
    routeCounts*:   seq[RouteCount]
    routeMetrics*:  seq[RouteMetric]
    recentRouteMetrics*: seq[RouteMetric]
    recentProviderMetrics*: seq[ProviderMetric]
    providerCooldowns*: seq[string]
    toolsCount*:    int
    memoryBackend*: string
    memoryStats*:   MemoryStats

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
  var recentProviderMetrics = newJArray()
  for pm in st.recentProviderMetrics:
    recentProviderMetrics.add(%*{
      "providerName": pm.providerName,
      "calls": pm.calls,
      "okCalls": pm.okCalls,
      "errCalls": pm.errCalls,
      "avgLatencyMs": pm.avgLatencyMs,
    })
  var providerCooldowns = newJArray()
  for item in st.providerCooldowns:
    providerCooldowns.add(%item)
  %*{
    "uptimeSec":     st.uptimeSec,
    "sessionCount":  st.sessionCount,
    "sessions":      sessions,
    "channels":      channels,
    "providers":     providers,
    "routeCounts":   routeCounts,
    "routeMetrics":  routeMetrics,
    "recentRouteMetrics": recentRouteMetrics,
    "recentProviderMetrics": recentProviderMetrics,
    "providerCooldowns": providerCooldowns,
    "toolsCount":    st.toolsCount,
    "memoryBackend": st.memoryBackend,
    "memoryStats": %*{
      "totalNodes": st.memoryStats.totalNodes,
      "memoryNodes": st.memoryStats.memoryNodes,
      "profileNodes": st.memoryStats.profileNodes,
      "preferenceNodes": st.memoryStats.preferenceNodes,
      "entityNodes": st.memoryStats.entityNodes,
      "embeddingNodes": st.memoryStats.embeddingNodes,
      "totalEdges": st.memoryStats.totalEdges,
    },
  }

func fromJsonStatus*(j: JsonNode): DaemonStatus =
  result.uptimeSec     = j{"uptimeSec"}.getBiggestInt(0)
  result.sessionCount  = j{"sessionCount"}.getInt(0)
  result.toolsCount    = j{"toolsCount"}.getInt(0)
  result.memoryBackend = j{"memoryBackend"}.getStr("md")
  result.memoryStats = MemoryStats(
    totalNodes: j{"memoryStats"}{"totalNodes"}.getInt(0),
    memoryNodes: j{"memoryStats"}{"memoryNodes"}.getInt(0),
    profileNodes: j{"memoryStats"}{"profileNodes"}.getInt(0),
    preferenceNodes: j{"memoryStats"}{"preferenceNodes"}.getInt(0),
    entityNodes: j{"memoryStats"}{"entityNodes"}.getInt(0),
    embeddingNodes: j{"memoryStats"}{"embeddingNodes"}.getInt(0),
    totalEdges: j{"memoryStats"}{"totalEdges"}.getInt(0),
  )
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
  for pm in j{"recentProviderMetrics"}:
    result.recentProviderMetrics.add(ProviderMetric(
      providerName: pm{"providerName"}.getStr(),
      calls: pm{"calls"}.getInt(0),
      okCalls: pm{"okCalls"}.getInt(0),
      errCalls: pm{"errCalls"}.getInt(0),
      avgLatencyMs: pm{"avgLatencyMs"}.getInt(0),
    ))
  for item in j{"providerCooldowns"}:
    result.providerCooldowns.add(item.getStr())
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

func hasGraphMemoryStats*(st: DaemonStatus): bool =
  st.memoryBackend.contains("magma") or
  st.memoryStats.totalNodes > 0 or
  st.memoryStats.embeddingNodes > 0 or
  st.memoryStats.totalEdges > 0

func formatDaemonStatus*(st: DaemonStatus): string =
  var lines = @[
    "Donkey status",
    "  Uptime:   " & $st.uptimeSec & "s",
    "  Sessions: " & $st.sessionCount,
    "  Channels: " & st.channels.join(", "),
    "  Providers:" & st.providers.join(", "),
    "  Tools:    " & $st.toolsCount,
    "  Memory:   " & st.memoryBackend,
  ]
  if st.hasGraphMemoryStats:
    lines.add(
      "  Graph:    nodes=" & $st.memoryStats.totalNodes &
      " memory=" & $st.memoryStats.memoryNodes &
      " profiles=" & $st.memoryStats.profileNodes &
      " prefs=" & $st.memoryStats.preferenceNodes &
      " entities=" & $st.memoryStats.entityNodes &
      " embeddings=" & $st.memoryStats.embeddingNodes &
      " edges=" & $st.memoryStats.totalEdges
    )
  if st.sessions.len > 0:
    lines.add("  Active sessions:")
    for s in st.sessions:
      lines.add("    " & s.userId & " [" & s.channels.join(", ") & "]")
  lines.join("\n")
