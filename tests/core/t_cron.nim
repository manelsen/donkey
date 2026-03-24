import std/[times, strutils]
import unittest2
import ../../src/donkey/core/cron
import ../../src/donkey/core/pipeops

suite "core/cron":

  suite "parseFieldValue":
    test "parses * as -1 (any)":
      check parseFieldValue("*", 0, 59).get() == -1

    test "parses valid number":
      check parseFieldValue("5", 0, 59).get() == 5

    test "rejects number below min":
      check parseFieldValue("-1", 0, 59).isErr

    test "rejects number above max":
      check parseFieldValue("60", 0, 59).isErr

    test "rejects non-numeric":
      check parseFieldValue("abc", 0, 59).isErr

    test "rejects empty string":
      check parseFieldValue("", 0, 59).isErr

    test "strips whitespace":
      check parseFieldValue("  5  ", 0, 59).get() == 5

  suite "parseFieldRange":
    test "single value":
      let r = parseFieldRange("5", 0, 59)
      check r.isOk
      check r.get() == @[5]

    test "range 1-5":
      let r = parseFieldRange("1-5", 0, 59)
      check r.isOk
      check r.get() == @[1, 2, 3, 4, 5]

    test "range with * is invalid":
      check parseFieldRange("*-5", 0, 59).isErr

    test "reversed range is invalid":
      check parseFieldRange("5-1", 0, 59).isErr

    test "range outside bounds":
      check parseFieldRange("1-100", 0, 59).isErr

  suite "parseCronField (minute 0-59)":
    test "wildcard *":
      let r = parseCronField("*", MinMinute, MaxMinute)
      check r.isOk
      check r.get().hasAll == true

    test "single value":
      let r = parseCronField("5", MinMinute, MaxMinute)
      check r.isOk
      check r.get().values == @[5]
      check r.get().hasAll == false

    test "comma-separated list":
      let r = parseCronField("0,30,59", MinMinute, MaxMinute)
      check r.isOk
      check r.get().values == @[0, 30, 59]

    test "range":
      let r = parseCronField("0-5", MinMinute, MaxMinute)
      check r.isOk
      check r.get().values == @[0, 1, 2, 3, 4, 5]

    test "step * /5":
      let r = parseCronField("*/5", MinMinute, MaxMinute)
      check r.isOk
      let f = r.get()
      check f.values == @[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

    test "step with range 1-10/2":
      let r = parseCronField("1-10/2", MinMinute, MaxMinute)
      check r.isOk
      check r.get().values == @[1, 3, 5, 7, 9]

    test "list with range":
      let r = parseCronField("0,5-10,30", MinMinute, MaxMinute)
      check r.isOk
      let values = r.get().values
      check 0 in values
      check 5 in values and 6 in values and 7 in values and 8 in values and 9 in values and 10 in values
      check 30 in values

    test "empty field is error":
      check parseCronField("", MinMinute, MaxMinute).isErr

  suite "parseCronExpr":
    test "every minute":
      let r = parseCronExpr("* * * * *")
      check r.isOk
      let expr = r.get()
      check expr.minute.hasAll == true
      check expr.hour.hasAll == true
      check expr.dayOfMonth.hasAll == true
      check expr.month.hasAll == true
      check expr.dayOfWeek.hasAll == true

    test "every 5 minutes":
      let r = parseCronExpr("*/5 * * * *")
      check r.isOk
      let expr = r.get()
      check expr.minute.hasAll == false
      check expr.minute.values == @[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

    test "daily at midnight":
      let r = parseCronExpr("0 0 * * *")
      check r.isOk
      let expr = r.get()
      check expr.minute.values == @[0]
      check expr.hour.values == @[0]

    test "hourly at minute 30":
      let r = parseCronExpr("30 * * * *")
      check r.isOk
      check r.get().minute.values == @[30]

    test "first of month at noon":
      let r = parseCronExpr("0 12 1 * *")
      check r.isOk
      let expr = r.get()
      check expr.minute.values == @[0]
      check expr.hour.values == @[12]
      check expr.dayOfMonth.values == @[1]

    test "wrong field count returns error":
      check parseCronExpr("* * * *").isErr
      check parseCronExpr("* * * * * *").isErr

  suite "fieldMatches":
    test "matches any when hasAll":
      let f = CronField(values: @[], hasAll: true)
      check fieldMatches(f, 0) == true
      check fieldMatches(f, 59) == true

    test "matches value in list":
      let f = CronField(values: @[0, 15, 30, 45], hasAll: false)
      check fieldMatches(f, 0) == true
      check fieldMatches(f, 15) == true
      check fieldMatches(f, 30) == true
      check fieldMatches(f, 45) == true
      check fieldMatches(f, 5) == false

  suite "matchesCron":
    test "every minute matches any datetime":
      let expr = everyMinute()
      let dt = initDateTime(15, mMar, 23, 10, 30, 0, utc())
      check matchesCron(expr, dt) == true

    test "matches specific minute":
      let expr = parseCronExpr("30 * * * *").get()
      let dtMatch = initDateTime(15, mMar, 23, 10, 30, 0, utc())
      let dtNoMatch = initDateTime(15, mMar, 23, 10, 31, 0, utc())
      check matchesCron(expr, dtMatch) == true
      check matchesCron(expr, dtNoMatch) == false

    test "matches specific hour and minute":
      let expr = parseCronExpr("0 14 * * *").get()
      let dtMatch = initDateTime(15, mMar, 23, 14, 0, 0, utc())
      let dtNoMatch = initDateTime(15, mMar, 23, 14, 1, 0, utc())
      check matchesCron(expr, dtMatch) == true
      check matchesCron(expr, dtNoMatch) == false

    test "day of month":
      let expr = parseCronExpr("0 12 15 * *").get()  # 15th of every month at noon
      let dtMatch = initDateTime(15, mJan, 2024, 12, 0, 0, utc())
      let dtNoMatch = initDateTime(16, mJan, 2024, 12, 0, 0, utc())
      check matchesCron(expr, dtMatch) == true
      check matchesCron(expr, dtNoMatch) == false

  suite "nextRun":
    test "every minute - next minute":
      let expr = everyMinute()
      let now = initDateTime(23, mMar, 2024, 10, 30, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 31
      check next.hour == 10
      check next.monthday == 23

    test "every 5 minutes - rounds up to next 5":
      let expr = parseCronExpr("*/5 * * * *").get()
      let now = initDateTime(23, mMar, 2024, 10, 3, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 5

    test "every 5 minutes at minute 7":
      let expr = parseCronExpr("*/5 * * * *").get()
      let now = initDateTime(23, mMar, 2024, 10, 7, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 10

    test "every 5 minutes - already at 15":
      let expr = parseCronExpr("*/5 * * * *").get()
      let now = initDateTime(23, mMar, 2024, 10, 15, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 20

    test "hourly at minute 30 - past 30":
      let expr = parseCronExpr("30 * * * *").get()
      let now = initDateTime(23, mMar, 2024, 10, 45, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 30
      check next.hour == 11

    test "daily at midnight":
      let expr = parseCronExpr("0 0 * * *").get()
      let now = initDateTime(23, mMar, 2024, 14, 30, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 0
      check next.hour == 0
      check next.monthday == 24

    test "daily at 9:00":
      let expr = parseCronExpr("0 9 * * *").get()
      let now = initDateTime(23, mMar, 2024, 8, 0, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 0
      check next.hour == 9
      check next.monthday == 23

    test "daily at 9:00 - already past":
      let expr = parseCronExpr("0 9 * * *").get()
      let now = initDateTime(23, mMar, 2024, 10, 0, 0, utc())
      let next = nextRun(expr, now)
      check next.minute == 0
      check next.hour == 9
      check next.monthday == 24

  suite "isValidCron":
    test "valid expressions":
      check isValidCron("* * * * *") == true
      check isValidCron("*/5 * * * *") == true
      check isValidCron("0 9 * * 1-5") == true
      check isValidCron("0 0 1 * *") == true

    test "invalid expressions":
      check isValidCron("") == false
      check isValidCron("* * * *") == false
      check isValidCron("60 * * * *") == false
      check isValidCron("* 24 * * *") == false

  suite "cronFieldToStr":
    test "wildcard":
      let f = CronField(values: @[], hasAll: true)
      check cronFieldToStr(f) == "*"

    test "single value":
      let f = CronField(values: @[5], hasAll: false)
      check cronFieldToStr(f) == "5"

    test "multiple values":
      let f = CronField(values: @[0, 15, 30, 45], hasAll: false)
      check cronFieldToStr(f) == "0,15,30,45"

  suite "$ CronExpr":
    test "every minute":
      let expr = everyMinute()
      check $expr == "* * * * *"

    test "every 5 minutes":
      let expr = parseCronExpr("*/5 * * * *").get()
      check $expr == "0,5,10,15,20,25,30,35,40,45,50,55 * * * *"

  suite "everyNMinutes":
    test "every 5 minutes":
      let r = everyNMinutes(5)
      check r.isOk
      check r.get().minute.values == @[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

    test "every 15 minutes":
      let r = everyNMinutes(15)
      check r.isOk
      check r.get().minute.values == @[0, 15, 30, 45]

    test "every 30 minutes":
      let r = everyNMinutes(30)
      check r.isOk
      check r.get().minute.values == @[0, 30]

    test "n too small":
      check everyNMinutes(0).isErr
      check everyNMinutes(-1).isErr

    test "n too large":
      check everyNMinutes(60).isErr

  suite "hourlyAt":
    test "valid minute":
      let r = hourlyAt(30)
      check r.isOk
      check r.get().minute.values == @[30]
      check r.get().hour.hasAll == true

    test "invalid minute":
      check hourlyAt(60).isErr
      check hourlyAt(-1).isErr

  suite "dailyAt":
    test "valid":
      let r = dailyAt(9, 30)
      check r.isOk
      check r.get().hour.values == @[9]
      check r.get().minute.values == @[30]

    test "invalid hour":
      check dailyAt(24, 0).isErr

    test "invalid minute":
      check dailyAt(9, 60).isErr

  suite "ScheduledTask":
    test "newScheduledTask":
      let expr = everyMinute()
      let task = newScheduledTask("task1", expr, "data", true)
      check task.id == "task1"
      check task.enabled == true
      check shouldRun(task, initDateTime(23, mMar, 2024, 10, 30, 0, utc())) == true

    test "disableTask":
      var task = newScheduledTask("task1", everyMinute(), "data", true)
      disableTask(task)
      check task.enabled == false

    test "enableTask":
      var task = newScheduledTask("task1", everyMinute(), "data", false)
      enableTask(task)
      check task.enabled == true

    test "shouldRun - disabled":
      var task = newScheduledTask("task1", everyMinute(), "data", true)
      disableTask(task)
      check shouldRun(task, initDateTime(23, mMar, 2024, 10, 30, 0, utc())) == false

    test "shouldRun - wrong time":
      let expr = parseCronExpr("0 9 * * *").get()
      let task = newScheduledTask("task1", expr, "data", true)
      let dt = initDateTime(23, mMar, 2024, 10, 0, 0, utc())
      check shouldRun(task, dt) == false

  suite "$ ScheduledTask":
    test "string representation":
      let task = newScheduledTask("task1", everyMinute(), "data", true)
      let s = $task
      check "task1" in s
      check "enabled=true" in s
