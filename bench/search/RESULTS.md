# Results

## Baseline, 23/11/2026

| Setting | Value |
|---|---|
| Model | DeepSeek V4.1 Flash, the only model so far |
| Seeds | 7, 11 and 23, one run each: 3 samples per question and condition |
| History | about 3,040 messages per seed, in 122 sessions |
| Donkey | `master` at `7ba59acb`: the search from #150 and the wording from #151 |

Nemotron and ERNIE are pending: OpenRouter's free tier had hit its daily cap
(1,000 requests). The run log resumes them.

### Summary

| Condition | n | Searched | **Right** | Doesn't remember | Denied | Wrong |
|---|---|---|---|---|---|---|
| natural | 48 | 27% | **25%** | 62% | 10% | 2% |
| forced (perfect gatekeeper) | 48 | 100% | **69%** | 25% | 4% | 2% |

By seed, "right" ranges over 19–31% in the natural condition and 62–75%
forced.

**Supernova, for reference** (same 16 questions and judge, DeepSeek, one
seed × 3 repetitions):

| Supernova condition | Searched | Right |
|---|---|---|
| natural | 6% | 8% |
| with the Gemini gatekeeper | 100% | 67% |

The two setups are not identical. Donkey keeps 20 recent messages, against
Supernova's 100. The prompts and tool sets differ, and the searches differ.

### Where it fails

**1. Not searching is the biggest loss.** In the natural condition, DeepSeek
searched 17% of the fact questions and got 13% of them right. Forced to
search, it got 67% right. It treats personal data as something outside its
reach. Asked for the wifi password, it answered "I don't have access to your
router; check the sticker". Asked for the complaint number, it answered "I
don't have that registered".

**2. With the search forced, every miss is a paraphrase.** Forced, 21 of 30
fact answers were right. The other 9 all come from three questions, each 0
of 3:

| Question | What Marta said | What the agent searched |
|---|---|---|
| surgery | "operada do quadril" | "cirurgia", "operação", "internada" |
| the exam | "PASSEI NO CONCURSO" | "prova", "notícia boa", "prova aprovada" |
| physiotherapy | "sessões de fisio" | "fisioterapia", once, then gave up |

The physiotherapy miss is the one a search can fix without a model. The
word Marta used is the start of the word the agent searched for. Neither
mode finds it: the phrase is a substring match, and ranked terms match words
that *start with* the term. The hint "try a shorter word" did not make
DeepSeek try again.

The other two are true paraphrases, the case Supernova's `lembrar` solved.

**3. Denials are rare once it searches** (4% forced). In the natural
condition they are 10%, all on questions where it did not search.

### What it suggests

1. **A gatekeeper is worth the most.** With the search forced, "right"
   nearly triples, from 25% to 69%. The forced condition is that ceiling,
   measured without Gemini.
2. **Match on word stems in ranked terms**, so a query word matches stored
   words that share its first characters ("fisioterapia" finds "fisio",
   "operação" finds "operada"). It is cheap and needs no model. It would
   probably fix physiotherapy and might fix surgery. "prova" against
   "concurso" still needs a model.
3. **Measure the MAGMA path.** Its per-message embedding recall is already an
   automatic pre-search, and it may close part of item 1 with no new
   dependency.

The log of every run (calls, outputs, answers, verdicts) is
`out/base.jsonl`, regenerated with the command in the README.

## MAGMA, the default build, 24/11/2026

`--memoria magma`: each seed's graph holds about 1,085 memories, one per
substantive turn, as automatic capture would have stored them: embedded with
`qwen/qwen3-embedding-8b` and stamped with the turn's own time. Before each
question the memory agent recalls 8 memories for it, as it does on every
message. Rerank is off, as it is by default. DeepSeek, seeds 7, 11 and 23,
48 runs per row.

| Memory | Condition | Searched | **Right** | Doesn't remember | Denied |
|---|---|---|---|---|---|
| Markdown only | natural | 27% | **25%** | 62% | 10% |
| Markdown only | forced search | 100% | **69%** | 25% | 4% |
| MAGMA, 30-day decay | natural | 31% | **31%** | 54% | 10% |
| MAGMA, 30-day decay | forced search | 100% | **79%** | 15% | 4% |
| **MAGMA, no decay** | natural | 15% | **67%** | 23% | 8% |
| **MAGMA, no decay** | forced search | 100% | **85%** | 2% | 8% |

Fact questions alone (30 per row):

