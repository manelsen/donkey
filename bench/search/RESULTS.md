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

| Seed | User messages skipped | Planted fact messages skipped |
|---|---|---|
| 7, 11, 23 | about 100 of 1,910 (5%) | 8 in each seed |

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
