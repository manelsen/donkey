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
