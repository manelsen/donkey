## AgentMessage — domain types for the multi-agent actor system.
##
## Agents communicate exclusively via AsyncQueue[AgentMessage].
## No shared mutable state; cancellation is explicit (amkCancel message).

import chronos/asyncsync
import ../core/types

type
  AgentMessageKind* = enum
    amkTask    ## work to perform
    amkResult  ## work completed
    amkPartial ## streaming partial token batch (before final result)
    amkError   ## work failed
    amkCancel  ## shut down this worker

  TaskKind* = enum
    tkNone
    tkUserMsg    ## top-level conversation turn
    tkLoadCtx    ## load user context files
    tkSaveMem    ## append to MEMORY.md
    tkSavePrefs  ## write PREFERENCES.md
    tkInvokeTool ## execute an MCP/Deno tool call
    tkReset      ## clear conversation history for this session

  AgentMessage* = object
    id*:       string              ## correlation id (request ↔ response)
    kind*:     AgentMessageKind
    ## amkTask fields:
    taskKind*: TaskKind
    userId*:   string
    payload*:  string  ## task-specific plain text or JSON
    channel*:  ChannelKind  ## which channel to reply on (amkTask)
    replyTo*:  string       ## channel-specific msg id to quote (amkTask)
    ## amkResult/amkPartial field:
    text*:     string
    ## amkError field:
    error*:    string

  AgentId* = distinct string

# ── AgentId helpers ───────────────────────────────────────────────────────────

func `$`*(id: AgentId):  string = string(id)
func `==`*(a, b: AgentId): bool = string(a) == string(b)
func `!=`*(a, b: AgentId): bool = string(a) != string(b)

# ── Constructors ──────────────────────────────────────────────────────────────

func `$`*(k: TaskKind): string =
  case k
  of tkNone:       "none"
  of tkUserMsg:    "userMsg"
  of tkLoadCtx:    "loadCtx"
  of tkSaveMem:    "saveMem"
  of tkSavePrefs:  "savePrefs"
  of tkInvokeTool: "invokeTool"
  of tkReset:      "reset"

func newTaskMsg*(id: string; taskKind: TaskKind; userId, payload: string;
                 channel = ckTelegram; replyTo = ""): AgentMessage =
  AgentMessage(kind: amkTask, id: id, taskKind: taskKind,
               userId: userId, payload: payload,
               channel: channel, replyTo: replyTo)

func newResultMsg*(id, text: string): AgentMessage =
  AgentMessage(kind: amkResult, id: id, text: text)

func newErrorMsg*(id, error: string): AgentMessage =
  AgentMessage(kind: amkError, id: id, error: error)

func newCancelMsg*(): AgentMessage =
  AgentMessage(kind: amkCancel)
