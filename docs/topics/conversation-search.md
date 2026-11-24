# Conversation search

`session_search` searches the user's whole conversation history: every past
session and what compaction removed from the current one. Transcripts are
read as they are (`{paddock}/sessions/<id>.jsonl`, append-only), newest
first. There is no index to build or keep in step.

That follows "Forget Freely, Grep Later" (Yang, Shi and Zhao,
arXiv:2611.25123). A lossless raw log searched with exact patterns matched or
beat structured memory, and was far ahead on exact recall: values, names,
IDs, log lines, the details a summary drops. The tool output follows the
paper's design. Each match has a header naming its session, time and message
number, plus neighbouring messages. Output is paginated and capped, long
lines are clipped around the match, and a count comes first. For the case
the paper names as grep's limit, when there is no exact string to look for,
ranked terms (BM25) are there too.

| Mode | Arguments | Returns |
|---|---|---|
| exact phrase | `phrase`, `context` (0-3, default 1), `limit` (10, max 30), `offset`, `order` | every message holding the phrase, newest first, `:` marks the match and `-` a neighbour |
| count | `phrase`, `count: true` | matches per session, without the messages |
| ranked | `query`, `limit` (8, max 20), `include_memory` | the best message of each matching conversation (BM25, k1 1.2, b 0.75; a term matches words that start with it), plus MEMORY.md hits |
| read | `session_id`, `around` (default: the last message), `context` (radius, default 5, max 20) | the messages around a hit, each clipped to 2000 characters |

`since`/`until` take `7d`, `24h`, `2w` or `YYYY-MM-DD` (UTC). Case and Latin
accents are ignored ("reuniao" finds "Reunião"). Earlier `session_search`
results stored in a transcript are skipped.

**Budget.** A search reads at most 256 MiB and runs at most 4 s, yielding to
the event loop after each file. When it stops early, the answer says how many
of the sessions it covered and suggests narrowing with `since`/`until`, so a
partial "no match" is never presented as complete. On a 100 MB synthetic
history (200 sessions), release build: an exact phrase takes about 0.6 s; a
ranked query whose terms occur in nearly every line (the worst case) takes
about 2 s.

## Backtrail (opt-in)

Backtrail checks the trail already walked. With `PERPLEXITY_API_KEY` set
(store it with `donkey ctl secret set PERPLEXITY_API_KEY`), each message a
person sends is first classified by
Perplexity Decider 1.3: something said before, a recent period, order or
dates, or not about the past. For the first three, Donkey runs
`session_search` with the message before the model's turn and gives the
model the result as a search it already made. The model cannot forget to
look, and the result carries the "not found is not never said" hint.

On Marta's benchmark, in the default install (MAGMA), right answers went
from 75% to 92%:
- facts: from 93% to 100%;
- questions about things never said: from 25% to 67%;
- "when" questions: from 67% to 100%.

The router comparison measured Perplexity at 94% routing accuracy, with no
false alarm on 30 ordinary messages (`bench/search/RESULTS.md`).

| | |
|---|---|
| What leaves the server | each incoming message, alone (not the history), to `api.perplexity.ai` |
| Data | Perplexity's own paid endpoint, not used for training |
| Cost | about $4 per million messages |
| Latency | about 0.3 s per message |
| If it fails | a slow (2 s deadline, no retry) or failed classification means no pre-search for that message; the turn goes on as without Backtrail. The call blocks the event loop while it runs, as recall's embedding does |
| Off | `DONKEY_BACKTRAIL=off`, or no key |

Only the person's own messages are classified; scheduled jobs and heartbeats
are not.
