## turn_traces.nim — appending per-turn traces (domain/turn_trace_pure).
##
## Opt-in: DONKEY_TRACES=on. One line per turn in
## `{home}/state/traces/YYYY-MM-DD.jsonl` (UTC days), created readable only by
## the daemon's user; the first line of a new day removes the files older
## than DONKEY_TRACES_DAYS (14 by default). Through the fs port, like every
## file the app layer writes.

import std/[os, strutils]
import ../config/environment
import ../core/pipeops
import ../domain/turn_trace_pure
import ../ports/fs

const DefaultTraceDays* = 14

func tracesEnabled*(env: Environment): bool =
  env.get("DONKEY_TRACES").strip.toLowerAscii in ["1", "on", "true", "yes"]

func traceRetentionDays*(env: Environment): int =
  try:
    let days = parseInt(env.get("DONKEY_TRACES_DAYS").strip)
    if days > 0: days else: DefaultTraceDays
  except ValueError:
    DefaultTraceDays

proc appendTurnTrace*(fs: FsRuntimePort; homeDir: string; trace: TurnTrace;
                      nowMs: int64; days: int): Result[void, string] =
  let dir = homeDir / "state" / "traces"
  ? fs.createDir(dir)
  let name = traceFileName(nowMs)
  let path = dir / name
  let line = traceLine(trace) & "\n"
  var names: seq[string]
  for entry in fs.listDir(dir).get(@[]):
    names.add extractFilename(entry.path)
  if name in names:
    return fs.appendFile(path, line)
  ## A new day: its file starts private, and the expired days go.
  ? fs.writePrivate(path, line)
  for old in expiredTraceFiles(names, nowMs, days):
    discard fs.remove(dir / old, false)
  ok()
