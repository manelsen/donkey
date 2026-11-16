# Memory System
Current storage model for the SQLite-first runtime.

## Overview

Donkey now runs SQLite-first by default.

The memory system has two cooperating layers:

```text
F1: Markdown paddock files per user
F2: MAGMA graph state, backed by SQLite by default
```

Both matter:

- Markdown remains the user-facing filesystem shape inside each paddock.
- MAGMA is the structured runtime memory used for identity, preferences,
  retrieval, and agent state.

## Default Storage Layout

```text
~/.donkey/
├── paddocks/<user_id>/
│   ├── USER.md
│   ├── MEMORY.md
│   ├── PREFERENCES.md
│   └── NOTES.md
└── state/
    └── magma.sqlite
```

The normal default database path is:

```text
~/.donkey/state/magma.sqlite
```

You can override it with:

```bash
export DONKEY_MAGMA_SQLITE_PATH=/path/to/magma.sqlite
```

## Workspace Memory

Each user still gets a paddock with Markdown documents:

```text
~/.donkey/paddocks/<user_id>/
├── USER.md
├── MEMORY.md
├── PREFERENCES.md
├── NOTES.md
├── attachments/     # inbound channel files
└── sessions/        # JSONL transcripts
```

These documents are useful because they are:

- inspectable by humans
- easy to back up
- convenient for debugging a single user/session

## Structured Memory

The runtime also writes structured state into MAGMA.

In the current default build:

- MAGMA uses SQLite
- SQLite base and `sqlite-vec` are embedded in the binary
- PostgreSQL is optional, not the default

This means the normal install no longer requires:

- external PostgreSQL
- separate `libsqlite3`
- separate `sqlite-vec`

## Identity and Preferences

Identity and preferences are no longer "Markdown only".

The runtime keeps Markdown and MAGMA in sync so that:

- onboarding identity persists across turns
- provider/model preferences survive channel/runtime actions
- partial state in one layer does not silently erase the other

That is why the modern runtime treats Markdown plus MAGMA as one logical memory
system rather than two disconnected stores.

## PostgreSQL-backed MAGMA

PostgreSQL still exists as an optional runtime for larger installs.

Enable it only when you explicitly want the Postgres-backed MAGMA path:

```bash
export DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'
```

If `DONKEY_PG_DSN` is unset, Donkey remains on the SQLite-first path.

## Memory Port Shape

At the storage boundary, the runtime still exposes a memory abstraction that
loads and saves:

- `USER.md`
- `MEMORY.md`
- `PREFERENCES.md`

plus structured graph state behind the scenes.

## Common Operations

Typical runtime operations include:

- loading a user's merged context
- saving onboarding identity
- updating provider/model preferences
- appending durable memories
- retrieving structured state for orchestration and heartbeat

## Automatic Memory Capture

Donkey can automatically save useful conversation turns into structured memory.

Recent hardening in the runtime makes this safer:

- operational failure text is no longer auto-captured as memory
- turns are no longer truncated at tiny limits by default
- identity and preference sync are preserved across SQLite-first flows
- short user messages are captured too, because a short message is often a
  correction; only greetings, bare acknowledgements and slash commands are
  skipped (policy in `domain/memory/capture_pure.nim`)

## Markdown ↔ MAGMA Sync

`MEMORY.md` stays editable by hand. On each context load, paragraphs of
`MEMORY.md` that the graph has never stored are imported once. The comparison
is per line and runs against every memory node of the user, so entries the
agent wrote itself are not imported a second time, however many nodes exist.

Memory nodes are ordered by timestamp and then by insertion order. The
`TEMPORAL` edge of a new memory always points from the memory inserted
immediately before it, including bursts written within the same second.

## Ingesting Documents and Attachments

When a channel sends a file, Donkey stores it under
`{paddock}/attachments/` and adds a relative-path marker to the user turn.
The agent can then read it with `fs_read`/`text_read`; images use
`inspect_image`. Channel file IDs are never sent to providers as image URLs.

For long documents, use the `memory_ingest` tool instead of copying the whole
file into a model response:

- `path` reads a workspace text file (max 2 MB) and appends it in bounded,
  UTF-8-safe chunks.
- `text` ingests an inline note.
- `chunk_chars`/`max_chunks` cap the work.

`memory_ingest` appends to memory; it does not overwrite `USER.md`. To change
the profile, use the normal identity/onboarding flow.

## Best Practices

### 1. Treat SQLite as the default

For a normal install, prefer the embedded SQLite path. Reach for PostgreSQL only
when you have a concrete scale or operational reason.

### 2. Inspect both layers when debugging

If something looks wrong, check:

- the paddock files in `~/.donkey/paddocks/<user_id>/`
- the active MAGMA backend reported by `donkey doctor` or `donkey about`

### 3. Keep paddock ownership clean

Donkey now treats ownership drift in paddocks as a security issue. In
production, startup aborts if paddock files are owned by the wrong user.

## Related

- [Configuration Reference](../reference/configuration.md)
- [Memory Port API](../reference/memory_port.md)
- [Hooks System](hooks.md)
