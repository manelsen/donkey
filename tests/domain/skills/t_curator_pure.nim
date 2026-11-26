## The curator, the pure half (E7.6): when a pass is due, which skills have
## gone stale (never the person's own), which backups to keep, and the
## instructions for consolidating. After hermes-agent (MIT), agent/curator.py.

import std/[strutils, unittest]
import donkey/config/environment
import donkey/domain/skills/curator_pure

const Day = 86_400_000'i64

proc runTests*() =
  suite "curator":

    test "every 7 days, archiving after 90 days unused; the operator can change or stop it":
      let s = curatorSettings(environmentOf({"X": "1"}))
      check s.enabled and s.intervalDays == 7 and s.staleDays == 90
      let t = curatorSettings(environmentOf({"DONKEY_CURATOR_INTERVAL_DAYS": "1",
                                             "DONKEY_CURATOR_STALE_DAYS": "30"}))
      check t.intervalDays == 1 and t.staleDays == 30
      check not curatorSettings(environmentOf({"DONKEY_CURATOR": "off"})).enabled

    test "a pass is due when the last one is older than the interval, or never ran":
      let s = CuratorSettings(enabled: true, intervalDays: 7, staleDays: 90)
      check curatorDue(0, 100 * Day, s)
      check not curatorDue(95 * Day, 100 * Day, s)
      check curatorDue(92 * Day, 100 * Day, s)
      check not curatorDue(0, 100 * Day, CuratorSettings(enabled: false, intervalDays: 7))

    test "stale: neither used nor created within the window; the person's own skills never":
      let s = CuratorSettings(enabled: true, intervalDays: 7, staleDays: 90)
      let now = 200 * Day
      let skills = @[
        SkillAge(name: "old-unused", createdBy: "review", createdAtMs: 10 * Day, lastUsedMs: 0),
        SkillAge(name: "old-but-used", createdBy: "agent", createdAtMs: 10 * Day, lastUsedMs: 150 * Day),
        SkillAge(name: "new", createdBy: "review", createdAtMs: 150 * Day, lastUsedMs: 0),
        SkillAge(name: "mine", createdBy: "user", createdAtMs: 1 * Day, lastUsedMs: 0)]
      check staleSkills(skills, now, s) == @["old-unused"]

    test "the five newest backups are kept":
      check backupsToPrune(@["100", "300", "200", "600", "500", "400", "x"], keep = 5) == @["100"]
      check backupsToPrune(@["1", "2"], keep = 5).len == 0

    test "the consolidation instructions: merge near-duplicates, archive, never delete":
      check "skill_manage" in CuratorInstructions
      check "archive" in CuratorInstructions.toLowerAscii
      check "never" in CuratorInstructions.toLowerAscii

when isMainModule:
  runTests()
