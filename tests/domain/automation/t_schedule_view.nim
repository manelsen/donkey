## Pure schedule view tests — US-007 visibility slice.
##
## `schedule_view` renders persisted schedule rows for `donkey ctl schedule
## list` / `show` and (later) the TUI panel. It owns no clock: every test
## passes an explicit `nowMs`, so `next_run` is deterministic.
##
## `last_run` is the **firing** instant (`lastFireAtMs`), never the scheduler
## watermark (`lastRunAtMs`). The watermark advances on every tick, so showing
## it would claim a run that never happened.
##
## `last_status`/`last_error`/`failures` are part of the view projection even
## though the current store slice does not persist them: the ctl passes them
## when present, and the panel must not invent a value.

import std/[json, options, strutils, unittest]
import donkey/domain/automation/schedule_pure
import donkey/domain/automation/schedule_view

const
  FixedNow = 1_700_000_040_000'i64
    ## 2023-11-14T22:14:00Z: two minutes past the fixed epoch used below.

func makeSpec(
  cron = "0 9 * * *";
  tz = 0;
  catchUp = scSkip;
  enabled = true;
  id = "daily";
  userId = "alice";
  channel = "telegram";
  payload = "run the report";
  createdAt = 1_700_000_000_000'i64;
): ScheduleSpec =
  ScheduleSpec(
    id: id,
    cronExpr: cron,
    tzOffsetMinutes: tz,
    userId: userId,
    channel: channel,
    payload: payload,
    catchUp: catchUp,
    enabled: enabled,
    createdAtMs: createdAt,
  )

func makeRow(
  lastRunAtMs = FixedNow;
  lastFireAtMs = 0'i64;
  lastStatus = "";
  lastError = "";
  failures = 0;
  spec = makeSpec();
  missed = 0;
  lastMissedAtMs = 0'i64;
): ScheduleViewRecord =
  ScheduleViewRecord(
    spec: spec,
    lastRunAtMs: lastRunAtMs,
    lastFireAtMs: lastFireAtMs,
    lastStatus: lastStatus,
    lastError: lastError,
    failures: failures,
    missed: missed,
    lastMissedAtMs: lastMissedAtMs,
  )

