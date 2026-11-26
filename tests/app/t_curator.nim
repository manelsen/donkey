## The curator (E7.6): a pass backs the skills up, archives what went stale
## (never the person's own), lets a copy of the agent merge near-duplicates,
## and remembers when it ran; a rollback brings the last backup back, after
## backing up what it replaces.

import std/[json, os, strutils, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/curator
import donkey/app/learned_skills
import donkey/app/provider_executor
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/skills/curator_pure

const Day = 86_400_000'i64

proc skill(name, desc: string): string =
  "---\nname: " & name & "\ndescription: " & desc & "\n---\n\nSteps for " & name & ".\n"

var n = 0
proc paddock(): string =
  inc n
  result = getTempDir() / ("donkey_curator_" & $n)
  removeDir(result); createDir(result)

proc quiet(): AsyncCompleteFn =
  result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
    return ok(CompletionResponse(text: "nothing"))

let settings = CuratorSettings(enabled: true, intervalDays: 7, staleDays: 90)

proc runTests*() =
  suite "curator":

    test "a pass backs up, archives the stale, spares the person's own, and records the run":
      let p = paddock()
      let store = newLearnedSkills(newFsAdapter(), p)
      check store.create(skill("old-one", "Old."), by = "review", nowMs = 1 * Day).isOk
      check store.create(skill("mine", "Mine."), by = "user", nowMs = 1 * Day).isOk
      check store.create(skill("fresh", "Fresh."), by = "review", nowMs = 150 * Day).isOk
      let r = waitFor runCuratorPass(quiet(), newFsAdapter(), p, settings, nowMs = 200 * Day)
      check r.isOk and "old-one" in r.get
      var names: seq[string]
      for s in store.list(): names.add s.doc.name
      check names == @["fresh", "mine"]
      check store.archived() == @["old-one"]
      check backupNames(newFsAdapter(), p).len == 1
      check not curatorDueFor(newFsAdapter(), p, settings, nowMs = 201 * Day)
      check curatorDueFor(newFsAdapter(), p, settings, nowMs = 208 * Day)

    test "the copy of the agent may merge duplicates through skill_manage":
      let p = paddock()
      let store = newLearnedSkills(newFsAdapter(), p)
      check store.create(skill("deploy-a", "Deploy."), by = "review", nowMs = 199 * Day).isOk
      check store.create(skill("deploy-b", "Deploy too."), by = "review", nowMs = 199 * Day).isOk
      var i = 0
      var firstAsk = ""
      let model: AsyncCompleteFn = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}:
          inc i
          if i == 1:
            firstAsk = req.messages[0].text
            return ok(CompletionResponse(toolCalls: @[ToolCallRequest(id: "1", name: "skill_manage",
              inputJson: $(%* {"action": "archive", "name": "deploy-b"}))]))
          return ok(CompletionResponse(text: "Merged."))
      check (waitFor runCuratorPass(model, newFsAdapter(), p, settings, nowMs = 200 * Day)).isOk
      check "deploy-b" in firstAsk and "Steps for deploy-b" in firstAsk
      check store.archived() == @["deploy-b"]

    test "no skills: nothing to back up, nothing to ask":
      let p = paddock()
      var asked = false
      let model: AsyncCompleteFn = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}: asked = true
        return ok(CompletionResponse(text: "nothing"))
      check (waitFor runCuratorPass(model, newFsAdapter(), p, settings, nowMs = 200 * Day)).isOk
      check not asked and backupNames(newFsAdapter(), p).len == 0

    test "a rollback restores the last backup and backs up what it replaces":
      let p = paddock()
      let store = newLearnedSkills(newFsAdapter(), p)
      check store.create(skill("old-one", "Old."), by = "review", nowMs = 1 * Day).isOk
      discard waitFor runCuratorPass(quiet(), newFsAdapter(), p, settings, nowMs = 200 * Day)
      check store.list().len == 0
      check rollbackSkills(newFsAdapter(), p, nowMs = 201 * Day).isOk
      check store.list().len == 1 and store.list()[0].doc.name == "old-one"
      check backupNames(newFsAdapter(), p).len == 2   ## the rollback can itself be undone

when isMainModule:
  runTests()
