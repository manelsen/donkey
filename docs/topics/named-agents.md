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
still answers; a provider with no credentials configured is skipped). The message keeps its `@name` in the history, so the main
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