proc runTests*() =
  suite "schedule view — formatScheduleRow":

    test "last_run is never when lastFireAtMs is zero":
      let row = formatScheduleRow(makeRow(lastFireAtMs = 0), FixedNow)
      check "last_run=never" in row

    test "last_run reflects lastFireAtMs and ignores the watermark":
      # The watermark is ahead of the last firing: the row must still print the
      # firing instant, not `FixedNow`.
      let row = formatScheduleRow(
        makeRow(lastRunAtMs = FixedNow, lastFireAtMs = FixedNow - 3_600_000'i64),
        FixedNow,
      )
      check "last_run=2023-11-14T21:14:00Z" in row
      check "last_run=2023-11-14T22:14:00Z" notin row

    test "next_run is derived from the cron expression":
      let row = formatScheduleRow(makeRow(), FixedNow)
      # 22:14Z, `0 9 * * *` → next occurrence is 09:00Z the next day.
      check "next_run=2023-11-15T09:00:00Z" in row

    test "next_run honours the fixed tz offset":
      let row = formatScheduleRow(makeRow(spec = makeSpec(tz = -180)), FixedNow)
      # 19:14 local (UTC-03:00) → 09:00 local next day = 12:00Z.
      check "next_run=2023-11-15T12:00:00Z" in row

    test "next_run is none when the cron never matches":
      let row = formatScheduleRow(
        makeRow(spec = makeSpec(cron = "0 0 30 2 *")), FixedNow)
      check "next_run=none" in row

    test "shows enabled and catch_up":
      let row = formatScheduleRow(
        makeRow(spec = makeSpec(catchUp = scOnce, enabled = false)), FixedNow)
      check "enabled=false" in row
      check "catch_up=once" in row

    test "shows last_status and last_error when present":
      let row = formatScheduleRow(
        makeRow(lastStatus = "failed", lastError = "inbox full"), FixedNow)
      check "last_status=failed" in row
      check "last_error=inbox full" in row

    test "omits last_error when absent and prints last_status=none":
      let row = formatScheduleRow(makeRow(), FixedNow)
      check "last_status=none" in row
      check "last_error" notin row

    test "shows the failure count":
      let row = formatScheduleRow(makeRow(failures = 2), FixedNow)
      check "failures=2" in row
      check "retention" notin row

    test "shows missed occurrences and when the last was noticed":
      let row = formatScheduleRow(makeRow(missed = 3,
        lastMissedAtMs = FixedNow - 3_600_000'i64), FixedNow)
      check "missed=3" in row
      check "last_missed=2023-11-14T21:14:00Z" in row
      check "missed" notin formatScheduleRow(makeRow(), FixedNow)
      let detail = scheduleDetailLines(makeRow(missed = 3,
        lastMissedAtMs = FixedNow), FixedNow)
      check "missed: 3" in detail
      check "last_missed: 2023-11-14T22:14:00Z" in detail
      let node = parseJson(formatScheduleJson(@[makeRow(missed = 3,
        lastMissedAtMs = FixedNow)], FixedNow))[0]
      check node["missed"].getInt == 3
      check node["last_missed_at_ms"].getInt == FixedNow
      let item = scheduleListItem(makeRow(missed = 2, lastMissedAtMs = FixedNow), FixedNow)
      check "missed 2" in item.status

    test "never prints the payload":
      let row = formatScheduleRow(makeRow(), FixedNow)
      check "payload" notin row
      check "run the report" notin row

    test "shows the timezone offset":
      let row = formatScheduleRow(makeRow(spec = makeSpec(tz = -180)), FixedNow)
      check "tz=UTC-03:00" in row

  suite "schedule view — schedulePanelLines":

    test "empty store prints one clear line":
      check schedulePanelLines(@[], FixedNow) == @["No schedules."]

    test "one self-describing line per record, no header":
      let lines = schedulePanelLines(@[
        makeRow(spec = makeSpec(id = "daily")),
        makeRow(spec = makeSpec(id = "hourly", cron = "0 * * * *")),
      ], FixedNow)
      check lines.len == 2
      check "id=daily" in lines[0]
      check "next_run=" in lines[0]
      check "id=hourly" in lines[1]

  suite "schedule view — JSON":

    test "empty list is an empty JSON array":
      check formatScheduleJson(@[], FixedNow) == "[]"

    test "list JSON parses and exposes the documented keys":
      let parsed = parseJson(formatScheduleJson(@[makeRow()], FixedNow))
      check parsed.kind == JArray
      check parsed.len == 1
      let node = parsed[0]
      for key in [
        "id", "cron", "tz", "user", "channel", "enabled", "catch_up",
        "last_run", "next_run", "last_status", "last_error", "failures",
        "created_at_ms", "last_run_at_ms", "last_fire_at_ms",
      ]:
        check node.hasKey(key)
      check not node.hasKey("payload")
      check node["id"].getStr == "daily"
      check node["last_run"].getStr == "never"
      check node["next_run"].getStr == "2023-11-15T09:00:00Z"
      check node["last_status"].getStr == "none"
      check node["last_run_at_ms"].getInt == FixedNow

    test "detail JSON includes the payload":
      let parsed = parseJson(
        formatScheduleJson(@[makeRow()], FixedNow, includePayload = true))
      check parsed[0]["payload"].getStr == "run the report"

    test "JSON last_run mirrors the human value":
      let row = makeRow(lastFireAtMs = FixedNow - 3_600_000'i64,
                        lastStatus = "sent")
      let node = parseJson(formatScheduleJson(@[row], FixedNow))[0]
      check node["last_run"].getStr == "2023-11-14T21:14:00Z"
      check node["last_status"].getStr == "sent"

when isMainModule:
  runTests()
