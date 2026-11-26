## learned_skills — the skills an agent learns, one store per person (E7.1).
##
## `{paddock}/learned_skills/<name>/SKILL.md`, with where each one came from
## in `.provenance.json` beside them; archived skills move to `.archive/`
## and can come back: nothing is deleted. Every write goes through the
## format check and the guard (domain/skills/learned_skill_pure): a blocked
## skill is not written and the reason comes back. Through the fs port.

import std/[algorithm, json, os, strutils, tables]
import ../core/pipeops
import ../domain/skills/learned_skill_pure
import ../ports/fs

export learned_skill_pure

const
  LearnedSkillsDirName* = "learned_skills"
  ProvenanceFile = ".provenance.json"
  UsageFile = ".usage.json"
  ArchiveDirName = ".archive"

type
  SkillMeta* = object
    createdBy*:   string   ## agent, review, curator, user
    note*:        string   ## where it came from
    createdAtMs*: int64
    updatedAtMs*: int64
    updatedBy*:   string

  SkillUsage* = object
    loads*:      int     ## times skill_view loaded it
    lastUsedMs*: int64   ## 0: never

  LearnedSkill* = object
    doc*:   SkillDoc
    meta*:  SkillMeta
    usage*: SkillUsage

  LearnedSkills* = object
    fs:   FsRuntimePort
    root*: string

func validPaddockId*(id: string): bool =
  ## A person's id as it names their paddock: no separator, no '..', so it
  ## cannot leave the paddocks directory.
  id.len > 0 and id.len <= 128 and id[0] != '.' and ".." notin id and
    id.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'})

proc newLearnedSkills*(fs: FsRuntimePort; paddockDir: string): LearnedSkills =
  LearnedSkills(fs: fs, root: paddockDir / LearnedSkillsDirName)

proc skillDir(s: LearnedSkills; name: string): string = s.root / name
proc skillFile(s: LearnedSkills; name: string): string = s.root / name / "SKILL.md"

proc loadMeta(s: LearnedSkills): Table[string, SkillMeta] =
  result = initTable[string, SkillMeta]()
  let text = s.fs.readFile(s.root / ProvenanceFile)
  if text.isErr: return
  try:
    let j = parseJson(text.get)
    if j.kind != JObject: return
    for name, m in j.pairs:
      result[name] = SkillMeta(createdBy: m{"created_by"}.getStr, note: m{"note"}.getStr,
        createdAtMs: m{"created_ms"}.getBiggestInt, updatedAtMs: m{"updated_ms"}.getBiggestInt,
        updatedBy: m{"updated_by"}.getStr)
  except CatchableError:
    discard   ## unreadable provenance costs the history, never the skills

proc saveMeta(s: LearnedSkills; meta: Table[string, SkillMeta]): Result[void, string] =
  var j = newJObject()
  for name, m in meta:
    j[name] = %* {"created_by": m.createdBy, "note": m.note, "created_ms": m.createdAtMs,
                  "updated_ms": m.updatedAtMs, "updated_by": m.updatedBy}
  s.fs.writePrivate(s.root / ProvenanceFile, $j)

proc loadUsage(s: LearnedSkills): Table[string, SkillUsage] =
  result = initTable[string, SkillUsage]()
  let text = s.fs.readFile(s.root / UsageFile)
  if text.isErr: return
  try:
    let j = parseJson(text.get)
    if j.kind != JObject: return
    for name, u in j.pairs:
      result[name] = SkillUsage(loads: u{"loads"}.getInt, lastUsedMs: u{"last_ms"}.getBiggestInt)
  except CatchableError:
    discard   ## unreadable usage only restarts the counts

proc recordUse*(s: LearnedSkills; name: string; nowMs: int64) =
  ## A load of `name`, for the curator and the journey (E7.3). Best effort:
  ## a failed write loses one count, never the skill.
  if not validSkillName(name) or s.fs.entryKind(s.skillFile(name)) != fekFile:
    return
  var usage = s.loadUsage()
  var u = usage.getOrDefault(name)
  inc u.loads
  u.lastUsedMs = nowMs
  usage[name] = u
  var j = newJObject()
  for n, x in usage:
    j[n] = %* {"loads": x.loads, "last_ms": x.lastUsedMs}
  discard s.fs.writePrivate(s.root / UsageFile, $j)