| Setup | natural | forced |
|---|---|---|
| Markdown only | 13% | 67% |
| MAGMA, 30-day decay | 23% | 87% |
| **MAGMA, no decay** | **83%** | **100%** |

**The decay was the problem.** Recall multiplied every score by a 30-day
half-life, so a four-month-old memory kept about 6% of its score. By plain
cosine similarity the right memory was first (wifi 0.67 and allergy 0.68,
against 0.58 for the filler), but after the decay last week's small talk
filled the recall. MAGMA itself (arXiv:2601.03236) applies no time decay to
relevance: time is a filter and an order for "when" questions. With the
decay removed:
- **Without searching:** recall answers fact questions on its own (83%, with
  the agent searching 3% of them).
- **Paraphrases:** "cirurgia" for "operada" goes from 0 of 3 to 3 of 3 in
  both conditions. Embeddings bridge what words cannot.

**What is left:**
- **Never-said questions** (25% natural, 50% forced). Most misses are graded
  "denied" for answers such as "you always said 'my boss', you never told me
  the name". That is a reasonable answer about something never said, but the
  judge's rubric (Supernova's, unchanged so the runs stay comparable) marks a
  confident "you never told me" as a denial.
- **Allergy, natural, 0 of 3.** Recall's literal-term matching folds case
  but not accents. Marta wrote "mamae é alergica" and the question says
  "alérgica", so the words do not match, while identical copies of a filler
  memory ("levei a mamãe no médico pra renovar receita") take three of the
  eight slots. Accent folding and dropping duplicate contents from recall are
  the next fixes.

## Recall: accents, word starts and one slot per content, 24/11/2026

PRD-recall items 1 and 2, measured together because they interact. MAGMA,
DeepSeek, seeds 7, 11 and 23, 48 runs per row:

| Condition | No decay (#153) | + accents | + accents, word starts | **+ one slot per content** |
|---|---|---|---|---|
| natural | 67% | 65% | 65% | **79%** |
| natural, facts | 83% | 80% | 83% | **93%** |
| forced | 85% | 77% | 81% | **83%** |
| forced, facts | 100% | 90% | 90% | **100%** |

**Accents alone broke something else.** Recall's literal terms matched
substrings, so the folded "mae" (from "mãe") also matched "mamae", which
appears in a third of Marta's messages. That filler pushed the surgery
memory out of the 8: 3 of 3 became 0 of 3, in both conditions.

**Word starts.** A term now matches words that start with it, as in
`session_search`'s ranked mode: "mae" no longer matches "mamae", while
"deploy" still matches "deployments". That was not enough. The surgery
memory sat at the edge of the 8, and two identical copies of "a mamae
acordou animada hoje" took two slots.

**One slot per content** brought it back. Per question, against #153:
- **allergy, natural:** 0/3 → 3/3, the target;
- **"when did I tell you about the cardiologist", natural:** 1/3 → 3/3;
- **surgery:** 3/3, unchanged in both conditions.

The one drop, Lisbon forced (3/3 → 1/3), is judge noise. All three answers
say "searched, found nothing about Lisbon, maybe you told it another way",
and the judge graded the same answer two ways.

## session_search: a long word matches by its first five letters, 24/11/2026

PRD-recall item 4. Ranked terms used to match only stored words that start
with the whole query word, so "fisioterapia" could not find "fisio". A query
word longer than five letters now matches by its first five ("operação" finds
"operada"). Recall's literal terms keep the stricter rule from #154.

Markdown memory, where search is the only way back to the past. DeepSeek,
seeds 7, 11 and 23:

| Condition | Before | After |
|---|---|---|
| forced | 69% | **77%** |
| forced, facts | 67% | **80%** |
| natural (3 repetitions, 144 runs) | 24% | 24% |
| natural, facts (3 repetitions) | 13% | **20%** |

**Per question, forced:**
- physiotherapy: 0/3 → 2/3;
- surgery: 0/3 → 2/3;
- the exam ("concurso"): 0/3 → 1/3.

**The natural row.** The first repetition showed 25% → 19%. Almost every
loss was a run in which DeepSeek did not search this time, which the change
cannot touch; whether it searches varies from run to run. With 2 more
repetitions on both sides the two are level (24% and 24%). Answers right
when it did search went from 27/43 to 29/42. The "before" side's first
repetition predates #154, which barely touches this path.
## Capture check, 24/11/2026

`bancada.py captura` (PRD-recall item 5): which planted fact messages
automatic capture would not keep, per seed.

| Seed | User messages skipped | Of those, with no reply after them | Planted fact messages skipped |
|---|---|---|---|
| 7 | 830 of 1,913 (43%) | 784 | 8 |
| 11 | 827 of 1,909 (43%) | 777 | 8 |
| 23 | 822 of 1,911 (43%) | 782 | 8 |

Almost all the skips come from the data, not from capture's rules: the
generator ends many episodes on a user line, and the next episode opens with
another, so the first line has no reply to pair with. Only about 50 per seed
are skipped as trivial text ("bom dia", "obg"). In real use Donkey replies to
every message, so a real graph would hold about 40% more of the user's
messages than these. The MAGMA results here are, if anything, pessimistic.

**Why.** All 8 are the last user line of a fact's episode, and the generator
ends those episodes without a reply. For example:
- "uns 8 meses. ela mora em Vitória";
- "o ortopedista disse que são uns 3 meses de recuperação com fisioterapia".

Capture needs a reply, so these turns never become memories.

**What it means:**
- **No question is affected.** Every answer key ("quadril", "Marília",
  "concurso"…) sits in an earlier message of its episode, and that one is
  captured.
- **It is an artifact of the data.** In real use Donkey replies to every
  message, so a turn like these would be captured.
- **A real gap remains:** a turn whose reply failed (a provider error) is
  never captured. That is a product question.

The generator is left as it is, so this benchmark stays comparable with
earlier runs and with Supernova's.

## Recall depth on LongMemEval S, 24/11/2026

PRD-recall item 3 (`longmemeval.py`). This is the 60 answerable questions of
Supernova's sample (10 of each type) from LongMemEval S (Wu et al.,
arXiv:2410.10813, MIT), English chat histories of about 115,000 tokens. Each
question's history becomes a MAGMA graph the way automatic capture would fill
it: about 220 memories, embedded with qwen3-embedding-8b and chained in
insertion order. Donkey's recall then ranks the memories for the question.
No LLM is involved.

