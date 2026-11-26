## curator_pure — the curator of learned skills, the pure half (E7.6).
##
## Every so many days a pass looks after a person's skills: skills neither
## used nor created within the stale window are archived (never deleted,
## never one the person wrote), and a copy of the agent merges
## near-duplicates. Before any change the skills are backed up; the newest
## backups are kept. After hermes-agent (MIT), agent/curator.py.

import std/[algorithm, strutils]
import ../../config/environment

type
  CuratorSettings* = object
    enabled*:      bool
    intervalDays*: int
    staleDays*:    int

  SkillAge* = object
    name*, createdBy*: string
    createdAtMs*, lastUsedMs*: int64

const DayMs = 86_400_000'i64

func positive(env: Environment; name: string; default: int): int =
  try:
    let v = parseInt(env.get(name).strip)
    if v > 0: v else: default
  except ValueError: default

func curatorSettings*(env: Environment): CuratorSettings =
  CuratorSettings(
    enabled: env.get("DONKEY_CURATOR").strip.toLowerAscii notin ["0", "off", "false", "no"],
    intervalDays: positive(env, "DONKEY_CURATOR_INTERVAL_DAYS", 7),
    staleDays: positive(env, "DONKEY_CURATOR_STALE_DAYS", 90))

func curatorDue*(lastRunMs, nowMs: int64; s: CuratorSettings): bool =
  s.enabled and (lastRunMs <= 0 or nowMs - lastRunMs >= int64(s.intervalDays) * DayMs)

func staleSkills*(skills: seq[SkillAge]; nowMs: int64; s: CuratorSettings): seq[string] =
  let window = int64(s.staleDays) * DayMs
  for k in skills:
    if k.createdBy == "user": continue
    if nowMs - max(k.createdAtMs, k.lastUsedMs) >= window:
      result.add k.name

func backupsToPrune*(names: seq[string]; keep: int): seq[string] =
  ## Backups are named by their epoch ms; the oldest beyond `keep` go.
  var stamped: seq[(int64, string)]
  for n in names:
    try: stamped.add (parseBiggestInt(n), n)
    except ValueError: discard
  stamped.sort(proc(a, b: (int64, string)): int = cmp(b[0], a[0]))
  for i in keep ..< stamped.len:
    result.add stamped[i][1]

const CuratorInstructions* = """You look after the skills an assistant wrote for the person it serves. Below are all of them, each with its name, description and instructions.

Merge near-duplicates: when two skills cover the same task, fold what is useful from one into the other with skill_manage edit (keep the better name), then archive the one you emptied. Fix a description that does not say when to use the skill. Leave alone what is fine; leave alone any skill whose provenance is the person's own.

Never delete anything (archive is the only removal, and it can be undone); never add secrets, private data, or instructions you did not find in these skills. At most a few changes. When there is nothing to do, answer just: nothing."""
