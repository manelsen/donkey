# Hermes mining — transferring API diagnostics into Donkey

This directory holds the reproducible output of mining the public fix history of
[hermes-agent](https://github.com/nousresearch/hermes-agent) for behavior of
external APIs that Donkey talks to. The Telegram pilot lives in
[`telegram/`](telegram/).

## The rule: transfer the diagnosis, not the solution

The hermes history is valuable because it records what the external API
actually does — the errors, the limits, the ordering quirks. It is **not** a
source of code to copy.

- **Transferable:** "Telegram counts message length in UTF-16 code units, so a
  byte-based split corrupts multi-byte characters."
- **Not transferable:** "hermes splits with `text[i:i+n]` and catches
  `BadRequest` in `_send_telegram`."

Each case in `CASES.md` states the API behavior, the trigger and what a correct
client must do. The Donkey implementation is written from that description, in
Donkey style (`func`, `Result`, pipeops), with its own tests. Because the
behavior — not the code — is what travels, the derived work stays independent
and the MIT attribution in `THIRD_PARTY_NOTICES.md` is enough.

## Reproducible extraction

```bash
# full run over the reference commit
bash scripts/hermes_mine.sh telegram
bash scripts/hermes_mine.sh discord

# incremental run: everything that landed after the last sync
bash scripts/hermes_mine.sh telegram --since "$(cat docs/hermes-mining/telegram/LAST_SYNC)"
```

O componente `discord` cobre o adapter atual em `plugins/platforms/discord` e o
anterior em `gateway/platforms/discord.py`, unidos aos commits cujo assunto
começa com `fix` e menciona Discord. Como não havia rodada anterior, a primeira
extração foi feita na `HEAD` do hermes e o `LAST_SYNC` registra essa ref.

Environment:

| Variable | Default | Meaning |
|---|---|---|
| `HERMES_DIR` | `/home/micelio/git/hermes-agent` | read-only checkout of hermes |
| `HERMES_REF` | `b3746e35dd` | commit the extraction is pinned to |

The script only reads from `$HERMES_DIR` (`git log`, `git show`, `git
cat-file`). It never checks out, fetches or writes there.

Outputs, both deterministic:

- `<component>/commits.tsv` — `hash`, `date`, `subject`, `files_changed`,
  `test_files`, sorted by date then hash.
- `<component>/LAST_SYNC` — the `HERMES_REF` used for that component.

Cada componente guarda o próprio `LAST_SYNC`: o do Telegram é `b3746e35dd`,
o do Discord é `b076b5856c`. A ref de um não reescreve a do outro.

For an incremental round, point `HERMES_REF` at the new hermes `HEAD`, run with
`--since`, classify the new rows, and extend `CASES.md`. `LAST_SYNC` then holds
the new ref.

## Adding another component

`scripts/hermes_mine.sh` has one `case` branch per component. A new component
needs:

1. a branch that unions the grep patterns and the paths that scope its fixes;
2. an output directory under `docs/hermes-mining/<component>/`;
3. the same classification, case and traceability files.

Unknown components exit with code 2 and list what is supported.

## Categories

| category | meaning | transfer |
|---|---|---|
| `RATE` | flood control, 429, `retry_after`, send windows | yes |
| `FORMAT` | HTML/MarkdownV2, entities, escaping, 4096 limit, splitting, code | yes |
| `MEDIA` | photos, documents, albums, voice, captions, size limits, `file_id` | yes |
| `EDIT` | message edit/delete, streaming by edit, "message is not modified" | yes |
| `INBOUND` | update parsing, `callback_query`, arrival order, duplicates, groups, mentions | yes |
| `NET` | polling, webhook, timeouts, retry on transient failure, DNS/IP | yes |
| `TOPIC_API` | forum topic API behavior and `message_thread_id` | yes |
| `INTERNAL` | hermes-only features, refactors, logs, names, hermes tests | no |
| `UNCLEAR` | cannot be decided even after reading the diff | no |

## Priorities

| priority | rule |
|---|---|
| `P0` | absent or partial in Donkey **and** loses or corrupts a user message, blocks sending, or gets the bot rate-limited or banned |
| `P1` | absent or partial and degrades the experience (wrong formatting, delay, visible duplicate) |
| `P2` | everything else, including cases already covered |

## Attribution

`THIRD_PARTY_NOTICES.md` carries the full MIT text and the reference commit.
Every derived function starts its doc comment with the hermes fix hash and the
case anchor, and `TRACEABILITY.md` maps case → hermes commits → Donkey test →
Donkey implementation.

## Checklist of one incremental round

1. `git -C "$HERMES_DIR" fetch` (read-only; never a checkout).
2. `HERMES_REF=<new head> bash scripts/hermes_mine.sh telegram --since "$(cat docs/hermes-mining/telegram/LAST_SYNC)"`.
3. Classify the new rows and append them to `classification.tsv`.
4. Fold new behaviors into `CASES.md` (one case per behavior, not per commit).
5. Port the new P0 cases with TDD and update `TRACEABILITY.md`.
6. Run the quality gates and record the round in `telegram/REPORT.md`.
