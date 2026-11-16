# Memory System
Current storage model for the SQLite-first runtime.

## Overview

Donkey now runs SQLite-first by default.

The memory system has one store per mode:

```text
With MAGMA (default): the graph is the source of truth.
                      The Markdown files in the paddock are an export of it.
Without MAGMA (F1):   the Markdown files in the paddock are the store.
```

- MAGMA holds identity, preferences, memories, episodes and commitments.
- The Markdown files stay inspectable by humans and easy to back up, but with
  MAGMA they are written, not read: editing them does not change what the
  agent knows.

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

## Source of Truth

With MAGMA every operation has one path:

- writes go to the graph; `USER.md` and `PREFERENCES.md` are then rewritten
  and `MEMORY.md` gets the new entry appended, as an export;
- reads come from the graph, including profile, agent identity, user listing
  and revocation.

The Markdown files are read in two cases only:

1. the graph holds nothing of the user yet: a paddock that predates the graph
   is imported once, and its memories are tagged `markdown`;
2. the graph cannot be read: the last export is returned instead of nothing.

To bring edited files into the graph on purpose, use
`donkey ctl memory import <uuid>`. It replaces what the graph holds for that
user with the content of the files. `donkey ctl memory export <uuid> [dir]`
writes the graph view as Markdown.

If the graph does not take a memory, nothing is exported and the error is
returned to the caller: auto-capture logs it and `memory_ingest` reports it.

## PostgreSQL-backed MAGMA

PostgreSQL still exists as an optional runtime for larger installs.

Enable it only when you explicitly want the Postgres-backed MAGMA path:

```bash
export DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'
```

If `DONKEY_PG_DSN` is unset, Donkey remains on the SQLite-first path.

## Memory Port Shape

At the storage boundary, the runtime exposes one memory abstraction that
loads and saves the user profile, the memories and the preferences. Whether
they live in the graph or in the Markdown files is decided inside the adapter.

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
- short user messages are captured too, because a short message is often a
  correction; only greetings, bare acknowledgements and slash commands are
  skipped (policy in `domain/memory/capture_pure.nim`)

## What Is Stored, and What Is Not

A memory is stored as it was said. The only structure kept between memories
is their order: each new memory gets a `TEMPORAL` edge from the one inserted
immediately before it, including bursts written within the same second.

Three things earlier versions did are gone:

- **Lessons.** No rule is distilled from an episode or from a commitment
  outcome. In our own experiments, lessons distilled from episodes lost to the
  raw episodes, including where a learnable rule existed.
- **Entity graph.** No entity nodes or `MENTIONS`/`ABOUT` edges. They were
  extracted with English sentence patterns.
- **Causal graph.** No `CAUSAL` edges. They were inferred from English
  markers.

Nodes of those kinds written by earlier versions stay in the database and are
no longer read.

## Recall

Each turn, the memories for the user's message are ranked by two lists fused
by reciprocal rank, at equal weight:

- **meaning**: nearest embeddings;
- **literal terms**: the words of the message, the same matching used by
  `session_search`. Names, error messages and file names are found here.

A message that asks about time (`when`, `last`, `yesterday`, ...) also ranks
by recency and pulls in the memories next to its hits. Relevance then decays
with a 30-day half-life. Without an embedding provider the literal terms
still rank.

## Memory Origin

Each memory node records where it came from, in its `meta`:

| `source` | Written by |
|---|---|
| `turn` | automatic capture of one user/assistant exchange, with `session_id` |
| `ingest` | a chunk appended by `memory_ingest` |
| `consolidation` | facts extracted at `/compact`, `/reset` or `/new` |
| `markdown` | a paragraph imported from `MEMORY.md` |

Nodes written before origins existed have empty `meta` and read as unknown.

## Dialogue Recall

When a search hit is a `turn`, it is delivered together with the previous and
the next turn of the same session, oldest first, inside explicit borders:

```text
<conversation-excerpt session="…" from="2026-11-16 18:44 UTC" entries="3">
[context]
- **User:** …
  **Response:** …
[match]
- **User:** …
  **Response:** …
[context]
- **User:** …
  **Response:** …
</conversation-excerpt>
```

- Only the three best-ranked dialogue hits are expanded.
- Neighbours are found on the `TEMPORAL` chain; nodes of another origin or
  session are skipped.
- A context entry longer than 2000 characters is clipped and ends in
  `[…truncated]`. The matched entry is never clipped.
- Excerpts that share an entry are merged, and no entry appears twice.
- Hits of any other origin, and legacy nodes, are delivered alone.

The policy and the rendering live in `domain/memory/recall_pure.nim`.

## Session Transcripts

`sessions/<id>.jsonl` is append-only: one message per line, each with the
time it was first stored (`ts`, milliseconds) and its number in the session
(`seq`). The live history is trimmed, compacted and rewound, but the
transcript keeps every message that was said: a message is appended when its
number is not in the file yet. Compaction summaries have no number and are
never written. `session_search` reads the most recent 512 KiB of each
transcript, newest lines first.

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

### 2. Debug against the graph

If something looks wrong, check the active MAGMA backend reported by
`donkey doctor` or `donkey about`, and export the graph view with
`donkey ctl memory export <uuid>`. The paddock files in
`~/.donkey/paddocks/<user_id>/` show the last export, not the live state.

### 3. Keep paddock ownership clean

Donkey now treats ownership drift in paddocks as a security issue. In
production, startup aborts if paddock files are owned by the wrong user.

## Related

- [Configuration Reference](../reference/configuration.md)
- [Memory Port API](../reference/memory_port.md)
- [Hooks System](hooks.md)
