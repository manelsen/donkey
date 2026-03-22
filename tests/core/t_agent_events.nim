## Agent event ring unit tests.

import std/[json, unittest]
import donkey/core/agent_events

suite "agent event ring":

  test "ring starts empty":
    agentEventRingInit()
    check agentEventSnapshot(10).len == 0

  test "pushAgentEvent stores an event":
    agentEventRingInit()
    pushAgentEvent(AgentEvent(kind: aekToolCall, userId: "u1",
                              toolName: "bash", summary: "ls -la"))
    check agentEventSnapshot(10).len == 1

  test "snapshot returns events in insertion order":
    agentEventRingInit()
    pushAgentEvent(AgentEvent(kind: aekToolCall, userId: "u1",
                              toolName: "bash", summary: "first"))
    pushAgentEvent(AgentEvent(kind: aekModelResponse, userId: "u1",
                              summary: "second"))
    let snap = agentEventSnapshot(10)
    check snap.len == 2
    check snap[0].summary == "first"
    check snap[1].summary == "second"

  test "snapshot honours limit":
    agentEventRingInit()
    for i in 0 ..< 5:
      pushAgentEvent(AgentEvent(kind: aekToolCall, summary: $i))
    check agentEventSnapshot(3).len == 3

  test "toJson produces expected fields":
    agentEventRingInit()
    pushAgentEvent(AgentEvent(kind: aekSessionStart, userId: "u2",
                              summary: "new session"))
    let snap = agentEventSnapshot(1)
    let j = snap[0].toJson()
    check j{"kind"}.getStr() == "session_start"
    check j{"userId"}.getStr() == "u2"
    check j{"summary"}.getStr() == "new session"
    check j{"ts"}.getStr().len > 0

  test "aekError kind serialises correctly":
    agentEventRingInit()
    pushAgentEvent(AgentEvent(kind: aekError, summary: "provider timeout"))
    let j = agentEventSnapshot(1)[0].toJson()
    check j{"kind"}.getStr() == "error"
