## Promoting a learned skill to everyone (open item of E7): the operator
## copies one person's skill into the instance's shared store; every person
## then sees it, read only, and their own skill of the same name wins.

import std/[json, os, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/learned_skills
import donkey/app/skill_tools
import donkey/core/pipeops

proc skill(name, desc: string): string =
  "---\nname: " & name & "\ndescription: " & desc & "\n---\n\nSteps for " & name & ".\n"

var n = 0
proc home(): string =
  inc n
  result = getTempDir() / ("donkey_shared_" & $n)
  removeDir(result)
  createDir(result / "paddocks" / "u1")
  createDir(result / "paddocks" / "u2")

proc runTests*() =
  suite "shared skills":

    test "a promoted skill is copied to the instance, recorded as the operator's":
      let h = home()
      check newLearnedSkills(newFsAdapter(), h / "paddocks" / "u1").create(
        skill("deploy", "Deploy."), by = "review", nowMs = 1).isOk
      check promoteSkill(newFsAdapter(), h, "u1", "deploy", nowMs = 2).isOk
      let shared = newLearnedSkills(newFsAdapter(), h).list()
      check shared.len == 1 and shared[0].meta.createdBy == "operator"
      check "u1" in shared[0].meta.note
      check promoteSkill(newFsAdapter(), h, "u1", "deploy", nowMs = 3).isErr   ## already shared
      check promoteSkill(newFsAdapter(), h, "u1", "nope", nowMs = 3).isErr

    test "every person sees the shared skills; their own of the same name wins":
      let h = home()
      check newLearnedSkills(newFsAdapter(), h).create(skill("deploy", "Shared deploy."),
                                                     by = "operator", nowMs = 1).isOk
      check newLearnedSkills(newFsAdapter(), h).create(skill("report", "Shared report."),
                                                     by = "operator", nowMs = 1).isOk
      check newLearnedSkills(newFsAdapter(), h / "paddocks" / "u2").create(
        skill("deploy", "My deploy."), by = "agent", nowMs = 1).isOk
      let docs = availableSkills(newFsAdapter(), h / "paddocks" / "u2")
      check docs.len == 2
      for d in docs:
        if d.name == "deploy": check d.description == "My deploy."
      check availableSkills(newFsAdapter(), h / "paddocks" / "u1").len == 2

    test "skill_view finds a shared skill; skill_manage cannot change it":
      let h = home()
      check newLearnedSkills(newFsAdapter(), h).create(skill("report", "Shared report."),
                                                     by = "operator", nowMs = 1).isOk
      let p = h / "paddocks" / "u1"
      check "Steps for report" in performSkillView(newFsAdapter(), p, "report", 5).get
      check performSkillManage(newFsAdapter(), p,
        parseSkillManage(parseJson("""{"action":"archive","name":"report"}""")).get, 5).isErr
      check newLearnedSkills(newFsAdapter(), h).list().len == 1

when isMainModule:
  runTests()
