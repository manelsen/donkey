## skill_tools — skill_manage and skill_view (E7.2): the agent writes and
## reads its skills for the person it serves, in that person's store
## (app/learned_skills), every write through the guard.

import std/strutils
import ../core/pipeops
import ../ports/fs
import ./learned_skills

export learned_skills

proc performSkillManage*(fs: FsRuntimePort; paddockDir: string; c: SkillManageContext;
                         nowMs: int64; by = "agent"): Result[string, string] =
  let store = newLearnedSkills(fs, paddockDir)
  case c.action
  of "create":
    ? store.create(c.content, by = by, note = c.note, nowMs = nowMs)
    let doc = ? parseSkillMd(c.content)
    ok("Skill " & doc.name & " saved.")
  of "edit":
    ? store.update(c.name, c.content, by = by, nowMs = nowMs)
    ok("Skill " & c.name & " updated.")
  of "patch":
    ? store.patch(c.name, c.oldText, c.newText, by = by, nowMs = nowMs)
    ok("Skill " & c.name & " patched.")
  of "archive":
    ? store.archive(c.name, nowMs)
    ok("Skill " & c.name & " archived; restore brings it back.")
  of "restore":
    ? store.restore(c.name)
    ok("Skill " & c.name & " restored.")
  else:
    var lines: seq[string]
    for s in store.list():
      lines.add s.doc.name & ": " & s.doc.description
    let archived = store.archived()
    if archived.len > 0:
      lines.add "archived: " & archived.join(", ")
    ok(if lines.len == 0: "No learned skills yet." else: lines.join("\n"))

proc performSkillView*(fs: FsRuntimePort; paddockDir, name: string;
                       nowMs: int64 = 0): Result[string, string] =
  let store = newLearnedSkills(fs, paddockDir)
  let doc = ? store.read(name.strip)
  store.recordUse(name.strip, nowMs)
  ok(renderSkillMd(doc))