| Type | n | top 1 | top 8 | top 16 | top 40 | not in 40 |
|---|---|---|---|---|---|---|
| all | 60 | 30 | **52** | 55 | 58 | 2 |
| knowledge-update | 10 | 4 | 10 | 10 | 10 | 0 |
| multi-session | 10 | 4 | 9 | 9 | 9 | 1 |
| single-session-assistant | 10 | 8 | 10 | 10 | 10 | 0 |
| single-session-preference | 10 | 6 | 7 | 9 | 9 | 1 |
| single-session-user | 10 | 6 | 9 | 9 | 10 | 0 |
| temporal-reasoning | 10 | 2 | 7 | 8 | 10 | 0 |

**The limit stays at 8.** Moving from 8 to 16 recovers 3 of 60 questions
(5%), under the PRD's 10% bar.

**Questions recall treats as about time are weaker:**

| Classified as temporal ("first", "ago", "last", "recent"…) | n | Answer in the top 8 |
|---|---|---|
| no | 47 | 45 (96%) |
| yes | 13 | 7 (54%) |

For such a question, recall cuts meaning to 0.30 and literal terms to 0.20,
and adds the most recent memories at 0.40. Part of the gap belongs to the
dataset: "10 days ago" counts from the question's date, in 2023, while
recall's recency list counts from today. A candidate (meaning and terms at
0.50, recency and neighbours at 0.10 each) puts 10 of 13 in the top 8 with
the other 47 unchanged. It is outside PRD-recall and is left for the
maintainer.

**A seeding bug, found and fixed during the run.** The first pass linked
each memory to the one with the latest timestamp, as `appendMemory` does.
LongMemEval's sessions are not in date order, so many memories linked to the
same few, making hubs of up to 142 links. A time question then pulled in
about 140 unrelated "neighbours", and only 47 of 60 answers made the top 8
(2 of 10 temporal-reasoning). In live use time only moves forward and the
links form a chain. The seeding now chains in insertion order, and the 60
graphs were relinked without re-embedding; the Marta graphs were already
chains.

## Who decides recall's policy: words or a decision model, 24/11/2026

Recall classifies a message as "about time" by its words and then gives
recency the largest weight, which mixes "which came first?" with "what did
we talk about yesterday?". `roteador.py` compares six routers on 96 labelled
messages:
- the 60 answerable LongMemEval questions;
- Marta's 16;
- 20 ordinary messages, in Portuguese and English.

