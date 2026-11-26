## insights_tool — a person's own report, in the chat (open item of E7.8).
##
## The `insights` tool reads the trace files through the fs port, keeps only
## the person's turns, and sums them (domain/insights_pure); the learned
## skills they loaded most come after. `/insights` asks the agent to use it.

import std/[algorithm, os, strutils]
import ../core/pipeops
import ../domain/insights_pure
import ../ports/fs
import ./learned_skills
import ./turn_traces

const
  InsightsToolName* = "insights"
  InsightsToolDescription* =
    "The person's own usage report: their turns, tokens, the tools used most " &
    "and how often they failed, providers, channels, and the learned skills " &
    "loaded most. Use it when they ask for /insights or how they use you."
  InsightsToolSchema* =
    "{\"type\":\"object\",\"properties\":{\"days\":{\"type\":\"integer\"," &
    "\"description\":\"How many days back (default 30)\"}}}"
  DayMs = 86_400_000'i64

proc performInsights*(fs: FsRuntimePort; paddockDir, userId: string;
                      sinceMs: int64): Result[string, string] =
  let lines = traceLines(fs, parentDir(paddockDir.strip(leading = false, chars = {'/'})),
                         sinceMs, userId)
  var report = formatInsights(aggregateInsights(lines),
    if sinceMs > 0: "the last " & $max(1, (epochMs() - sinceMs) div DayMs) & " days"
    else: "all kept traces")
  var skills = newLearnedSkills(fs, paddockDir).list()
  skills.sort(proc(a, b: LearnedSkill): int = cmp(b.usage.loads, a.usage.loads))
  if skills.len > 0:
    report.add "\nLearned skills loaded most:"
    for i, s in skills:
      if i >= 5: break
      report.add "\n  " & s.doc.name & ": " & $s.usage.loads
  ok(report)
