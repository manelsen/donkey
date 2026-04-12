## session_state.nim — mutable per-session state for native tools.
## Ref object: lives in the orchestrator, passed to executeNativeTool.

import std/tables
import chronos
import ../domain/message

## Job system (issue #8 — documented):
## `jobs`, `jobCounter`, `TaskToolName`, `SubmitResultToolName`, `CancelJobToolName`,
## `AwaitToolName` are NOT dead code. They implement parallel job execution:
##   - `task`    — spawns an async background job, returns job_id
##   - `await`   — polls job futures until all complete (with timeout)
##   - `cancel_job` — cancels a running job
##   - `submit_result` — sets the result string for a completed job
## These are registered as native tools in session_bootstrap.nim and dispatched
## in native_tools.nim's executeNativeTool. The orchestrator passes SessionState
## to executeNativeTool, which populates state.jobs when `task` is called.

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
    todos*:           seq[TodoItem]
    checkpoints*:     seq[ConversationHistory]   ## history snapshots
    jobs*:            Table[string, JobState]
    jobCounter*:       int
    lastHeartbeatAtMs*: int64                    ## monotonic ms of last heartbeat turn

proc newSessionState*(): SessionState =
  SessionState(
    todos:            @[],
    checkpoints:      @[],
    jobs:             initTable[string, JobState](),
    jobCounter:       0,
    lastHeartbeatAtMs: 0,
  )
