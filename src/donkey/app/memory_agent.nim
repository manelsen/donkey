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
          var lessonSection = ""
          ## Semantic search enrichment: if searchFn and a query are available,
          ## refine autobiographical memory hits and inject bounded lessons.
          if searchFn != nil and msg.payload.len > 0:
            let hits = searchFn(userId, msg.payload, 8)
            if hits.len > 0:
              var memoryLines: seq[string]
              var lessonLines: seq[string]
              for h in hits:
                if h.kind == "lesson":
                  if lessonLines.len < 3:
                    lessonLines.add("- " & h.content)
                else:
                  memoryLines.add("- [" & h.kind & "] " & h.content)
              if memoryLines.len > 0:
                memSection = memoryLines.join("\n")
              if lessonLines.len > 0:
                lessonSection = "Relevant lessons:\n" & lessonLines.join("\n")
          var parts = @[ctx.userMd, memSection]
          if lessonSection.len > 0:
            parts.add(lessonSection)
          parts.add(ctx.preferencesMd)
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
