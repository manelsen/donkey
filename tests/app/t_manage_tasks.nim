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
import donkey/domain/automation/schedule_pure
import donkey/domain/automation/schedule_view
import donkey/ports/schedules

const Now = 1_800_000_000_000'i64   ## 2027-01-15

proc paddock(tag: string): string =
  result = getTempDir() / ("donkey_tasks_" & tag)
  removeDir(result)
  createDir(result)

proc act(dir: string; c: ManageTasksContext): Result[string, string] =
  performManageTasks(newFsAdapter(), dir, c, Now)

type Agenda = ref object
  rows: seq[ScheduleViewRecord]

proc port(a: Agenda): SchedulePort =
  SchedulePort(
    all: proc(): Result[seq[ScheduleViewRecord], string] {.gcsafe, raises: [].} =
      ok(a.rows),
    insert: proc(spec: ScheduleSpec): Result[bool, string] {.gcsafe, raises: [].} =
      for r in a.rows:
        if r.spec.id == spec.id: return ok(false)
      a.rows.add ScheduleViewRecord(spec: spec, lastRunAtMs: spec.createdAtMs)
      ok(true),
    remove: proc(id: string): Result[void, string] {.gcsafe, raises: [].} =
      var kept: seq[ScheduleViewRecord]
      for r in a.rows:
        if r.spec.id != id: kept.add r
      a.rows = kept
      ok(),
    setEnabled: proc(id: string; enabled: bool; nowMs: int64): Result[bool, string] {.gcsafe, raises: [].} =
      ok(false))

proc withAgenda(dir: string; a: Agenda; c: ManageTasksContext): Result[string, string] =
  performManageTasks(newFsAdapter(), dir, c, Now,
                     TaskAgenda(schedules: port(a), userId: "alice", channel: "telegram"))

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

    test "a task an agent holds with a due date becomes that agent's turn on the day":
      let dir = paddock("agent-turn")
      defer: removeDir(dir)
      let a = Agenda()
      let r = withAgenda(dir, a, ManageTasksContext(action: "add", title: "levantar preços",
        assignee: "@pesquisa", due: "2027-01-20")).get
      check a.rows.len == 1
      let spec = a.rows[0].spec
      check spec.userId == "alice" and spec.channel == "telegram"
      check parseTrigger(spec.cronExpr).get.atMs == parseDueDate("2027-01-20").get + 12 * 3_600_000
      check spec.payload.startsWith("@pesquisa ")
      check "t1" in spec.payload and "levantar preços" in spec.payload
      check "@pesquisa" in r and "2027-01-20" in r

    test "the turn follows the task: moved due, new agent, done or deleted":
      let dir = paddock("agent-sync")
      defer: removeDir(dir)
      let a = Agenda()
      discard withAgenda(dir, a, ManageTasksContext(action: "add", title: "x",
        assignee: "@pesquisa", due: "2027-01-20"))
      discard withAgenda(dir, a, ManageTasksContext(action: "due", id: "t1", due: "2027-01-25"))
      check a.rows.len == 1
      check parseTrigger(a.rows[0].spec.cronExpr).get.atMs ==
            parseDueDate("2027-01-25").get + 12 * 3_600_000
      discard withAgenda(dir, a, ManageTasksContext(action: "assign", id: "t1", assignee: "@juridico"))
      check a.rows.len == 1 and a.rows[0].spec.payload.startsWith("@juridico ")
      discard withAgenda(dir, a, ManageTasksContext(action: "move", id: "t1", state: "done"))
      check a.rows.len == 0
      discard withAgenda(dir, a, ManageTasksContext(action: "move", id: "t1", state: "todo"))
      check a.rows.len == 1
      discard withAgenda(dir, a, ManageTasksContext(action: "delete", id: "t1"))
      check a.rows.len == 0

    test "no turn for the person's own tasks, without a due date, or already past":
      let dir = paddock("agent-none")
      defer: removeDir(dir)
      let a = Agenda()
      discard withAgenda(dir, a, ManageTasksContext(action: "add", title: "meu", due: "2027-01-20"))
      discard withAgenda(dir, a, ManageTasksContext(action: "add", title: "sem prazo", assignee: "@x"))
      discard withAgenda(dir, a, ManageTasksContext(action: "add", title: "atrasado",
        assignee: "@x", due: "2027-01-10"))
      check a.rows.len == 0

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
