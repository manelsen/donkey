## MemoryAgent — actor responsible for user context I/O.
##
## Inbox messages (amkTask):
##   taskKind="loadCtx"  → loads UserContext, replies with concatenated text
##   taskKind="saveMem"  → appends payload to MEMORY.md, replies with empty result
##   taskKind="savePrefs"→ writes payload to PREFERENCES.md, replies with empty result
##
## Stops on amkCancel.

import chronos
import chronos/asyncsync
import ../domain/agent_message
import ../adapters/memory/md_file
import ../core/types

proc runMemoryAgent*(inbox:  AsyncQueue[AgentMessage];
                     outbox: AsyncQueue[AgentMessage];
                     memory: MdFileAdapter): Future[void] {.async.} =
  while true:
    let msg = await inbox.get()
    case msg.kind

    of amkCancel:
      break

    of amkTask:
      case msg.taskKind

      of tkLoadCtx:
        let userId = UserId(msg.userId)
        let ctx    = memory.loadContext(userId)
        let text   = ctx.userMd & "\n" & ctx.memoryMd & "\n" & ctx.preferencesMd
        await outbox.put(newResultMsg(msg.id, text))

      of tkSaveMem:
        memory.appendMemory(UserId(msg.userId), msg.payload)
        await outbox.put(newResultMsg(msg.id, ""))

      of tkSavePrefs:
        memory.savePreferences(UserId(msg.userId), msg.payload)
        await outbox.put(newResultMsg(msg.id, ""))

      else:
        await outbox.put(newErrorMsg(msg.id, "MemoryAgent: unexpected task: " & $msg.taskKind))

    else:
      discard   ## ignore result/error messages sent to wrong queue
