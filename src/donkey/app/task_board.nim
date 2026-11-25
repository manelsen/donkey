## task_board — the `manage_tasks` tool on the person's paddock (PRD-roadmap
## E4.2). The board's rules are pure (domain/tasks/task_board_pure); here it
## is read from and written to `tasks.json` through the fs port, with the
## readable `TASKS.md` written beside it at each change. A file that cannot be
## read is an error, never replaced by an empty board.

import std/strutils
import ../core/pipeops
import ../core/tooling/native_tool_args
import ../domain/tasks/task_board_pure
import ../ports/fs

export task_board_pure

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
  ? fs.writeFile(paddockDir & "/" & BoardFile, boardJson(b))
  fs.writeFile(paddockDir & "/" & BoardView, renderMarkdown(b))

proc listing(b: TaskBoard; state, assignee: string): Result[string, string] =
  var filter = none(TaskState)
  if state.strip.len > 0:
    filter = some(? parseTaskState(state))
  var view = TaskBoard(nextId: b.nextId)
  view.tasks = b.filtered(filter, assignee)
  ok(renderMarkdown(view))

proc performManageTasks*(fs: FsRuntimePort; paddockDir: string;
                         ctx: ManageTasksContext; nowMs: int64): Result[string, string] =
  if paddockDir.len == 0:
    return err("Error: no workspace for tasks")
  let board = (? loadBoard(fs, paddockDir).mapErr(proc(e: string): string =
    "Error: the task board cannot be read (" & e & "); it was left as it is"))
  var next: TaskBoard
  var reply: string
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
    reply = "Added " & taskLine(next.find(task.id).get).strip(chars = {'-', ' '})
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
  ok(reply)
