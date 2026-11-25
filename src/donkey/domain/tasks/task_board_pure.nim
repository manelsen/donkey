## task_board_pure — a small task board the person and their agents keep
## together (PRD-roadmap E4.1).
##
## The board is a value: every change returns a new board, or an error that
## says why it cannot be made (unknown task, bad assignee, empty title, a
## full board). Stored as JSON in the paddock (`tasks.json`), with a readable
## `TASKS.md` written beside it at each change, like the other `.md` files.
## A task is the person's or one of their named agents' (`@name`).
##
## `proc` where JSON is built or parsed, or a date formatted (ADR-007).

import std/[json, options, strutils, times]
import ../../core/pipeops
import ../agents/agent_name_pure

export options

const
  MaxTasks* = 200
  MaxTitleLen* = 200
  MaxNoteLen* = 2_000
  MaxNotesPerTask* = 50

type
  TaskState* = enum
    tsTodo = "todo"
    tsDoing = "doing"
    tsBlocked = "blocked"
    tsDone = "done"

  TaskNote* = object
    atMs*: int64
    text*: string

  BoardTask* = object
    id*:        string    ## t1, t2, … never reused
    title*:     string
    state*:     TaskState
    assignee*:  string    ## "" = the person; "@name" = a named agent
    dueMs*:     int64     ## 0 = no due date
    createdMs*: int64
    updatedMs*: int64
    doneMs*:    int64     ## when it was last moved to done; 0 otherwise
    notes*:     seq[TaskNote]

  TaskBoard* = object
    tasks*:  seq[BoardTask]
    nextId*: int

func newBoard*(): TaskBoard = TaskBoard(nextId: 1)

func indexOf(b: TaskBoard; id: string): int =
  for i, t in b.tasks:
    if t.id == id.strip.toLowerAscii:
      return i
  -1

func find*(b: TaskBoard; id: string): Option[BoardTask] =
  let i = b.indexOf(id)
  if i < 0: none(BoardTask) else: some(b.tasks[i])

func unknown(id: string): string = "no task " & id.strip

