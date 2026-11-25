## task_board — the `manage_tasks` tool on the person's paddock (PRD-roadmap
## E4.2). The board's rules are pure (domain/tasks/task_board_pure); here it
## is read from and written to `tasks.json` through the fs port, with the
## readable `TASKS.md` written beside it at each change. A file that cannot be
## read is an error, never replaced by an empty board.

import std/strutils
import ../core/pipeops
import ../core/tooling/native_tool_args
import ../domain/tasks/task_board_pure
import ../domain/automation/schedule_pure
import ../domain/automation/user_schedule_pure
import ../ports/fs
import ../ports/schedules

export task_board_pure

type
  TaskAgenda* = object
    ## Where a task an agent holds becomes that agent's turn on its due day
    ## (E4.4): the person's schedules, and who and where the turn answers.
    ## Empty: no turns are scheduled.
    schedules*: SchedulePort
    userId*:    string
    channel*:   string

const AgentTurnHourMs* = 12 * 3_600_000'i64
  ## The turn comes at noon UTC of the due day (09:00 in Brasília).

const
  BoardFile* = "tasks.json"
  BoardView* = "TASKS.md"

proc loadBoard*(fs: FsRuntimePort; paddockDir: string): Result[TaskBoard, string] =
  let path = paddockDir & "/" & BoardFile
  if fs.entryKind(path) == fekMissing:
    return ok(newBoard())
  let text = ? fs.readFile(path)
  parseBoard(text)

proc saveBoard(fs: FsRuntimePort; paddockDir: string; b: TaskBoard): Result[void, string] =
  ## tasks.json is the record; TASKS.md only a view of it. Once the record is
  ## written the change is made, whatever happens to the view (it is written
  ## again at the next change).
  ? fs.writeFile(paddockDir & "/" & BoardFile, boardJson(b))
  discard fs.writeFile(paddockDir & "/" & BoardView, renderMarkdown(b))
  ok()

proc listing(b: TaskBoard; state, assignee: string): Result[string, string] =
  var filter = none(TaskState)
  if state.strip.len > 0:
    filter = some(? parseTaskState(state))
  ## A filter that names nobody is a mistake to report, not an empty board.
  let who = ? normalAssignee(assignee)
  var view = TaskBoard(nextId: b.nextId)
  view.tasks = b.filtered(filter, who)
  ok(renderMarkdown(view))

func agentTurnPrompt*(t: BoardTask): string =
  ## Starts with the agent's mention, so the turn answers as that agent.
  t.assignee & " A tarefa " & t.id & " (\"" & t.title & "\") vence hoje e está " &
    "com você. Trabalhe nela agora; registre o andamento com manage_tasks " &
    "(action=note) e mova a tarefa quando o estado mudar."

proc syncAgentTurn(agenda: TaskAgenda; taskId: string; task: Option[BoardTask];
                   nowMs: int64): string =
  ## One schedule per task (`task-<id>` among the person's schedules), kept
  ## while an agent holds the task, it has a due day still ahead and it is not
  ## done; removed otherwise. Returns a sentence for the reply, or "".
  let wantsTurn = task.isSome and task.get.assignee.startsWith("@") and
                  task.get.dueMs > 0 and task.get.state != tsDone and
                  task.get.dueMs + AgentTurnHourMs > nowMs
  if not agenda.schedules.schedulesAvailable or agenda.userId.len == 0:
    return (if wantsTurn: " (Schedules are off here, so the agent's turn will not be scheduled.)"
            else: "")
  let id = userScheduleId(agenda.userId, "task-" & taskId)
  discard agenda.schedules.remove(id)
  if not wantsTurn:
    return ""
  let t = task.get
  let at = t.dueMs + AgentTurnHourMs
  let spec = ScheduleSpec(id: id, cronExpr: AtPrefix & " " & $at, userId: agenda.userId,
                          channel: agenda.channel, payload: agentTurnPrompt(t),
                          catchUp: scOnce, enabled: true, createdAtMs: nowMs)
  let inserted = agenda.schedules.insert(spec)
  if inserted.isErr or not inserted.get:
    return " (The agent's turn could not be scheduled: " &
           (if inserted.isErr: inserted.error else: "a schedule with that name exists") & ".)"
  " " & t.assignee & " will work on it on " & dateOf(t.dueMs) & " at 12:00 UTC."

proc performManageTasks*(fs: FsRuntimePort; paddockDir: string;
                         ctx: ManageTasksContext; nowMs: int64;
                         agenda: TaskAgenda = TaskAgenda()): Result[string, string] =
  if paddockDir.len == 0:
    return err("Error: no workspace for tasks")
  let board = (? loadBoard(fs, paddockDir).mapErr(proc(e: string): string =
    "Error: the task board cannot be read (" & e & "); it was left as it is"))
  var next: TaskBoard
  var reply: string
  var addedId = ""
  case ctx.action
  of "list":
    return board.listing(ctx.state, ctx.assignee).mapErr(proc(e: string): string = "Error: " & e)
  of "add":
    let due = ? parseDueDate(ctx.due).mapErr(proc(e: string): string = "Error: " & e)
    var (added, task) = ? board.addTask(ctx.title, nowMs, due).mapErr(
      proc(e: string): string = "Error: " & e)
    if ctx.assignee.strip.len > 0:
      added = ? added.assignTask(task.id, ctx.assignee, nowMs).mapErr(
        proc(e: string): string = "Error: " & e)
    next = added
    addedId = task.id
    reply = "Added " & task.id & ": " & task.title
    if ctx.assignee.strip.len > 0:
      reply.add " (" & ctx.assignee.strip.toLowerAscii & ")"
    if due > 0:
      reply.add ", due " & dateOf(due)
    reply.add "."
  of "move":
    let state = ? parseTaskState(ctx.state).mapErr(proc(e: string): string = "Error: " & e)
    next = ? board.moveTask(ctx.id, state, nowMs).mapErr(proc(e: string): string = "Error: " & e)
    reply = "Moved " & ctx.id & " to " & $state & "."
  of "assign":
    next = ? board.assignTask(ctx.id, ctx.assignee, nowMs).mapErr(
      proc(e: string): string = "Error: " & e)
    reply = ctx.id & " is now " &
            (if ctx.assignee.strip.len > 0: ctx.assignee.strip.toLowerAscii & "'s." else: "the user's.")
  of "note":
    next = ? board.commentTask(ctx.id, ctx.text, nowMs).mapErr(
      proc(e: string): string = "Error: " & e)
    reply = "Noted on " & ctx.id & "."
  of "due":
    let due = ? parseDueDate(ctx.due).mapErr(proc(e: string): string = "Error: " & e)
    next = ? board.setDue(ctx.id, due, nowMs).mapErr(proc(e: string): string = "Error: " & e)
    reply = (if due > 0: ctx.id & " is due " & dateOf(due) & "." else: ctx.id & " has no due date now.")
  of "delete":
    next = ? board.deleteTask(ctx.id).mapErr(proc(e: string): string = "Error: " & e)
    reply = "Deleted " & ctx.id & "."
  else:
    return err("Error: unknown action '" & ctx.action & "'")
  ? saveBoard(fs, paddockDir, next).mapErr(proc(e: string): string =
    "Error: the task board was not saved (" & e & ")")
  let changed = if addedId.len > 0: addedId else: ctx.id.strip.toLowerAscii
  reply.add syncAgentTurn(agenda, changed, next.find(changed), nowMs)
  ok(reply)
