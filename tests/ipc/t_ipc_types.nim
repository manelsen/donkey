import unittest
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
      toolsCount:    5,
      memoryBackend: "md",
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
    check st2.toolsCount   == 5
    check st2.memoryBackend == "md"

  test "empty DaemonStatus serializes without error":
    let st  = DaemonStatus()
    let st2 = fromJsonStatus(st.toJson())
    check st2.uptimeSec    == 0
    check st2.sessionCount == 0
    check st2.sessions.len == 0

  test "IpcLogEntry round-trips through JSON":
    let e  = IpcLogEntry(ts: "2026-01-01T12:00:00", level: "INF",
                         subsys: "daemon", msg: "started ok")
    let e2 = fromJsonLogEntry(e.toJson())
    check e2.ts     == e.ts
    check e2.level  == e.level
    check e2.subsys == e.subsys
    check e2.msg    == e.msg