func addTask*(b: TaskBoard; title: string; nowMs: int64;
              dueMs = 0'i64): Result[(TaskBoard, BoardTask), string] =
  let t = title.strip
  if t.len == 0:
    return err("a task needs a title")
  if t.len > MaxTitleLen:
    return err("the title is longer than " & $MaxTitleLen & " characters")
  if b.tasks.len >= MaxTasks:
    return err("the board is full (" & $MaxTasks & " tasks); close or delete some first")
  var next = b
  let task = BoardTask(id: "t" & $b.nextId, title: t, state: tsTodo,
                       dueMs: max(dueMs, 0), createdMs: nowMs, updatedMs: nowMs)
  next.tasks.add task
  inc next.nextId
  ok((next, task))

func moveTask*(b: TaskBoard; id: string; state: TaskState;
               nowMs: int64): Result[TaskBoard, string] =
  let i = b.indexOf(id)
  if i < 0:
    return err(unknown(id))
  var next = b
  next.tasks[i].state = state
  next.tasks[i].updatedMs = nowMs
  next.tasks[i].doneMs = if state == tsDone: nowMs else: 0
  ok(next)

func normalAssignee*(raw: string): Result[string, string] =
  ## "" (the person) or "@name" of a valid agent name, lower case.
  let a = raw.strip.toLowerAscii
  if a.len == 0:
    return ok("")
  if not a.startsWith("@") or not validAgentName(a[1 .. ^1]):
    return err("an assignee is empty (you) or @agent-name")
  ok(a)

func assignTask*(b: TaskBoard; id, assignee: string;
                 nowMs: int64): Result[TaskBoard, string] =
  let i = b.indexOf(id)
  if i < 0:
    return err(unknown(id))
  let who = ? normalAssignee(assignee)
  var next = b
  next.tasks[i].assignee = who
  next.tasks[i].updatedMs = nowMs
  ok(next)

func commentTask*(b: TaskBoard; id, text: string;
                  nowMs: int64): Result[TaskBoard, string] =
  let i = b.indexOf(id)
  if i < 0:
    return err(unknown(id))
  let note = text.strip
  if note.len == 0:
    return err("a note needs text")
  if note.len > MaxNoteLen:
    return err("the note is longer than " & $MaxNoteLen & " characters")
  var next = b
  next.tasks[i].notes.add TaskNote(atMs: nowMs, text: note)
  if next.tasks[i].notes.len > MaxNotesPerTask:
    next.tasks[i].notes.delete(0)
  next.tasks[i].updatedMs = nowMs
  ok(next)

func setDue*(b: TaskBoard; id: string; dueMs: int64;
             nowMs: int64): Result[TaskBoard, string] =
  let i = b.indexOf(id)
  if i < 0:
    return err(unknown(id))
  var next = b
  next.tasks[i].dueMs = max(dueMs, 0)
  next.tasks[i].updatedMs = nowMs
  ok(next)

func deleteTask*(b: TaskBoard; id: string): Result[TaskBoard, string] =
  let i = b.indexOf(id)
  if i < 0:
    return err(unknown(id))
  var next = b
  next.tasks.delete(i)
  ok(next)

func filtered*(b: TaskBoard; state = none(TaskState); assignee = ""): seq[BoardTask] =
  let who = assignee.strip.toLowerAscii
  for t in b.tasks:
    if state.isSome and t.state != state.get:
      continue
    if who.len > 0 and t.assignee != who:
      continue
    result.add t

# ── The readable board ───────────────────────────────────────────────────────

func stateHeading(s: TaskState): string =
  case s
  of tsTodo: "A fazer"
  of tsDoing: "Fazendo"
  of tsBlocked: "Bloqueadas"
  of tsDone: "Feitas"

proc dateOf*(ms: int64): string =
  ## The UTC day of `ms`, YYYY-MM-DD.
  fromUnix(ms div 1000).utc.format("yyyy-MM-dd")

proc taskLine*(t: BoardTask): string =
  result = "- " & t.id & " · " & t.title
  if t.assignee.len > 0:
    result.add " — " & t.assignee
  if t.dueMs > 0:
    result.add " (até " & dateOf(t.dueMs) & ")"
  if t.notes.len > 0:
    result.add "\n  - " & t.notes[^1].text.replace("\n", " ")

proc renderMarkdown*(b: TaskBoard): string =
  result = "# Tarefas\n\n"
  if b.tasks.len == 0:
    return result & "Nenhuma tarefa.\n"
  for s in TaskState:
    let group = b.filtered(state = some(s))
    if group.len == 0:
      continue
    result.add "## " & stateHeading(s) & "\n\n"
    for t in group:
      result.add taskLine(t) & "\n"
    result.add "\n"

# ── Storage ──────────────────────────────────────────────────────────────────

proc boardJson*(b: TaskBoard): string =
  var tasks = newJArray()
  for t in b.tasks:
    var notes = newJArray()
    for n in t.notes:
      notes.add(%* {"at_ms": n.atMs, "text": n.text})
    tasks.add(%* {"id": t.id, "title": t.title, "state": $t.state,
                  "assignee": t.assignee, "due_ms": t.dueMs,
                  "created_ms": t.createdMs, "updated_ms": t.updatedMs,
                  "done_ms": t.doneMs, "notes": notes})
  $(%* {"next_id": b.nextId, "tasks": tasks})

func stateNamed(name: string; s: var TaskState): bool =
  for k in TaskState:
    if $k == name:
      s = k
      return true
  false

proc parseBoard*(text: string): Result[TaskBoard, string] =
  ## "" is a board not written yet: empty.
  if text.strip.len == 0:
    return ok(newBoard())
  let j =
    try: parseJson(text)
    except CatchableError: return err("tasks.json is not JSON")
  if j.kind != JObject or j{"tasks"}.isNil or j["tasks"].kind != JArray:
    return err("tasks.json has no task list")
  var b = TaskBoard(nextId: max(j{"next_id"}.getInt(1), 1))
  for item in j["tasks"]:
    var t = BoardTask(id: item{"id"}.getStr, title: item{"title"}.getStr,
                      assignee: item{"assignee"}.getStr,
                      dueMs: item{"due_ms"}.getBiggestInt,
                      createdMs: item{"created_ms"}.getBiggestInt,
                      updatedMs: item{"updated_ms"}.getBiggestInt,
                      doneMs: item{"done_ms"}.getBiggestInt)
    if t.id.len == 0 or t.title.len == 0 or
        not stateNamed(item{"state"}.getStr, t.state):
      return err("tasks.json has a task without id, title or state")
    if not item{"notes"}.isNil and item["notes"].kind == JArray:
      for n in item["notes"]:
        t.notes.add TaskNote(atMs: n{"at_ms"}.getBiggestInt, text: n{"text"}.getStr)
    if b.indexOf(t.id) >= 0:
      return err("tasks.json has two tasks with the id " & t.id)
    b.tasks.add t
    ## A next_id behind the ids already used (an edited file) must not hand
    ## out one of them again.
    if t.id.startsWith("t"):
      try: b.nextId = max(b.nextId, parseInt(t.id[1 .. ^1]) + 1)
      except ValueError: discard
  ok(b)

proc parseDueDate*(text: string): Result[int64, string] =
  ## "YYYY-MM-DD" (the start of that UTC day) or "" for no due date.
  let t = text.strip
  if t.len == 0:
    return ok(0'i64)
  try:
    ok(parse(t, "yyyy-MM-dd", utc()).toTime.toUnix * 1000)
  except CatchableError:
    err("a due date is YYYY-MM-DD, got '" & t & "'")

func parseTaskState*(text: string): Result[TaskState, string] =
  var s: TaskState
  let t = text.strip.toLowerAscii
  if stateNamed(t, s):
    return ok(s)
  err("a state is todo, doing, blocked or done, got '" & t & "'")
