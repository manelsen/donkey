# Scheduled jobs

A scheduled job is a prompt the agent runs on a clock. At each run the prompt
reaches the user's session as a task, the agent answers it with its tools, and
the answer goes to the user in the job's channel.

## Who makes them

- **The user, from chat**, via the `manage_schedules` tool ("every weekday at 9
  send me the news"). The job is the user's, in the channel it was made in,
  stored as `<userId>:<name>`. A user sees and changes only their own jobs.
  Limits: at most 20 per user and no more often than every 5 minutes, because
  each run is a full agent turn.
- **The operator**, via `donkey ctl schedule add <id> --cron <expr> --user <id>
  --payload <text>`, with any id and no spacing limit.

Both live in `{home}/state/schedules.json` and show in `ctl schedule list` and
the TUI. With `DONKEY_SCHEDULES_ENABLED=0` nothing fires and the tool refuses
new jobs.

## Expressions

| Form | Example | Meaning |
|---|---|---|
| 5-field cron | `0 9 * * 1-5` | minute hour day month weekday, on the job's `UTC±HH:MM` clock |
| alias | `@hourly`, `@daily`, `@weekly`, `@monthly`, `@yearly` | the cron it names |
| interval | `@every 30m`, `@every 1h30m`, `@every 1d` | one period after creation, then every period; ignores the timezone |

## Downtime

`catch_up = skip` (default): an occurrence missed by more than two minutes is
not run. `once`: after downtime, the most recent missed occurrence runs once,
looking back at most `DONKEY_SCHEDULE_CATCHUP_MAX_H` hours. A backlog is never
replayed. Pausing and resuming does not replay the paused time.

Every occurrence that does not run is counted: the stale ones `skip` drops and
the backlog `once` collapses into one run (paused time is not a miss). The
store keeps the total and when the last miss was noticed; `ctl schedule
list/show` (`missed`, `last_missed`), the TUI and the user's
`manage_schedules list` show them. Counting stops at 1000 per tick.
