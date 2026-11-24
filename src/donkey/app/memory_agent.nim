## MemoryAgent — actor responsible for user context I/O.
##
## Inbox messages (amkTask):
##   taskKind="loadCtx"  → loads UserContext, replies with concatenated text
##   taskKind="saveMem"  → appends payload to MEMORY.md, replies with empty result
##   taskKind="savePrefs"→ writes payload to PREFERENCES.md, replies with empty result
##
## Stops on amkCancel.

import std/strutils except strip
import ../core/pipeops
import chronos
import chronos/asyncsync
import ../domain/agent_message
import ../core/pipeops
import ../core/types
import ../ports/memory

func errorText(error: string): string =
  ## An error is an error even when the backend gave it no text.
  if error.len > 0: error else: "not stored"

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
            ## Async: the question's embedding is computed on a worker
            ## thread, so recall does not stall the loop.
            let recalled = renderRecall(await searchFn(userId, msg.payload, 8))
            if recalled.len > 0:
              memSection = recalled
          let parts = @[ctx.userMd, memSection, ctx.preferencesMd]
          let text = parts.join("\n")
          await outbox.put(newResultMsg(msg.id, text))
        except Exception as e:  ## effect boundary: callee raises are unannotated
          await outbox.put(newErrorMsg(msg.id, "MemoryAgent loadCtx: " & e.msg))

      of tkSaveMem:
        ## A memory that was not stored is an error for the caller, never a
        ## silent success. The port does not raise; the Result is the answer.
        let stored = memory.appendMemory(UserId(msg.userId), msg.payload)
        if stored.isErr:
          await outbox.put(newErrorMsg(
            msg.id, "MemoryAgent saveMem: " & errorText(stored.error)))
        else:
          await outbox.put(newResultMsg(msg.id, ""))

      of tkSavePrefs:
        let saved = memory.savePreferences(UserId(msg.userId), msg.payload)
        if saved.isErr:
          await outbox.put(newErrorMsg(
            msg.id, "MemoryAgent savePrefs: " & errorText(saved.error)))
        else:
          await outbox.put(newResultMsg(msg.id, ""))

      else:
        await outbox.put(newErrorMsg(msg.id, "MemoryAgent: unexpected task: " & $msg.taskKind))

    else:
      discard   ## ignore result/error messages sent to wrong queue
