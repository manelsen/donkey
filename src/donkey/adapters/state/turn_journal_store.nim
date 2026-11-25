## turn_journal_store — the turn journal on disk (ports/turn_journal).
##
## One file per turn in flight, `{dir}/{id}.json`, written atomically and
## private (durable_file): the start writes it, each new effect rewrites it
## before the tool runs, the end removes it. What is left at startup is
## exactly the turns a previous process died in, so there is nothing to
## compact. A file that cannot be read is renamed `.bad` and left for the
## operator. Used from the daemon loop only.

import std/[os, tables]
import ../../core/pipeops
import ../../domain/turn_journal_pure
import ../../ports/turn_journal
import ./durable_file

type
  TurnJournalStore* = ref object
    dir: string
    open: Table[string, TurnRecord]   ## this process's turns in flight
    writes*: int                      ## files written, for tests

proc newTurnJournalStore*(dir: string): TurnJournalStore =
  TurnJournalStore(dir: dir)

proc write(s: TurnJournalStore; r: TurnRecord): Result[void, string] {.raises: [].} =
  ? atomicWriteText(s.dir / journalFileName(r.id), recordJson(r), "w")
  inc s.writes
  ok()

proc begin(s: TurnJournalStore; r: TurnRecord): Result[void, string] {.raises: [].} =
  ? s.write(r)
  s.open[r.id] = r
  ok()

proc markEffect(s: TurnJournalStore; id, toolName: string): Result[void, string] {.raises: [].} =
  let current = s.open.getOrDefault(id)
  if current.id.len == 0:
    return err("turn journal: no turn " & id & " in flight")
  if toolName in current.effects:
    return ok()
  let next = current.withEffect(toolName)
  ? s.write(next)
  s.open[id] = next
  ok()

proc finish(s: TurnJournalStore; id: string): Result[void, string] {.raises: [].} =
  s.open.del(id)
  let path = s.dir / journalFileName(id)
  try:
    if fileExists(path):
      removeFile(path)
    ok()
  except CatchableError as e:
    err("turn journal: cannot remove " & path & ": " & e.msg)

proc pending(s: TurnJournalStore): Result[seq[TurnRecord], string] {.raises: [].} =
  var found: seq[TurnRecord]
  if not dirExists(s.dir):
    return ok(found)
  try:
    for kind, path in walkDir(s.dir):
      if kind != pcFile:
        continue
      let name = extractFilename(path)
      let id = turnIdOfFile(name)
      if id.len == 0 or id in s.open:
        continue
      let parsed = parseTurnRecord(readFile(path))
      if parsed.isOk and parsed.get.id == id:
        found.add parsed.get
      else:
        ? renamePath(path, path & ".bad")
    ok(found)
  except CatchableError as e:
    err("turn journal: cannot read " & s.dir & ": " & e.msg)

proc turnJournalPort*(s: TurnJournalStore): TurnJournalPort =
  TurnJournalPort(
    begin: proc(r: TurnRecord): Result[void, string] {.gcsafe, raises: [].} =
      s.begin(r),
    markEffect: proc(id, toolName: string): Result[void, string] {.gcsafe, raises: [].} =
      s.markEffect(id, toolName),
    finish: proc(id: string): Result[void, string] {.gcsafe, raises: [].} =
      s.finish(id),
    pending: proc(): Result[seq[TurnRecord], string] {.gcsafe, raises: [].} =
      s.pending())
