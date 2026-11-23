## SchedulePort — the persisted schedules, as the application layer sees them.
##
## The scheduler tick reads the store through `ScheduleStorePort`
## (`app/automation_runtime`); this port is the other side: what a user's
## `manage_schedules` tool may list, add, pause and remove. The store adapter
## (`adapters/state/schedule_store`) builds it. A field left `nil` means the
## server runs no scheduler, and the tool says so.

import ../core/pipeops
import ../domain/automation/schedule_pure
import ../domain/automation/schedule_view

export schedule_pure, schedule_view

type
  SchedulePort* = object
    all*:        proc(): Result[seq[ScheduleViewRecord], string] {.gcsafe, raises: [].}
      ## Every stored schedule, of every owner.
    insert*:     proc(spec: ScheduleSpec): Result[bool, string] {.gcsafe, raises: [].}
      ## Stores a new schedule whose window starts at its creation (creation
      ## never fires); `false` when the id is taken.
    remove*:     proc(id: string): Result[void, string] {.gcsafe, raises: [].}
    setEnabled*: proc(id: string; enabled: bool; nowMs: int64): Result[bool, string] {.gcsafe, raises: [].}
      ## Pauses or resumes; resuming does not replay the paused time.
      ## `false` when there is no such id.

func schedulesAvailable*(port: SchedulePort): bool =
  port.all != nil and port.insert != nil and port.remove != nil and
    port.setEnabled != nil
