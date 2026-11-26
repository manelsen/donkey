## curator — looks after a person's learned skills (E7.6).
##
## A pass, at most every `intervalDays` (curator_pure): back the skills up
## into `{paddock}/.curator_backups/<ms>/` (the five newest kept), archive
## the ones gone stale (never the person's own), then let a copy of the
## agent merge near-duplicates through skill_manage (as the curator). It
## records when it ran in `learned_skills/.curator_state`. A rollback brings
## the newest backup back, after backing up what it replaces, so it can be
## undone too. Nothing is ever deleted but old backups. Through the fs port.

import std/[os, strutils]
import chronos
import ../core/pipeops
import ../domain/skills/curator_pure
import ../ports/fs
import ./background_review
import ./learned_skills
import ./provider_executor

const
  BackupsDirName* = ".curator_backups"
  StateFile = ".curator_state"
  KeepBackups* = 5

proc lastRunMs(fs: FsRuntimePort; paddockDir: string): int64 =
  let text = fs.readFile(paddockDir / LearnedSkillsDirName / StateFile)
  if text.isErr: return 0
  try: parseBiggestInt(text.get.strip) except ValueError: 0

proc curatorDueFor*(fs: FsRuntimePort; paddockDir: string; s: CuratorSettings;
                    nowMs: int64): bool =
  curatorDue(lastRunMs(fs, paddockDir), nowMs, s)

proc backupNames*(fs: FsRuntimePort; paddockDir: string): seq[string] =
  for e in fs.listDir(paddockDir / BackupsDirName).get(@[]):
    if e.kind == fekDir: result.add extractFilename(e.path)

proc backup(fs: FsRuntimePort; paddockDir: string; nowMs: int64): Result[void, string] =
  let src = paddockDir / LearnedSkillsDirName
  if fs.entryKind(src) != fekDir: return ok()
  ? fs.createDir(paddockDir / BackupsDirName)
  var dest = paddockDir / BackupsDirName / $nowMs
  var extra = 0
  while fs.entryKind(dest) != fekMissing:
    inc extra
    dest = paddockDir / BackupsDirName / $(nowMs + extra)
  ? fs.copyTree(src, dest)
  for old in backupsToPrune(backupNames(fs, paddockDir), KeepBackups):
    discard fs.remove(paddockDir / BackupsDirName / old, true)
  ok()

proc catalog(store: LearnedSkills): string =
  ## Every active skill, in full, for the consolidating copy of the agent.
  for s in store.list():
    result.add "### " & s.doc.name & " (written by " &
      (if s.meta.createdBy.len > 0: s.meta.createdBy else: "unknown") & ", loaded " &
      $s.usage.loads & " times)\n" & renderSkillMd(s.doc) & "\n"

proc runCuratorPass*(callModel: AsyncCompleteFn; fs: FsRuntimePort; paddockDir: string;
                     s: CuratorSettings; nowMs: int64; provider = ""; model = ""):
    Future[Result[string, string]] {.async.} =
  let store = newLearnedSkills(fs, paddockDir)
  let skills = store.list()
  var notes: seq[string]
  if skills.len > 0:
    let saved = backup(fs, paddockDir, nowMs)
    if saved.isErr:
      return err(Result[string, string], "curator: no backup, nothing changed: " & saved.error)
    var ages: seq[SkillAge]
    for k in skills:
      ages.add SkillAge(name: k.doc.name, createdBy: k.meta.createdBy,
                        createdAtMs: k.meta.createdAtMs, lastUsedMs: k.usage.lastUsedMs)
    for name in staleSkills(ages, nowMs, s):
      if store.archive(name, nowMs).isOk: notes.add "archived " & name & " (stale)"
    if store.list().len > 1:
      let merged = await runSkillAgent(callModel, fs, paddockDir, CuratorInstructions,
        "The skills:\n\n" & catalog(store), provider, model, "curator", nowMs)
      if merged.isErr: notes.add merged.error
      elif merged.get.strip.toLowerAscii notin ["", "nothing"]: notes.add merged.get.strip
  discard fs.createDir(paddockDir / LearnedSkillsDirName)
  discard fs.writePrivate(paddockDir / LearnedSkillsDirName / StateFile, $nowMs)
  return ok(Result[string, string], if notes.len > 0: notes.join("; ") else: "nothing")

proc rollbackSkills*(fs: FsRuntimePort; paddockDir: string; nowMs: int64): Result[string, string] =
  ## The newest backup back in place; what it replaces is backed up first.
  var newest = ""
  var newestMs = -1'i64
  for n in backupNames(fs, paddockDir):
    try:
      let ms = parseBiggestInt(n)
      if ms > newestMs: (newest, newestMs) = (n, ms)
    except ValueError: discard
  if newest.len == 0: return err("no backup to roll back to")
  let source = paddockDir / BackupsDirName / newest
  let live = paddockDir / LearnedSkillsDirName
  ? backup(fs, paddockDir, nowMs)
  if fs.entryKind(live) != fekMissing:
    ? fs.remove(live, true)
  ? fs.copyTree(source, live)
  ok("restored the skills as they were at backup " & newest)
