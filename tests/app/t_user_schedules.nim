## `manage_schedules`: a user's own recurring jobs, against a fake store.

import std/[strutils, unittest]
import chronos
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/user_schedules
import donkey/core/pipeops
import donkey/core/tooling/native_tool_args
import donkey/core/types
import donkey/domain/message
import donkey/domain/subagent_pure
import donkey/domain/automation/user_schedule_pure
import donkey/ports/schedules

const Now = 1_700_000_040_000'i64   ## 2023-11-14T22:14:00Z

type FakeStore = ref object
  rows: seq[ScheduleViewRecord]

proc fakePort(store: FakeStore): SchedulePort =
  SchedulePort(
    all: proc(): Result[seq[ScheduleViewRecord], string] {.gcsafe, raises: [].} =
      ok(store.rows),
    insert: proc(spec: ScheduleSpec): Result[bool, string] {.gcsafe, raises: [].} =
      for r in store.rows:
        if r.spec.id == spec.id: return ok(false)
      store.rows.add(ScheduleViewRecord(spec: spec, lastRunAtMs: spec.createdAtMs))
      ok(true),
    remove: proc(id: string): Result[void, string] {.gcsafe, raises: [].} =
      var kept: seq[ScheduleViewRecord]
      for r in store.rows:
        if r.spec.id != id: kept.add(r)
      store.rows = kept
      ok(),
    setEnabled: proc(id: string; enabled: bool; nowMs: int64
                    ): Result[bool, string] {.gcsafe, raises: [].} =
      for r in store.rows.mitems:
        if r.spec.id == id:
          r.spec.enabled = enabled
          return ok(true)
      ok(false))

proc create(port: SchedulePort; user, name, schedule: string;
            tz = ""; catchUp = ""): Result[string, string] =
  performManageSchedules(port, user, "telegram", ManageSchedulesContext(
    action: "create", name: name, schedule: schedule,
    prompt: "send the news", timezone: tz, catchUp: catchUp), Now)

proc act(port: SchedulePort; user, action, name = ""): Result[string, string] =
  performManageSchedules(port, user, "telegram",
    ManageSchedulesContext(action: action, name: name), Now)

proc runTests*() =
  suite "manage_schedules":

    test "create stores the user's job in this channel and says when it runs":
      let store = FakeStore()
      let port = fakePort(store)
      let r = create(port, "alice", "news", "0 9 * * 1-5", tz = "UTC-03:00")
      check r.isOk
      check "First run 2023-11-15T12:00:00Z" in r.get
      check store.rows.len == 1
      let spec = store.rows[0].spec
      check spec.id == "alice:news"
      check spec.userId == "alice"
      check spec.channel == "telegram"
      check spec.tzOffsetMinutes == -180
      check spec.payload == "send the news"
      check spec.catchUp == scSkip
      check spec.createdAtMs == Now

    test "the defaults are UTC and skip; once is accepted; nonsense is not":
      let store = FakeStore()
      let port = fakePort(store)
      check create(port, "alice", "a", "@daily").isOk
      check store.rows[0].spec.tzOffsetMinutes == 0
      check create(port, "alice", "b", "@daily", catchUp = "once").isOk
      check store.rows[1].spec.catchUp == scOnce
      check create(port, "alice", "c", "@daily", catchUp = "always").isErr
      check create(port, "alice", "d", "@daily", tz = "America/Sao_Paulo").isErr

    test "a name taken, a bad name, too frequent and the cap are refused":
      let store = FakeStore()
      let port = fakePort(store)
      check create(port, "alice", "news", "@daily").isOk
      check "already exists" in create(port, "alice", "news", "@hourly").error
      check create(port, "alice", "Bad Name", "@daily").isErr
      check "5 minutes" in create(port, "alice", "spam", "* * * * *").error
      for i in 1 ..< MaxUserSchedules:
        check create(port, "alice", "job" & $i, "@daily").isOk
      check "delete one first" in create(port, "alice", "one-more", "@daily").error
      ## The cap is per user.
      check create(port, "bob", "news", "@daily").isOk

    test "a user lists, pauses, resumes and deletes only their own jobs":
      let store = FakeStore()
      let port = fakePort(store)
      check create(port, "alice", "news", "@daily").isOk
      check create(port, "bob", "news", "@hourly").isOk
      let listed = act(port, "alice", "list").get
      check "- news: @daily" in listed
      check "@hourly" notin listed
      check act(port, "alice", "pause", "news").isOk
      check not store.rows[0].spec.enabled
      check store.rows[1].spec.enabled
      check "paused" in act(port, "alice", "list").get
      check act(port, "alice", "resume", "news").isOk
      check store.rows[0].spec.enabled
      check act(port, "alice", "delete", "news").isOk
      check store.rows.len == 1 and store.rows[0].spec.userId == "bob"
      check "no schedule named" in act(port, "alice", "delete", "news").error

    test "a job made by the operator for the user is not theirs to touch by name":
      let store = FakeStore()
      store.rows.add(ScheduleViewRecord(spec: ScheduleSpec(
        id: "ops-backup", cronExpr: "@daily", userId: "alice",
        channel: "telegram", payload: "x", enabled: true)))
      let port = fakePort(store)
      check "ops-backup" in act(port, "alice", "list").get
      check act(port, "alice", "delete", "ops-backup").isErr
      check store.rows.len == 1

    test "without a scheduler the tool says so":
      let r = act(SchedulePort(), "alice", "list")
      check r.isErr
      check r.error == SchedulesUnavailable

    test "api: users cannot schedule (their replies have no turn to go to)":
      let port = fakePort(FakeStore())
      check "api:" in create(port, "api:svc", "news", "@daily").error

    test "the tool is dispatched for real and denied to subagents":
      let store = FakeStore()
      let ctx = NativeCtx(uid: UserId("alice"), channel: ckTelegram,
                          schedules: fakePort(store))
      let made = waitFor executeNativeTool(ToolCallRequest(id: "1",
        name: "manage_schedules", inputJson: """{"action":"create","name":"news",""" &
        """"schedule":"@every 2h","prompt":"send the news"}"""),
        ctx, newSessionState(), @[])
      check made.handled
      check "Scheduled 'news'" in made.text
      check store.rows.len == 1 and store.rows[0].spec.channel == "telegram"
      let listed = waitFor executeNativeTool(ToolCallRequest(id: "2",
        name: "manage_schedules", inputJson: """{"action":"list"}"""),
        ctx, newSessionState(), @[])
      check "news: @every 2h" in listed.text
      check "manage_schedules" in SubagentHardDeniedTools

when isMainModule:
  runTests()