proc checked(text: string): Result[SkillDoc, string] =
  let doc = ? parseSkillMd(text)
  let findings = scanSkill(doc)
  if findings.len > 0:
    return err(guardReport(findings))
  ok(doc)

proc read*(s: LearnedSkills; name: string): Result[SkillDoc, string] =
  if not validSkillName(name): return err("not a skill name: " & name)
  parseSkillMd(? s.fs.readFile(s.skillFile(name)))

proc list*(s: LearnedSkills): seq[LearnedSkill] =
  ## The active skills, by name; a broken file is left out.
  let meta = s.loadMeta()
  let usage = s.loadUsage()
  var names: seq[string]
  for e in s.fs.listDir(s.root).get(@[]):
    let name = extractFilename(e.path)
    if validSkillName(name) and e.kind == fekDir: names.add name
  names.sort()
  for name in names:
    let doc = s.read(name)
    if doc.isOk:
      result.add LearnedSkill(doc: doc.get, meta: meta.getOrDefault(name),
                              usage: usage.getOrDefault(name))

proc write(s: LearnedSkills; doc: SkillDoc; by, note: string; nowMs: int64;
           creating: bool): Result[void, string] =
  ? s.fs.createDir(s.skillDir(doc.name))
  ? s.fs.writePrivate(s.skillFile(doc.name), renderSkillMd(doc))
  var meta = s.loadMeta()
  var m = meta.getOrDefault(doc.name)
  if creating:
    m = SkillMeta(createdBy: by, note: note, createdAtMs: nowMs)
  m.updatedAtMs = nowMs
  m.updatedBy = by
  meta[doc.name] = m
  s.saveMeta(meta)

proc create*(s: LearnedSkills; text: string; by: string; note = ""; nowMs: int64): Result[void, string] =
  let doc = ? checked(text)
  if s.fs.entryKind(s.skillFile(doc.name)) != fekMissing:
    return err("the skill " & doc.name & " exists; edit or patch it")
  s.write(doc, by, note, nowMs, creating = true)

proc update*(s: LearnedSkills; name, text: string; by: string; nowMs: int64): Result[void, string] =
  if not validSkillName(name): return err("not a skill name: " & name)
  discard ? s.read(name)
  let doc = ? checked(text)
  if doc.name != name:
    return err("an edit keeps the name " & name & "; create another skill instead")
  s.write(doc, by, "", nowMs, creating = false)

proc patch*(s: LearnedSkills; name, oldText, newText: string; by: string; nowMs: int64): Result[void, string] =
  let current = ? s.read(name)
  let rendered = renderSkillMd(current)
  let at = rendered.find(oldText)
  if oldText.len == 0 or at < 0:
    return err("the passage to replace is not in " & name)
  if rendered.find(oldText, at + 1) >= 0:
    return err("the passage appears more than once in " & name & "; give more of it")
  s.update(name, rendered[0 ..< at] & newText & rendered[at + oldText.len .. ^1], by, nowMs)

proc archive*(s: LearnedSkills; name: string; nowMs: int64): Result[void, string] =
  if not validSkillName(name): return err("not a skill name: " & name)
  if s.fs.entryKind(s.skillDir(name)) != fekDir:
    return err("no skill " & name)
  ? s.fs.createDir(s.root / ArchiveDirName)
  ## Never over an earlier copy: the same millisecond gets a suffix.
  var dest = s.root / ArchiveDirName / (name & "@" & $nowMs)
  var extra = 0
  while s.fs.entryKind(dest) != fekMissing:
    inc extra
    dest = s.root / ArchiveDirName / (name & "@" & $nowMs & "-" & $extra)
  s.fs.move(s.skillDir(name), dest)

proc archived*(s: LearnedSkills): seq[string] =
  for e in s.fs.listDir(s.root / ArchiveDirName).get(@[]):
    let entry = extractFilename(e.path)
    let at = entry.rfind('@')
    let name = if at > 0: entry[0 ..< at] else: entry
    if validSkillName(name) and name notin result: result.add name
  result.sort()

