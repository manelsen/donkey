## MemoryAgent — actor responsible for user context I/O.
##
## Inbox messages (amkTask):
##   taskKind="loadCtx"  → loads UserContext, replies with concatenated text
##   taskKind="saveMem"  → appends payload to MEMORY.md, replies with empty result
##   taskKind="savePrefs"→ writes payload to PREFERENCES.md, replies with empty result
##
## Stops on amkCancel.

import std/strutils except strip
import chronos
import chronos/asyncsync
import ../domain/agent_message
import ../core/types
import ../ports/memory

proc runMemoryAgent*(inbox:     AsyncQueue[AgentMessage];
                     outbox:    AsyncQueue[AgentMessage];
                     memory:    MemoryRuntimePort;
                     searchFn:  SearchFn = nil): Future[void] {.async.} =
  ## searchFn: when non-nil, uses semantic search over the user query (payload)
  ## to retrieve relevant memories instead of returning raw MEMORY.md.
  while true:
    let msg = await inbox.get()
    case msg.kind

    of amkCancel:
      break

    of amkTask:
      case msg.taskKind

      of tkLoadCtx:
        try:
          let userId = UserId(msg.userId)
          let ctx    = memory.loadContext(userId)
          var memSection = ctx.memoryMd
          ## Semantic search enrichment: if searchFn and a query are available,
          ## replace the raw memory dump with the hits for this query.
          ## Dialogue hits arrive with their session neighbours and are
          ## rendered as ordered excerpts (domain/memory/recall_pure).
          if searchFn != nil and msg.payload.len > 0:
            let recalled = renderRecall(searchFn(userId, msg.payload, 8))
            if recalled.len > 0:
              memSection = recalled
          let parts = @[ctx.userMd, memSection, ctx.preferencesMd]
          let text = parts.join("\n")
          await outbox.put(newResultMsg(msg.id, text))
        except Exception as e:
          await outbox.put(newErrorMsg(msg.id, "MemoryAgent loadCtx: " & e.msg))

      of tkSaveMem:
        try:
          memory.appendMemory(UserId(msg.userId), msg.payload)
          await outbox.put(newResultMsg(msg.id, ""))
        except Exception as e:
          await outbox.put(newErrorMsg(msg.id, "MemoryAgent saveMem: " & e.msg))

      of tkSavePrefs:
        try:
          memory.savePreferences(UserId(msg.userId), msg.payload)
          await outbox.put(newResultMsg(msg.id, ""))
        except Exception as e:
          await outbox.put(newErrorMsg(msg.id, "MemoryAgent savePrefs: " & e.msg))

      else:
        await outbox.put(newErrorMsg(msg.id, "MemoryAgent: unexpected task: " & $msg.taskKind))

    else:
      discard   ## ignore result/error messages sent to wrong queue
