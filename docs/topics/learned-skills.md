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