proc restore*(s: LearnedSkills; name: string): Result[void, string] =
  ## The most recently archived copy of `name`.
  if not validSkillName(name): return err("not a skill name: " & name)
  if s.fs.entryKind(s.skillDir(name)) != fekMissing:
    return err("a skill " & name & " is active; archive it first")
  var latest = ""
  var latestMs = -1'i64
  for e in s.fs.listDir(s.root / ArchiveDirName).get(@[]):
    let entry = extractFilename(e.path)
    if entry.startsWith(name & "@"):
      try:
        let stamp = entry[name.len + 1 .. ^1]
        let dash = stamp.find('-')
        let ms = parseBiggestInt(if dash > 0: stamp[0 ..< dash] else: stamp)
        if ms > latestMs: (latest, latestMs) = (entry, ms)
      except ValueError: discard
  if latest.len == 0: return err("no archived skill " & name)
  s.fs.move(s.root / ArchiveDirName / latest, s.skillDir(name))

# ── The journey (E7.7) ───────────────────────────────────────────────────────

func dayOf(ms: int64): string =
  ## YYYY-MM-DD (UTC) of an epoch ms, without a clock (Hinnant's algorithm).
  if ms <= 0: return "-"
  let z = ms div 86_400_000 + 719_468
  let era = (if z >= 0: z else: z - 146_096) div 146_097
  let doe = z - era * 146_097
  let yoe = (doe - doe div 1460 + doe div 36_524 - doe div 146_096) div 365
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = doy - (153 * mp + 2) div 5 + 1
  let m = if mp < 10: mp + 3 else: mp - 9
  let y = yoe + era * 400 + (if m <= 2: 1 else: 0)
  $y & "-" & align($m, 2, '0') & "-" & align($d, 2, '0')

func journeyLine*(s: LearnedSkill): string =
  ## One skill as the person or the operator reads it.
  result = s.doc.name & " — " & s.doc.description & "\n  written by " &
    (if s.meta.createdBy.len > 0: s.meta.createdBy else: "?") & " on " & dayOf(s.meta.createdAtMs) &
    ", loaded " & $s.usage.loads & "×" &
    (if s.usage.lastUsedMs > 0: " (last " & dayOf(s.usage.lastUsedMs) & ")" else: "")
  if s.meta.note.len > 0:
    result.add "\n  from: " & s.meta.note

proc journey*(store: LearnedSkills): string =
  var parts: seq[string]
  for s in store.list(): parts.add journeyLine(s)
  let archived = store.archived()
  if archived.len > 0: parts.add "archived: " & archived.join(", ")
  if parts.len == 0: "No learned skills yet." else: parts.join("\n")

# ── Shared skills: promoted by the operator to everyone ──────────────────────

func homeOfPaddock*(paddockDir: string): string =
  ## `{home}/paddocks/<uuid>` → `{home}`: where the shared store lives.
  parentDir(parentDir(paddockDir.strip(leading = false, chars = {'/'})))

proc promoteSkill*(fs: FsRuntimePort; home, userId, name: string; nowMs: int64): Result[void, string] =
  ## One person's skill, copied to the instance's store for every person,
  ## through the guard again and recorded as the operator's.
  if not validPaddockId(userId): return err("not a person id: " & userId)
  let doc = ? newLearnedSkills(fs, home / "paddocks" / userId).read(name)
  newLearnedSkills(fs, home).create(renderSkillMd(doc), by = "operator",
                                    note = "promoted from " & userId, nowMs = nowMs)

proc availableSkills*(fs: FsRuntimePort; paddockDir: string): seq[SkillDoc] =
  ## The person's skills and the shared ones; theirs win on a name.
  var names: seq[string]
  for s in newLearnedSkills(fs, paddockDir).list():
    result.add s.doc
    names.add s.doc.name
  for s in newLearnedSkills(fs, homeOfPaddock(paddockDir)).list():
    if s.doc.name notin names: result.add s.doc
