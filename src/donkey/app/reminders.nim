## Reminder delivery: the due reminders go to the outbox, then out of the
## store. The daemon runs it on its tick.

import std/strutils
import ../core/pipeops
import ../core/log
import ../core/types
import ../domain/message
import ../ports/reminders
import ./metrics

export reminders

type
  ReminderOutboxFn* = proc(reminder: Reminder): Result[void, string] {.gcsafe, raises: [].}
    ## Hands the reminder to the channel that will send it.

func reminderMessage*(reminder: Reminder): OutboundMessage =
  ## What the user receives. A channel name this build does not know falls
  ## back to Telegram, the default channel.
  OutboundMessage(
    userId:  reminder.userId,
    channel: parseEnum[ChannelKind](reminder.channel, ckTelegram),
    text:    "⏰ " & reminder.message,
  )

proc deliverDueReminders*(port: ReminderPort; now: int64; outbox: ReminderOutboxFn;
                          log: Logger = newLogger("reminders")): int
                         {.gcsafe, raises: [].} =
  ## Delivers what is due at `now` (Unix seconds) and returns how many went
  ## out. A reminder the outbox refused stays in the store, to be tried on the
  ## next pass; one that went out but could not be removed is logged, since
  ## it will go out again.
  if port.due == nil:
    return 0
  let due = port.due(now).valueOr:
    log.error("reminders: " & error)
    return 0
  for reminder in due:
    let sent = outbox(reminder)
    if sent.isErr:
      log.error("reminder delivery failed for user=" & $reminder.userId &
                " channel=" & reminder.channel & " reason=" & sent.error)
      recordReminderFailure(sent.error)
      continue
    inc result
    if port.remove != nil:
      port.remove(reminder.userId, reminder.id).isOkOr:
        log.warn("reminder " & reminder.id & " was delivered but not removed: " & error)
