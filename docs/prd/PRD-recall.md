# PRD-recall: Donkey remembers what was said

Overnight, autonomous. Each item is its own PR, measured by the
conversation-search benchmark (`bench/search`). Status: draft, 24/11/2026.

## Where we are

DeepSeek, seeds 7, 11 and 23, 48 runs per row (`bench/search/RESULTS.md`).
This is the default build (MAGMA on SQLite) with the decay removed (#153):

| Condition | Right | Fact questions |
|---|---|---|
| natural (recall of 8 per message, the agent decides whether to search) | 67% | 83% |
| forced search | 85% | 100% |

**Known gaps:**
- **Accents:** recall's literal-term match folds case but not accents
  ("alérgica" does not match "alergica"). The allergy question scores 0 of 3
  in the natural condition.
- **Duplicates:** identical memories take several of the 8 slots.
- **Prefixes:** in `session_search`, "fisioterapia" does not find "fisio".
- **The judge:** it grades "you never told me the name" about a name never
  said as a denial.
- **Recall depth:** 8 memories may be too few on realistic data. On
  LongMemEval S, Supernova found the right chunk first by embedding in only
  37 of 59 questions, and as low as 24th (PRD-M, `BUSCA-bancada.md`).

## Goal

Raise right answers in the natural condition (no help, the default install)
with no new dependency, and measure recall depth on an external corpus
before any decision about a model-based search.

## Items, in order

Each item is one PR.
- **TDD:** the test is red before the code goes in.
- **Before each push:** full suite, build and boundary checks green.
- **Merging:** only with `wait_pr.sh N && gh pr merge N --merge`.
- **Benchmark:** re-run only the setup the item affects (graphs and
  embeddings are cached).

1. **Accent folding in recall.** `rankTextsLexically` folds with `foldText`
   from `conversation_search_pure`.
   - Test: a memory written without accents is found by a question with
     them.
   - Target: allergy, natural, at least 2 of 3.
2. **One slot per content in recall.** Identical memories collapse to the
   newest copy before the limit is applied.
   - Test: three identical fillers and one fact leave room for the fact.
3. **Recall depth on LongMemEval S.** Port Supernova's
   `dev/bancada/longmemeval.py` (the corpus is MIT). This is a no-LLM
   measurement: ingest each conversation into a MAGMA graph, then measure
   whether the answer's chunk is in recall's top 8, 16 and 40, by embedding
   alone and by embedding plus words. Embeddings only, a few dollars at
   most.
   - Output: a table in `RESULTS.md` and a recommendation for the limit.
   - Change the limit only if moving from 8 to 16 recovers at least 10% of
     the answerable questions, and only after the Marta benchmark confirms
     no drop.
4. **Stem matching in `session_search` ranked terms.** A query word matches
   stored words that share its first 5 characters.
   - Target: "fisio", Markdown memory, forced search, 3 of 3.
   - Guard: no question in the per-question table drops.
5. **Capture check.** The benchmark reports whether any planted fact was in
   a turn skipped by `shouldSkipAutoMemoryCapture` (about 43% of user
   messages are skipped as trivial).
6. **Second judge column.** Supernova's new rule: "I think you never told
   me" counts as "doesn't remember". It is reported in its own column; the
   official numbers keep the old rubric so the runs stay comparable with
   earlier ones.
7. **Free models.** Resume Nemotron and ERNIE once OpenRouter's daily cap
   resets (same command, the log resumes).

## How a change is accepted

- 3 seeds × 1 run is 3 samples per question: noise is about ±10 points per
  row.
- A change is kept when its target improves and no other row drops more
  than 5 points. If the result is ambiguous, run 2 more repetitions, not
  more.
- Comparisons are made per question, not only on the totals.
- The benchmark's data, questions and official judge rubric do not change
  during the night.

## Budget and stop conditions

- **Marta benchmark:** at most 8 full runs (DeepSeek, about 96 runs × 3
  calls × 20k tokens each).
- **LongMemEval:** embeddings only.
- **Stop when:** two items in a row fail to beat the baseline, a PR fails
  CI twice, or API errors pass 10% of the runs.
- **On stopping:** write the report, and push no half-done work.

## Out of scope (decisions for the maintainer)

- **A Decision-model search over MAGMA's short list** (Supernova's cheap
  `lembrar`: top 40 by embedding plus words, about $0.0006 per query). It
  needs Gemini as a dependency, a paid key, and the conversation's excerpts
  going to Google. Item 3 says whether recall alone is short of it.
- **A gatekeeper.** With recall on every message, forced search adds 18
  points over natural. Worth it only if item 3 shows recall misses.
- **Rerank on by default**, any change to persistence, and the official
  judge rubric.

## Morning deliverables

- **Merged PRs,** each with its before/after rows in `RESULTS.md`.
- **A short report:**
  - the new table;
  - what was tried and dropped, and why;
  - item 3's recall-depth numbers and the recommendation;
  - what waits on the maintainer.

## References

- Yang, Shi, Zhao. *Forget Freely, Grep Later* (GrepMem). arXiv:2611.25123.
- Jiang, Li, Li, Li. *MAGMA: A Multi-Graph based Agentic Memory
  Architecture for AI Agents*. arXiv:2601.03236.
- Wu et al. *LongMemEval*. arXiv:2410.10813.
- Supernova: `docs/relatorios/BUSCA-bancada.md`, `docs/prd/PRD-M-memoria.md`
  (PR #66), `dev/bancada/longmemeval.py`.
