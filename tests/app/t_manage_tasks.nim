## `manage_tasks` (PRD-roadmap E4.2): the board in the person's paddock,
## through the fs port. tasks.json is the record; TASKS.md the readable view.

import std/[os, strutils, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/task_board
import donkey/core/pipeops
import donkey/core/tooling/native_tool_args
import donkey/core/types
import donkey/domain/message
import donkey/domain/subagent_pure

const Now = 1_800_000_000_000'i64   ## 2027-01-15

proc paddock(tag: string): string =
  result = getTempDir() / ("donkey_tasks_" & tag)
  removeDir(result)
  createDir(result)

proc act(dir: string; c: ManageTasksContext): Result[string, string] =
  performManageTasks(newFsAdapter(), dir, c, Now)

proc runTests*() =
  suite "manage_tasks":

    test "a task is added, and both files are written":
      let dir = paddock("add")
      defer: removeDir(dir)
      let r = act(dir, ManageTasksContext(action: "add", title: "revisar contrato",
                                          due: "2027-01-20", assignee: "@juridico"))
      check r.isOk
      check "t1" in r.get
      check fileExists(dir / "tasks.json")
      let md = readFile(dir / "TASKS.md")
      check "t1 · revisar contrato — @juridico (até 2027-01-20)" in md

    test "move, note, assign and delete act on the stored board":
      let dir = paddock("flow")
      defer: removeDir(dir)
      discard act(dir, ManageTasksContext(action: "add", title: "a"))
      check act(dir, ManageTasksContext(action: "move", id: "t1", state: "doing")).isOk
      check act(dir, ManageTasksContext(action: "note", id: "t1", text: "começado")).isOk
      check act(dir, ManageTasksContext(action: "assign", id: "t1", assignee: "@pesquisa")).isOk
      let listed = act(dir, ManageTasksContext(action: "list")).get
      check "Fazendo" in listed and "@pesquisa" in listed and "começado" in listed
      check act(dir, ManageTasksContext(action: "delete", id: "t1")).isOk
      check "Nenhuma tarefa" in act(dir, ManageTasksContext(action: "list")).get

    test "list filters by state and assignee":
      let dir = paddock("filter")
      defer: removeDir(dir)
      discard act(dir, ManageTasksContext(action: "add", title: "a"))
      discard act(dir, ManageTasksContext(action: "add", title: "b", assignee: "@x"))
      let mine = act(dir, ManageTasksContext(action: "list", assignee: "@x")).get
      check "b" in mine and "· a" notin mine
      let todo = act(dir, ManageTasksContext(action: "list", state: "done")).get
      check "Nenhuma tarefa" in todo
      check act(dir, ManageTasksContext(action: "list", assignee: "x")).isErr

    test "mistakes come back as errors the model can fix":
      let dir = paddock("errors")
      defer: removeDir(dir)
      check act(dir, ManageTasksContext(action: "move", id: "t9", state: "done")).isErr
      discard act(dir, ManageTasksContext(action: "add", title: "a"))
      check act(dir, ManageTasksContext(action: "move", id: "t1", state: "later")).isErr
      check act(dir, ManageTasksContext(action: "add", title: "b", due: "amanhã")).isErr

    test "a damaged tasks.json is not overwritten":
      let dir = paddock("damaged")
      defer: removeDir(dir)
      writeFile(dir / "tasks.json", "{broken")
      check act(dir, ManageTasksContext(action: "add", title: "a")).isErr
      check readFile(dir / "tasks.json") == "{broken"

    test "a view that cannot be written does not undo the saved change":
      let dir = paddock("view")
      defer: removeDir(dir)
      createDir(dir / "TASKS.md")   ## a directory where the view should go
      let r = act(dir, ManageTasksContext(action: "add", title: "a"))
      check r.isOk
      check "t1" in readFile(dir / "tasks.json")

    test "the reply to add names the task on one line":
      let dir = paddock("reply")
      defer: removeDir(dir)
      let r = act(dir, ManageTasksContext(action: "add", title: "- ligar -",
                                          assignee: "@x", due: "2027-02-01")).get
      check '\n' notin r
      check "t1" in r and "- ligar -" in r and "@x" in r and "2027-02-01" in r

    test "the tool is dispatched for real and denied to subagents":
      let dir = paddock("dispatch")
      defer: removeDir(dir)
      let ctx = NativeCtx(uid: UserId("alice"), channel: ckTelegram,
                          fs: newFsAdapter(), paddockDir: dir)
      let made = waitFor executeNativeTool(ToolCallRequest(id: "1",
        name: "manage_tasks", inputJson: """{"action":"add","title":"ligar"}"""),
        ctx, newSessionState(), @[])
      check made.handled
      check "t1" in made.text
      check "manage_tasks" in SubagentHardDeniedTools

when isMainModule:
  runTests()
