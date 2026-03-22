## agent_events — global ring buffer for structured agent/session events.
##
## Provides a pub-compatible source for the HTTP SSE gateway's /api/events
## endpoint. Works like the log ring but carries structured agent-level events
## (session start/end, tool calls, model responses, errors).
##
## Thread-safe via a Lock. agentEventRingInit() must be called once in the
## daemon before any pushAgentEvent() calls (same pattern as log ringInit()).

import std/[json, locks, times]

const AgentEventRingCap* = 200

type
  AgentEventKind* = enum
    aekSessionStart   = "session_start"
    aekSessionEnd     = "session_end"
    aekToolCall       = "tool_call"
    aekToolResult     = "tool_result"
    aekModelResponse  = "model_response"
    aekError          = "error"

  AgentEvent* = object
    kind*:     AgentEventKind
    userId*:   string
    channel*:  string
    toolName*: string   ## populated for aekToolCall / aekToolResult
    summary*:  string   ## human-readable one-liner
    ts*:       string   ## ISO-8601 timestamp (set by pushAgentEvent)

# ── ring buffer ───────────────────────────────────────────────────────────────

var gAgentRing:   array[AgentEventRingCap, AgentEvent]
var gAgentHead:   int
var gAgentCount:  int
var gAgentLock:   Lock
var gAgentReady:  bool

proc agentEventRingInit*() =
  initLock(gAgentLock)
  gAgentHead  = 0
  gAgentCount = 0
  gAgentReady = true

proc pushAgentEvent*(ev: AgentEvent) =
  {.gcsafe.}:
    if not gAgentReady: return
    var e = ev
    if e.ts.len == 0:
      e.ts = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    withLock gAgentLock:
      gAgentRing[gAgentHead mod AgentEventRingCap] = e
      inc gAgentHead
      if gAgentCount < AgentEventRingCap: inc gAgentCount

proc agentEventSnapshot*(n: int): seq[AgentEvent] {.gcsafe.} =
  ## Returns up to `n` most recent events in insertion order.
  {.cast(gcsafe).}:
    if not gAgentReady: return @[]
    withLock gAgentLock:
      let take = min(n, gAgentCount)
      let start = (gAgentHead - take + AgentEventRingCap * 2) mod AgentEventRingCap
      result = newSeq[AgentEvent](take)
      for i in 0 ..< take:
        result[i] = gAgentRing[(start + i) mod AgentEventRingCap]

# ── serialisation ─────────────────────────────────────────────────────────────

func kindLabel*(k: AgentEventKind): string =
  case k
  of aekSessionStart:   "session_start"
  of aekSessionEnd:     "session_end"
  of aekToolCall:       "tool_call"
  of aekToolResult:     "tool_result"
  of aekModelResponse:  "model_response"
  of aekError:          "error"

func toJson*(ev: AgentEvent): JsonNode =
  result = %* {
    "kind":    kindLabel(ev.kind),
    "userId":  ev.userId,
    "channel": ev.channel,
    "summary": ev.summary,
    "ts":      ev.ts,
  }
  if ev.toolName.len > 0:
    result["toolName"] = %ev.toolName
