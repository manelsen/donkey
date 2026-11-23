## The user's own schedules, the pure part: names, ids, the per-user cap and
## the minimum spacing a chat-created schedule may fire at.

import std/[strutils, unittest]
import results
import donkey/domain/automation/schedule_pure
import donkey/domain/automation/schedule_view
import donkey/domain/automation/user_schedule_pure

const
  MinuteMs = 60_000'i64
  HourMs = 60 * MinuteMs
  Now = 1_700_000_040_000'i64   ## 2023-11-14T22:14:00Z

func spec(expr: string; user = "alice"; name = "daily"): ScheduleSpec =
  ScheduleSpec(id: userScheduleId(user, name), cronExpr: expr,
               userId: user, channel: "telegram", payload: "do it",
               catchUp: scSkip, enabled: true, createdAtMs: Now)

func row(s: ScheduleSpec; fired = 0'i64; status = ""; missed = 0): ScheduleViewRecord =
  ScheduleViewRecord(spec: s, lastRunAtMs: s.createdAtMs, lastFireAtMs: fired,
                     lastStatus: status, missed: missed, lastMissedAtMs: Now)

proc runTests*() =
  suite "user schedules — names and ids":

    test "a name is 1-32 of a-z, 0-9 and '-'":
      check validScheduleName("daily-report")
      check validScheduleName("a")
      check not validScheduleName("")
      check not validScheduleName("Daily")
      check not validScheduleName("a b")
      check not validScheduleName("a:b")
      check not validScheduleName(repeat('a', 33))

    test "the id joins the owner and the name; the name comes back out":
      let id = userScheduleId("alice", "daily")
      check id == "alice:daily"
      check scheduleNameOf(id) == "daily"
      check ownsSchedule(spec("@daily"), "alice")
      check not ownsSchedule(spec("@daily"), "bob")

    test "a schedule made by the operator with another id still lists by its id":
      check scheduleNameOf("ops-backup") == "ops-backup"

  suite "user schedules — spacing":

    test "an interval fires as often as its period":
      check firesMoreOftenThan(spec("@every 4m"), Now, 5 * MinuteMs)
      check not firesMoreOftenThan(spec("@every 5m"), Now, 5 * MinuteMs)

    test "a cron fires as often as its closest two occurrences":
      check firesMoreOftenThan(spec("* * * * *"), Now, 5 * MinuteMs)
      check firesMoreOftenThan(spec("*/2 9 * * *"), Now, 5 * MinuteMs)
      check firesMoreOftenThan(spec("0,1 9 * * *"), Now, 5 * MinuteMs)
      check not firesMoreOftenThan(spec("*/5 * * * *"), Now, 5 * MinuteMs)
      check not firesMoreOftenThan(spec("0 9 * * 1-5"), Now, 5 * MinuteMs)
      check not firesMoreOftenThan(spec("@yearly"), Now, 5 * MinuteMs)

    test "a dense day far from now is still found":
      ## Every minute, but only on the 31st: the next one is weeks away.
      check firesMoreOftenThan(spec("* * 31 * *"), Now, 5 * MinuteMs)

  suite "user schedules — what a new one must pass":

    test "a valid schedule under the cap passes":
      check checkNewUserSchedule(spec("0 9 * * *"), 0, Now).isOk

    test "the cap is per user":
      let r = checkNewUserSchedule(spec("0 9 * * *"), MaxUserSchedules, Now)
      check r.isErr
      check $MaxUserSchedules in r.error

    test "too frequent is refused with the limit in the message":
      let r = checkNewUserSchedule(spec("* * * * *"), 0, Now)
      check r.isErr
      check "5 minutes" in r.error

    test "the general validation still runs":
      check checkNewUserSchedule(spec("not a cron"), 0, Now).isErr
      var empty = spec("@daily")
      empty.payload = ""
      check checkNewUserSchedule(empty, 0, Now).isErr

  suite "user schedules — the list the model reads":

    test "one line per schedule with expression, next run and state":
      var paused = spec("@every 2h", name = "pulse")
      paused.enabled = false
      let text = formatUserSchedules(@[
        row(spec("0 9 * * *", name = "daily"), fired = Now - HourMs, status = "sent"),
        row(paused)], Now)
      check "daily: 0 9 * * * (UTC+00:00)" in text
      check "next 2023-11-15T09:00:00Z" in text
      check "last 2023-11-14T21:14:00Z sent" in text
      check "pulse: @every 2h" in text
      check "paused" in text
      check "do it" in text

    test "an interval does not show a timezone it ignores":
      let text = formatUserSchedules(@[row(spec("@every 2h", name = "pulse"))], Now)
      check "- pulse: @every 2h, next " in text

    test "missed runs are reported so the agent can tell the user":
      let text = formatUserSchedules(@[row(spec("@hourly"), missed = 5)], Now)
      check "missed 5 (last noticed 2023-11-14T22:14:00Z)" in text
      check "missed" notin formatUserSchedules(@[row(spec("@hourly"))], Now)

    test "no schedules says how to make one":
      check "action=create" in formatUserSchedules(@[], Now)

when isMainModule:
  runTests()
