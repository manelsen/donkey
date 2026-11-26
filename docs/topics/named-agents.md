# Named agents

A user can keep several named agents next to their main assistant: a code
reviewer, a researcher, a writer. Each one is a persona with its own role and,
optionally, its own provider and model.

## Calling one

Start a message with `@name`:

```
@revisor olha esse diff antes do merge
```

That turn is the agent's: its role replaces the main assistant's identity in
the system prompt, its notes are added, and its model is tried first (the
user's own routing follows as the fallback, so an agent whose provider fails
still answers; a provider with no credentials configured is skipped). With
`strict_provider = true` the agent's provider is the only route: when it fails
or has no credentials, the turn fails instead of going to another provider,
so the data never reaches a destination the agent was not given. A local
provider (Ollama) is strict unless the file says `strict_provider = false`:
whoever picks one wants the data to stay on the host (audit of 26/11,
finding 2). The message keeps its `@name` in the history, so the main
assistant and the other agents see who was asked what.

`@name` only counts as the first word. An unknown name is an ordinary message.

## What an agent shares

- **Shared:** everything Donkey knows about the user — `USER.md`, `MEMORY.md`,
  the memory graph — and the conversation.
- **Its own:** the role (`description`), the provider/model, and a notes file
  the agent writes for itself (`manage_agents`, action `note`).

## Creating and changing them

From the chat, through the `manage_agents` tool ("create a reviewer that is
strict about tests"), or by editing the files directly:

```
{paddock}/agents/revisor.toml
{paddock}/agents/revisor.notes.md
```

```toml
name = "revisor"
description = "Reviews code strictly: risks before praise, tests before style."
provider = "anthropic"          # optional
model = "claude-sonnet-5-5"     # optional
strict_provider = false         # optional: true = this provider only
```

Names are 1–32 characters of `a-z`, `0-9` and `-`. `manage_agents` supports
`list`, `create`, `update`, `delete` and `note`; a subagent can never use it.

## Agents talking to each other

- **`ask_agent(name, question, context)`** — the current agent (the main
  assistant or a named one) asks another and gets its answer back. The asked
  agent replies once, in its own role, with its notes and model, without tools
  (so no chain of calls); `context` is what it needs to know, since it does not
  see the caller's turn.
- **`convene_agents(agents, question, context, rounds)`** — a deliberation
  room of 2–5 agents. In round 1 each answers on its own (in parallel); in each
  further round (up to 3, default 2) each reads the others' latest answers and
  says where it agrees, where it disagrees and its revised answer. The tool
  returns the transcript and the caller is the lead: it writes the synthesis for
  the user.

In the daemon both use the async completion, which runs the provider call on a
worker, so the loop stays free while the agents think (a context with only a
synchronous completion falls back to calling it inline). Subagents can use
neither, nor `manage_agents`.

## Limits

- An agent with its own provider runs without streaming: streaming is wired to
  the user's default provider only.
- An agent asked through `ask_agent` or a room answers without tools.

## The task board

`manage_tasks` keeps a small board the person and their agents share
(PRD-roadmap E4): tasks `t1`, `t2`, … with a title, a state (`todo`,
`doing`, `blocked`, `done`), an assignee (the person, or `@agent`), an
optional due date (`YYYY-MM-DD`) and notes. It lives in the paddock as
`tasks.json`, with a readable `TASKS.md` written beside it at each change;
editing `TASKS.md` changes nothing. `/tasks` shows the board on any channel.
At most 200 tasks; subagents and consulted agents cannot use the tool.

A task held by an agent with a due date becomes that agent's turn on the
day: a one-time schedule (`task-<id>` among the person's schedules) fires at
noon UTC with a prompt that starts with `@agent`, so the turn answers as
that agent and records its progress on the board. Moving the due date,
reassigning, finishing or deleting the task moves or removes the turn.

