# Learned skills

The agent remembers facts in its memory (MAGMA). Learned skills are the other
half: procedures it writes down so it does a task right the next time, the
way Hermes does (agentskills.io's SKILL.md format).

## Per person

Each person's skills live in their own paddock,
`{paddock}/learned_skills/<name>/SKILL.md`: nothing learned while helping one
person reaches another. Where each skill came from (who wrote it, when, from
what) is kept in `.provenance.json` beside them.

## The format

```markdown
---
name: deploy-staging
description: How to deploy the API to staging and check it came up.
---

1. Run the build.
2. Push the image.
3. Check /health.
```

The name is 1–64 of `a-z`, `0-9` and `-`; the description (when the skill
applies) up to 1024 characters; the whole file up to 32 KB.

## The guard

A skill becomes a standing instruction, so every new or changed skill is
scanned before it is written, and blocked (with the reason) when it reads
like exfiltration of secrets, prompt injection (ignore the instructions, take
over the role, hide something from the person, reveal the system prompt,
behave differently when unobserved), hidden or direction-changing
characters, or a destructive command. Categories and patterns derive from
hermes-agent (MIT).

## Tools

- `skill_manage` — `create` (the whole SKILL.md), `edit`, `patch` (replace
  one passage), `archive` (moved to `.archive/`, never deleted), `restore`,
  `list`. Subagents cannot use it.
- `skill_view` — load a skill to follow it.

Every turn the system prompt lists the person's skills (name and
description, at most 40), so the model knows which one to load; a skill
written during a conversation is listed from the next turn.

## Usage

Each time `skill_view` loads a skill, the load is counted, with when it
happened (`.usage.json` beside the skills); the curator and the journey read
these counts.

## The background review

After every 10 of a person's turns, or 15 tool calls, whichever comes first,
a copy of the agent reads the end of the conversation and keeps what deserves
a skill: a task that took several steps, a correction the person made, a
workflow they taught. It sees the person's existing skills, so it patches one
instead of writing a near-duplicate, and it may only use `skill_view` and
`skill_manage` (at most 4 rounds, within 3 minutes), every write through the
guard and recorded as the review's. It runs after the turn: the answer never
waits for it, and the conversation is not touched. What it kept goes to the
log.

```sh
DONKEY_REVIEW=off                      # on by default
DONKEY_REVIEW_EVERY_TURNS=10
DONKEY_REVIEW_EVERY_TOOL_CALLS=15
DONKEY_REVIEW_PROVIDER=openrouter      # a cheaper route for reviews;
DONKEY_REVIEW_MODEL=<model>            # without them, the session's route
```

Facts are not the review's job: the memory (MAGMA) already keeps each turn
that matters.

## /learn and /refine

- `/learn <source>` — the agent turns the source (a path, a URL, pasted notes)
  into a skill, gathering it with its own tools; `/learn` alone means what you
  just did together. If a skill already covers it, the agent patches that one.
- `/refine` — the review, now and in the conversation: the agent looks back
  and keeps what deserves a skill, and tells you what it saved.

Both are ordinary turns with a prompt of their own (as in Hermes), so they use
the session's route and you see what happens.

## The curator

At most every 7 days, riding on a background review (same auxiliary route,
still off the turn), a pass looks after each person's skills:

1. The skills are backed up into `{paddock}/.curator_backups/<ms>/` (the five
   newest backups are kept).
2. Skills neither loaded nor created in the last 90 days are archived — never
   one the person wrote themselves, and never deleted.
3. A copy of the agent sees every skill in full and merges near-duplicates
   (folds one into the other with `skill_manage edit`, archives the emptied
   one), recorded as the curator's.

```sh
DONKEY_CURATOR=off                      # on by default
DONKEY_CURATOR_INTERVAL_DAYS=7
DONKEY_CURATOR_STALE_DAYS=90
donkey ctl skill rollback <uuid>        # the skills as the newest backup had them
```

A rollback backs up the skills it replaces first, so it can be undone too.

## The journey

What the agent learned for a person, who wrote each skill (the agent, the
review, the curator, the person), when, how often it was loaded, and where it
came from:

```sh
donkey ctl skill learned <uuid>                  # the journey
donkey ctl skill learned <uuid> show <name>      # one skill in full
donkey ctl skill learned <uuid> archive <name>   # or restore <name>
```

The TUI shows the same journey in a person's detail view (Admin → Users →
Enter). The person can ask the agent too (`skill_manage list`).

## Sharing a skill with everyone

Skills are per person. The operator can share one person's skill with every
person:

```sh
donkey ctl skill promote <uuid> <name>
```

It is copied (through the guard again) into the instance's store,
`{home}/learned_skills/`, recorded as the operator's. Everyone then sees it in
their index and can load it with `skill_view`; nobody's agent can change it
with `skill_manage`, and a person's own skill of the same name wins.

## /insights

`/insights [days]` asks the agent for the person's own usage report (the
`insights` tool): their turns, tokens, tools and failures, providers,
channels, and the learned skills they loaded most, over the last 30 days by
default. It reads the traces (`DONKEY_TRACES=on`) and only that person's turns.
