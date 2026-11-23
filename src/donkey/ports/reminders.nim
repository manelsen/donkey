## Reminders: schedule one, list the ones that are due, remove one once it was
## delivered. Kept apart from the memory port, so a memory backend does not
## have to store reminders. `adapters/memory/reminder_store` keeps them as
## files under each paddock.

import ../core/pipeops
import ../core/types
import ../domain/reminder

export reminder

type
  ReminderPort* = object
    schedule*: proc(userId: UserId; channel: string; scheduledAt: int64;
                    message: string): Result[string, string] {.gcsafe, raises: [].}
      ## Stores a reminder and returns its id.
    due*:      proc(now: int64): Result[seq[Reminder], string] {.gcsafe, raises: [].}
      ## Every reminder, of every user, scheduled at or before `now` (Unix
      ## seconds). One that cannot be read is skipped, not an error.
    remove*:   proc(userId: UserId; id: string): Result[void, string] {.gcsafe, raises: [].}
      ## Removing a reminder that is not there is not an error.
