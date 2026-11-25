## A small task board (PRD-roadmap E4.1): the person and their agents keep
## tasks together. Pure: the board is a value, every change returns a new one
## or says why it cannot be made.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/tasks/task_board_pure

const Day = 86_400_000'i64

proc runTests*() =
  suite "task board — changes":

    test "a new task is to do, numbered, unassigned":
      let (b, t) = newBoard().addTask("revisar contrato", nowMs = 1_000).get
      check t.id == "t1" and t.state == tsTodo
      check t.title == "revisar contrato" and t.assignee == ""
      check t.createdMs == 1_000
      check b.tasks.len == 1
      let (b2, t2) = b.addTask("ligar para o fornecedor", nowMs = 2_000).get
      check t2.id == "t2" and b2.tasks.len == 2

    test "a title is required and kept short":
      check newBoard().addTask("   ", nowMs = 0).isErr
      check newBoard().addTask("x".repeat(MaxTitleLen + 1), nowMs = 0).isErr

    test "a task moves between states, and a done task can be reopened":
      var b = newBoard().addTask("a", nowMs = 0).get[0]
      b = b.moveTask("t1", tsDoing, nowMs = 10).get
      check b.find("t1").get.state == tsDoing
      b = b.moveTask("t1", tsBlocked, nowMs = 20).get
      b = b.moveTask("t1", tsDone, nowMs = 30).get
      check b.find("t1").get.doneMs == 30
      b = b.moveTask("t1", tsTodo, nowMs = 40).get
      check b.find("t1").get.doneMs == 0

    test "an unknown task is an error, not a silent no-op":
      check newBoard().moveTask("t9", tsDone, nowMs = 0).isErr
      check newBoard().assignTask("t9", "@ana", nowMs = 0).isErr
      check newBoard().commentTask("t9", "oi", nowMs = 0).isErr

    test "a task is assigned to the person or to one of their agents":
      var b = newBoard().addTask("a", nowMs = 0).get[0]
      b = b.assignTask("t1", "@Pesquisa", nowMs = 1).get
      check b.find("t1").get.assignee == "@pesquisa"
      b = b.assignTask("t1", "", nowMs = 2).get
      check b.find("t1").get.assignee == ""
      check b.assignTask("t1", "@não válido", nowMs = 3).isErr
      check b.assignTask("t1", "ana", nowMs = 3).isErr   ## agents start with @

    test "notes are kept in order, each with its time":
      var b = newBoard().addTask("a", nowMs = 0).get[0]
      b = b.commentTask("t1", "pedi a planilha", nowMs = 5).get
      b = b.commentTask("t1", "chegou", nowMs = 9).get
      let t = b.find("t1").get
      check t.notes.len == 2 and t.notes[1].text == "chegou" and t.notes[1].atMs == 9
      check b.commentTask("t1", "  ", nowMs = 10).isErr

    test "a due date is optional and can be cleared":
      var b = newBoard().addTask("a", nowMs = 0, dueMs = 5 * Day).get[0]
      check b.find("t1").get.dueMs == 5 * Day
      b = b.setDue("t1", 0, nowMs = 1).get
      check b.find("t1").get.dueMs == 0

    test "the board has a limit, so a runaway loop cannot fill the disk":
      var b = newBoard()
      for i in 0 ..< MaxTasks:
        b = b.addTask("t" & $i, nowMs = 0).get[0]
      check b.addTask("one more", nowMs = 0).isErr

  suite "task board — views":

    test "filters by state and by assignee":
      var b = newBoard()
      b = b.addTask("a", nowMs = 0).get[0]
      b = b.addTask("b", nowMs = 0).get[0]
      b = b.moveTask("t2", tsDoing, nowMs = 0).get
      b = b.assignTask("t2", "@pesquisa", nowMs = 0).get
      check b.filtered(state = some(tsDoing)).len == 1
      check b.filtered(assignee = "@pesquisa")[0].id == "t2"
      check b.filtered().len == 2

    test "the readable board groups by state and shows what matters":
      var b = newBoard()
      b = b.addTask("revisar contrato", nowMs = 0, dueMs = 2 * Day).get[0]
      b = b.addTask("ligar", nowMs = 0).get[0]
      b = b.moveTask("t2", tsDone, nowMs = 0).get
      b = b.assignTask("t1", "@juridico", nowMs = 0).get
      let md = b.renderMarkdown()
      check "## A fazer" in md and "## Feitas" in md
      check "t1 · revisar contrato" in md
      check "@juridico" in md
      check "1970-01-03" in md
      check md.find("## A fazer") < md.find("## Feitas")

    test "an empty board says so":
      check "Nenhuma tarefa" in newBoard().renderMarkdown()

  suite "task board — reading what the model sends":

    test "a due date is a day, or nothing":
      check parseDueDate("2027-01-20").get == 1_800_403_200_000'i64
      check parseDueDate("").get == 0
      check parseDueDate("20/01/2027").isErr
      check parseDueDate("amanhã").isErr

    test "a state is one of four":
      check parseTaskState("Doing").get == tsDoing
      check parseTaskState("later").isErr

  suite "task board — storage":

    test "the board survives the JSON round trip":
      var b = newBoard()
      b = b.addTask("a", nowMs = 1, dueMs = 3).get[0]
      b = b.commentTask("t1", "nota", nowMs = 2).get
      b = b.assignTask("t1", "@x", nowMs = 2).get
      let back = parseBoard(boardJson(b))
      check back.isOk
      check back.get == b

    test "a damaged file is refused, not guessed":
      check parseBoard("nope").isErr
      check parseBoard("""{"tasks":[{"id":"t1"}]}""").isErr
      check parseBoard("").get.tasks.len == 0   ## no file yet: an empty board

when isMainModule:
  runTests()
