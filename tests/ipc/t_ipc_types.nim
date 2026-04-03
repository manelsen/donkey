import std/[strutils, unittest]
import donkey/adapters/ipc/types

suite "IPC types serialization":

  test "DaemonStatus round-trips through JSON":
    let st = DaemonStatus(
      uptimeSec:     3661,
      sessionCount:  2,
      sessions: @[
        SessionInfo(userId: "abc-123", channels: @["telegram", "discord"]),
        SessionInfo(userId: "xyz-456", channels: @["telegram"]),
      ],
      channels:      @["telegram", "discord"],
      providers:     @["openrouter"],
      routeCounts:   @[RouteCount(route: "anthropic/claude-opus-4-6", count: 7)],
      routeMetrics:  @[RouteMetric(route: "anthropic/claude-opus-4-6", calls: 7, okCalls: 6, errCalls: 1, avgLatencyMs: 840)],
      recentRouteMetrics: @[RouteMetric(route: "openrouter/openai/gpt-4o-mini", calls: 4, okCalls: 4, errCalls: 0, avgLatencyMs: 620)],
      recentProviderMetrics: @[ProviderMetric(providerName: "openrouter", calls: 4, okCalls: 4, errCalls: 0, avgLatencyMs: 620)],
      providerCooldowns: @["anthropic (5m)"],
      toolsCount:    5,
      memoryBackend: "md",
      memoryStats: MemoryStats(
        totalNodes: 12,
        memoryNodes: 8,
        profileNodes: 2,
        preferenceNodes: 1,
        entityNodes: 1,
        embeddingNodes: 11,
        totalEdges: 9,
      ),
    )
    let j   = st.toJson()
    let st2 = fromJsonStatus(j)
    check st2.uptimeSec         == 3661
    check st2.sessionCount      == 2
    check st2.sessions.len      == 2
    check st2.sessions[0].userId   == "abc-123"
    check st2.sessions[0].channels == @["telegram", "discord"]
    check st2.sessions[1].channels == @["telegram"]
    check st2.channels     == @["telegram", "discord"]
    check st2.providers    == @["openrouter"]
    check st2.routeCounts.len == 1
    check st2.routeCounts[0].route == "anthropic/claude-opus-4-6"
    check st2.routeCounts[0].count == 7
    check st2.routeMetrics.len == 1
    check st2.routeMetrics[0].route == "anthropic/claude-opus-4-6"
    check st2.routeMetrics[0].calls == 7
    check st2.routeMetrics[0].okCalls == 6
    check st2.routeMetrics[0].errCalls == 1
    check st2.routeMetrics[0].avgLatencyMs == 840
    check st2.recentRouteMetrics.len == 1
    check st2.recentRouteMetrics[0].route == "openrouter/openai/gpt-4o-mini"
    check st2.recentRouteMetrics[0].calls == 4
    check st2.recentRouteMetrics[0].okCalls == 4
    check st2.recentRouteMetrics[0].errCalls == 0
    check st2.recentRouteMetrics[0].avgLatencyMs == 620
    check st2.recentProviderMetrics.len == 1
    check st2.recentProviderMetrics[0].providerName == "openrouter"
    check st2.recentProviderMetrics[0].calls == 4
    check st2.recentProviderMetrics[0].okCalls == 4
    check st2.recentProviderMetrics[0].errCalls == 0
    check st2.recentProviderMetrics[0].avgLatencyMs == 620
    check st2.providerCooldowns == @["anthropic (5m)"]
    check st2.toolsCount   == 5
    check st2.memoryBackend == "md"
    check st2.memoryStats.totalNodes == 12
    check st2.memoryStats.memoryNodes == 8
    check st2.memoryStats.profileNodes == 2
    check st2.memoryStats.preferenceNodes == 1
    check st2.memoryStats.entityNodes == 1
    check st2.memoryStats.embeddingNodes == 11
    check st2.memoryStats.totalEdges == 9

  test "empty DaemonStatus serializes without error":
    let st  = DaemonStatus()
    let st2 = fromJsonStatus(st.toJson())
    check st2.uptimeSec    == 0
    check st2.sessionCount == 0
    check st2.sessions.len == 0

  test "formatDaemonStatus includes graph-backed counts":
    let rendered = formatDaemonStatus(DaemonStatus(
      uptimeSec: 42,
      sessionCount: 1,
      channels: @["telegram"],
      providers: @["openrouter"],
      toolsCount: 3,
      memoryBackend: "md+magma",
      memoryStats: MemoryStats(
        totalNodes: 12,
        memoryNodes: 8,
        profileNodes: 2,
        preferenceNodes: 1,
        entityNodes: 1,
        embeddingNodes: 11,
        totalEdges: 9,
      ),
    ))
    check rendered.contains("Memory:   md+magma")
    check rendered.contains("nodes=12")
    check rendered.contains("embeddings=11")
    check rendered.contains("edges=9")

  test "IpcLogEntry round-trips through JSON":
    let e  = IpcLogEntry(ts: "2026-01-01T12:00:00", level: "INF",
                         subsys: "daemon", msg: "started ok")
    let e2 = fromJsonLogEntry(e.toJson())
    check e2.ts     == e.ts
    check e2.level  == e.level
    check e2.subsys == e.subsys
    check e2.msg    == e.msg
