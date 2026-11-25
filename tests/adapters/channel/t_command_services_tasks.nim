## /tasks reads the board the agent keeps in the person's paddock (E4.3).

import std/[os, strutils, unittest]
import donkey/adapters/channel/command_services
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/memory/md_file
import donkey/app/task_board
import donkey/core/pipeops
import donkey/core/tooling/native_tool_args
import donkey/domain/message

proc runTests*() =
  suite "command services — /tasks":

    test "the board the agent wrote is what /tasks shows":
      let base = getTempDir() / "donkey_cmd_tasks"
      removeDir(base)
      defer: removeDir(base)
      let memory = MdFileAdapter(paddocksDir: base)
      let uid = UserId("u-tasks")
      createDir(memory.paddockDir(uid))
      check taskBoardText(memory, uid).get.contains("Nenhuma tarefa")
      check performManageTasks(newFsAdapter(), memory.paddockDir(uid),
        ManageTasksContext(action: "add", title: "enviar proposta"), 1_000).isOk
      check "t1 · enviar proposta" in taskBoardText(memory, uid).get

    test "a damaged board is an error, not an empty list":
      let base = getTempDir() / "donkey_cmd_tasks_bad"
      removeDir(base)
      defer: removeDir(base)
      let memory = MdFileAdapter(paddocksDir: base)
      let uid = UserId("u-bad")
      createDir(memory.paddockDir(uid))
      writeFile(memory.paddockDir(uid) / "tasks.json", "{nope")
      check taskBoardText(memory, uid).isErr

when isMainModule:
  runTests()
