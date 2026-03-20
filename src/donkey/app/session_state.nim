## session_state.nim — mutable per-session state for native tools.
## Ref object: lives in the orchestrator, passed to executeNativeTool.

import std/tables
import chronos
import ../domain/message

type
  TodoPhase* = enum
    phBacklog     = "backlog"
    phInProgress  = "in_progress"
    phCompleted   = "completed"

  TodoItem* = object
    id*:    string
    title*: string
    phase*: TodoPhase
    notes*: string

  JobState* = object
    future*: Future[string]   ## nil when already resolved
    done*:   bool
    result*: string

  SessionState* = ref object
    todos*:       seq[TodoItem]
    checkpoints*: seq[ConversationHistory]   ## history snapshots
    jobs*:        Table[string, JobState]
    jobCounter*:  int

proc newSessionState*(): SessionState =
  SessionState(
    todos:       @[],
    checkpoints: @[],
    jobs:        initTable[string, JobState](),
    jobCounter:  0,
  )