There are four routes: `fato` (something said before), `recencia` (a recent
period), `ordem` (when, which came first, time between) and `agora` (not
about the past). The models all get the same instructions and option
descriptions.

| Router | Accuracy | `ordem` | `recencia` | Past caught | False alarms | Latency | $ per 1M messages |
|---|---|---|---|---|---|---|---|
| word list (today) | 59% | 0/6 | 7/8 | 66/66 | n/a, no `agora` route | 0 | 0 |
| word list, split | 65% | 5/6 | 7/8 | 66/66 | n/a | 0 | 0 |
| Perplexity flash (OpenRouter) | 85% | 6/6 | 6/8 | 61/66 | 0/30 | 0.19 s | 2.20 |
| Perplexity `latest` (OpenRouter) | 96% | 6/6 | 7/8 | 64/66 | 0/30 | 0.26 s | 4.40 |
| **Perplexity 1.3 (direct)** | 94% | 6/6 | 6/8 | 64/66 | **0/30** | 0.30 s | **4.14** |
| Gemini Decision 1 | 95% | 6/6 | 8/8 | 63/66 | 0/30 | 0.26 s | 22.70 |

**Recall's top 8 with each router's routes.** `recencia` gets the temporal
policy and every other route the default. These are the cached graphs, with
±3 noise from query embeddings.

| Router | LongMemEval (60) | of them `ordem` | Marta facts (36) |
|---|---|---|---|
| word list (today) | 49 | 2/4 | 33 |
| **word list, split** | 52 | **4/4** | **36** |
| Perplexity flash | 54 | 4/4 | 35 |
| Perplexity `latest` | 53 | 4/4 | 35 |
| Gemini | 53 | 4/4 | 35 |

**What it shows:**
- **For recall, the free split matches the models.** Only the boundary
  between `recencia` and everything else changes recall's policy, and the
  split gets that right for ordering questions.
- **The models' edge is the gatekeeper.** Perplexity 1.3 catches 64 of 66
  questions about the past and fires on none of the 30 ordinary messages.
- **On Marta the gatekeeper is the forced condition.** It fires on all 16
  questions, so its effect is the forced condition already measured on
  current code: 79% → 83% right, and facts 93% → 100%, in the default
  install (MAGMA). Recall now finds most memories without a search, so the
  gatekeeper is worth about 4 points there. With Markdown-only memory,
  where search is the only way back, forcing it went from 24% to 77%.
- **Perplexity against Gemini:** Perplexity 1.3 on its own endpoint matches
  Gemini's accuracy at a fifth of the price, and its paid access does not
  train on the data. It and the OpenRouter `latest` alias differ on 2 of 96
  borderline messages.

## Recall: recency only for questions about a recent period, 24/11/2026

The router comparison's free split, made the rule. Only words about a recent
period ("yesterday", "last", "ago", "today", "recently", "ontem", "último",
"atrás", "passado") give recency its weight. Words about order or dates
("first", "before", "after", "when", "quando", "antes", "primeira",
"cronológica", "anterior") now rank by meaning and words. LongMemEval,
recall's top 8 on the cached graphs: **53 of 60** (today's word list: 49 to
52). The 4 ordering questions are all in. The temporal-reasoning misses left
are "N days ago" questions, which count from a 2023 question date that
recall's recency list cannot know.

## The gatekeeper as a pre-search (Backtrail), 24/11/2026

Condition `prebusca` uses Perplexity Decider 1.3 on its own endpoint. It
classifies the message, and unless the route is "not about the past", it
runs `session_search` with the message (ranked terms) and injects the call
and its result before the model's first turn. This is provider-agnostic: no
forced tool choice. MAGMA (default build), current master, DeepSeek, seeds
7, 11 and 23, 48 runs per row:

| Condition | Searched | Right | Facts | Never said | "When" |
|---|---|---|---|---|---|
| natural | 8% | 75% | 93% | 25% | 67% |
| forced first search (earlier run) | 100% | 83% | 100% | — | — |
| **pre-search with the gatekeeper** | 100% | **92%** | **100%** | **67%** | **100%** |

**What the numbers show:**
- **The gatekeeper fired on all 48 runs.**
- **The pre-search beats forcing the model to search.** The search result
  arrives before the model answers, and its "maybe said in other words,
  say you don't remember" hint keeps it from denying things never said
  (25% → 67%).
- **Run-to-run noise:** natural shows 75% here against 79% the night before.
