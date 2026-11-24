# Conversation-search benchmark

Measures how Donkey answers questions about the conversation's past: does the
agent search, does the search find it, and does the answer get it right (or
deny something that was said)? Nothing here is part of the build.

It is a port of Supernova's benchmark (`supernova/dev/bancada`, same author),
so the two projects can be compared on the same ground. The synthetic
history, questions and judge are the same. Everything that is Donkey's comes
from Donkey itself.

| File | What it is |
|---|---|
| `dados.py` | A synthetic history: Marta talking with her agent over about 4 months. It covers good, bad and neutral days. 35% of her messages have no accents, 10% have typos, and she uses slang ("vc", "fds", "kkk"). 14 facts are planted: one is corrected later, one is misspelled, and several are said one way and asked another ("operada", later asked about the "cirurgia"). There are 16 questions, 4 of them about things never said, plus traps: the neighbour's dog appears 31 times, and the boss's name never does. All invented. |
| `donkey_bench.nim` | `prompt` prints the system prompt and the 48 native tools a Donkey turn sends, built by the orchestrator's own functions. `serve` runs the real `session_search` through `executeNativeTool`. |
| `bancada.py` | Runs the agent loop and the judge, and writes the log. |

## Seeds

Each seed generates a different history: the filler conversations, typos,
timestamps, and the position of each planted fact (±2%). The facts and
questions stay the same, so seeds are comparable. A seed is written as a
Donkey paddock:
- one `sessions/<id>.jsonl` per local day, about 122 sessions;
- USER.md, plus a MEMORY.md with two profile notes.

The same seed always gives the same history.

## What the agent sees

| Setting | Donkey | Supernova |
|---|---|---|
| Recent messages in context | 20 (`trimTo(20)`) | 100 |
| Native tools offered | all 48; only `session_search` runs, the rest answer "Unavailable in this conversation." | its 11 real tools |
| Tool calls per question | up to 5 | up to 5 |

## Conditions

- **`natural`**: the prompt as Donkey sends it. The agent decides whether to
  search.
- **`forcada`**: the first call must be `session_search`. This is the upper
  bound of a perfect gatekeeper, measured without Gemini: every question is
  about the past, so a perfect gatekeeper would always fire.

## Judge

DeepSeek grades each answer against the answer key, using Supernova's
categories:

| Category | Meaning |
|---|---|
| `acertou` | right |
| `nao_lembra` | says it doesn't remember |
| `negou` | denies with certainty that it was said |
| `errou` | wrong content |
| `inventou` | made up |

Not searching counts against the agent only through the answer it gives.

`negou*` applies Supernova's later rule: on a never-said question, a denial
in a doubting tone ("acho que você nunca me disse") is the approved tone,
not a denial. It is reported next to `negou`, never in place of it.

## Keys

`OPENROUTER_API_KEY` and `SUPERNOVA_PROVIDER_MISTRAL_API_KEY` (DeepSeek V4.1
Flash is served by Mistral). They are read from `bench/search/.env.bench`
(gitignored) or from Supernova's files, and never printed.

## Running

```sh
python3 -I bench/search/bancada.py rodar --modelos deepseek,nemotron,ernie \
    --sementes 7,11,23 --saida bench/search/out/base.jsonl
python3 -I bench/search/bancada.py resumo bench/search/out/base.jsonl
```

The `--saida` file is the run log, one line per attempt, with:
- seed, model, condition and question;
- every tool call, with its arguments and its output (up to 2000 characters);
- the answer;
- the judge's verdict and reason.

An interrupted run resumes where it stopped. A task that failed (for
example on a rate limit) is tried again, and the summary counts its last
line. Results are in `RESULTS.md`.

## Limits

- **One synthetic history family and 16 questions.** It shows behaviours,
  not production rates.
- **The judge is an LLM**, and it sometimes errs.
- **Two memory setups** (`--memoria`):
  - **`md`:** MEMORY.md with only two profile notes, as in Supernova's
    benchmark.
  - **`magma`:** the default build (SQLite). The graph holds one memory per
    substantive turn, as automatic capture would have stored them, embedded
    through OpenRouter and stamped with the turn's time. Each question gets
    the memory agent's recall of 8 memories. A seed's graph is built once
    (about 30 minutes, embedding is the slow part) and reused.
