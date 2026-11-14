# Subagents

Subagents are isolated child sessions used for delegation. The parent keeps its
history and workspace; the child gets only the explicit task, a separate
paddock and a filtered tool set.

## Tools

| Tool | Purpose |
|------|---------|
| `spawn_subagent` | Start a child. `wait=true` (default) returns the structured result; `wait=false` returns a `subagent_id`. |
| `await_subagent` | Collect a background child's structured result. |
| `list_subagents` | List children with status, age, last activity and usage. |
| `cancel_subagent` | Cancel a running child. Idempotent. |

`spawn_subagent` accepts `task`, `context`, an optional `tools` subset, and the
budgets `max_tool_calls`, `max_tokens`, `max_duration_sec`.

## Policy

The pure policy lives in `domain/subagent_pure.nim`:

- **Depth 1.** A child cannot call `spawn_subagent`; nesting fails closed.
- **Read-only default.** `read_file`, `fs_list`, `fs_read`, `text_search`,
  `text_read`, `json_query`, `table_query`, `session_search`, `calc`,
  `current_time`.
- **No escalation.** `bash`, `execute_code`, all write tools, `manage_skills`,
  job/subagent tools and `ask` are denied even if requested.
- **Network reads** (`fetch`, `http_fetch`, `web_fetch`, `web_search`) are
  available only when explicitly requested and present in the parent; they
  inherit the parent URL/network policy.
- **Approval inherited.** The child uses the daemon's `ApprovalService`.
  Requests go to the user with `[subagent <id>]` in the summary. The child has
  no API to approve or deny.
- **Workspace isolation.** The child paddock is
  `{parentPaddock}/subagents/{id}` with `0700`; path guards reject `..` escapes.
- **No parent history.** The child history contains only the delegated task.
  Context must be passed explicitly.

## Budgets

Defaults: 24 tool calls, 32k tokens, 120 seconds. Hard caps: 100 tool calls,
128k tokens, 600 seconds. Token counts use provider usage when available and a
conservative `chars / 4` estimate otherwise. Exceeding a budget fails the
child closed and is reported in `error`.

## Structured result

```json
{
  "subagent_id": "sub-...",
  "status": "completed",
  "text": "...",
  "error": "",
  "tool_calls": 3,
  "input_tokens": 1200,
  "output_tokens": 340,
  "duration_ms": 4200
}
```

`status` is one of `queued`, `running`, `completed`, `failed`, `cancelled` or
`timed_out`. `cost_usd` is included only when pricing is available.

## Lifecycle

- `spawn_subagent` creates the paddock, child state and tool loop.
- Progress/errors go to a drained child outbox; approval prompts use the parent
  outbox.
- Timeout and `cancel_subagent` cancel the loop, close the child tool agent and
  remove the paddock.
- Session shutdown and `amkCancel` cancel all children.
- Start/end are emitted as `session_start`/`session_end` agent events.
