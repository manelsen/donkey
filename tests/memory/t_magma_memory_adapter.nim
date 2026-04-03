## Tests for adapters/memory/magma_memory_adapter — MAGMA MemoryPort.
##
## Validates that MagmaMemoryAdapter satisfies SemanticMemoryPort:
##   hasProfile, loadContext, saveUserMd, appendMemory,
##   savePreferences, search
##
## Requires PostgreSQL with pgvector on localhost, database donkey_test.
## Run: nim c -d:withPostgres -r tests/memory/t_magma_memory_adapter.nim

when defined(withPostgres):
  import std/[unittest, strutils, options, sequtils]
  import db_connector/db_postgres
  import ../../src/donkey/core/types
  import ../../src/donkey/ports/memory
  import ../../src/donkey/ports/reranking
  import ../../src/donkey/adapters/memory/magma_graph
  import ../../src/donkey/adapters/memory/magma_memory_adapter
  import ../../src/donkey/domain/memory/commitment_pure
  import ../../src/donkey/domain/memory/episode_pure
  import ../../src/donkey/domain/memory/lessons_pure

  const testDsn = "host=localhost port=5432 dbname=donkey_test"

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} =
    var emb: seq[float32]
    for i in 0 ..< 4096:
      if i < text.len.min(64):
        emb.add(float32(text[i mod text.len]) / 255.0)
      else:
        emb.add(0.0'f32)
    emb

  proc setupGraph() =
    let g = newMagmaGraph(testDsn)
    g.migrate()

  proc cleanGraph() =
    let g = newMagmaGraph(testDsn)
    let db = g.openDb()
    defer: db.close()
    try:
      db.exec(sql"DELETE FROM magma_edges")
      db.exec(sql"DELETE FROM magma_nodes")
    except:
      discard

  proc preferPriorityRerankFn(query: string;
                              candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
    for candidate in candidates:
      result.add(if "priority" in candidate.content.toLowerAscii(): 1.0'f32 else: 0.05'f32)

  proc newTestAdapter(rerankFn: RerankFn = nil): MagmaMemoryAdapter =
    setupGraph()
    cleanGraph()
    newMagmaMemoryAdapter(testDsn, fakeEmbedFn, rerankFn)

  suite "MagmaMemoryAdapter - SemanticMemoryPort compliance":

    test "satisfies SemanticMemoryPort concept":
      let a = newTestAdapter()
      discard a.hasProfile(UserId("u1"))
      discard a.loadContext(UserId("u1"))
      a.saveUserMd(UserId("u1"), "profile")
      a.appendMemory(UserId("u1"), "memory text")
      a.savePreferences(UserId("u1"), "prefs")
      discard a.search(UserId("u1"), "query", 5)

  suite "MagmaMemoryAdapter - hasProfile":

    setup:
      let a = newTestAdapter()

    test "returns false for unknown user":
      check not a.hasProfile(UserId("unknown"))

    test "returns true after saveUserMd":
      a.saveUserMd(UserId("u1"), "# Alice\nSome profile")
      check a.hasProfile(UserId("u1"))

    test "returns false for different user":
      a.saveUserMd(UserId("u1"), "# Alice")
      check not a.hasProfile(UserId("u2"))

  suite "MagmaMemoryAdapter - saveUserMd / loadContext":

    setup:
      let a = newTestAdapter()

    test "loadContext returns empty for unknown user":
      let ctx = a.loadContext(UserId("nobody"))
      check ctx.userMd == ""
      check ctx.memoryMd == ""
      check ctx.preferencesMd == ""

    test "saveUserMd and loadContext round-trip":
      let profile = "# Alice\nPreferred name: Ali\nTimezone: UTC"
      a.saveUserMd(UserId("u1"), profile)
      let ctx = a.loadContext(UserId("u1"))
      check ctx.userMd == profile
      check ctx.userId == UserId("u1")

    test "saveUserMd updates existing profile":
      a.saveUserMd(UserId("u1"), "first")
      a.saveUserMd(UserId("u1"), "second")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.userMd == "second"

  suite "MagmaMemoryAdapter - appendMemory":

    setup:
      let a = newTestAdapter()

    test "appendMemory stores content":
      a.appendMemory(UserId("u1"), "User likes Rust")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.memoryMd.contains("Rust")

    test "appendMemory accumulates multiple entries":
      a.appendMemory(UserId("u1"), "First memory")
      a.appendMemory(UserId("u1"), "Second memory")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.memoryMd.contains("First memory")
      check ctx.memoryMd.contains("Second memory")

    test "appendMemory creates node with embedding":
      a.appendMemory(UserId("u1"), "embedded content")
      let g = newMagmaGraph(testDsn)
      let node = g.getLastNode("u1")
      check node.isSome

    test "appendMemory links temporal chain":
      a.appendMemory(UserId("u1"), "first event")
      a.appendMemory(UserId("u1"), "second event")
      let g = newMagmaGraph(testDsn)
      let edges = g.getEdges("u1_m0", edgeType = EdgeTemporal)
      check edges.len >= 1

  suite "MagmaMemoryAdapter - savePreferences":

    setup:
      let a = newTestAdapter()

    test "savePreferences stores and loads":
      let prefs = "language = \"pt-BR\"\ntimezone = \"America/Sao_Paulo\""
      a.savePreferences(UserId("u1"), prefs)
      let ctx = a.loadContext(UserId("u1"))
      check ctx.preferencesMd == prefs

    test "savePreferences updates existing":
      a.savePreferences(UserId("u1"), "first")
      a.savePreferences(UserId("u1"), "updated prefs")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.preferencesMd == "updated prefs"

  suite "MagmaMemoryAdapter - stats":

    setup:
      let a = newTestAdapter()

    test "stats wraps graph counts without SQL in runtime code":
      a.saveUserMd(UserId("u1"), "# Ada")
      a.savePreferences(UserId("u1"), "language = \"nim\"")
      a.appendMemory(UserId("u1"), "m1")
      a.appendMemory(UserId("u1"), "m2")

      let stats = a.stats(UserId("u1"))
      check stats.totalNodes == 4
      check stats.memoryNodes == 2
      check stats.profileNodes == 1
      check stats.preferenceNodes == 1
      check stats.entityNodes == 0
      check stats.embeddingNodes == 4
      check stats.totalEdges == 1

    test "stats aggregates all users for daemon-level status":
      a.saveUserMd(UserId("u1"), "# Ada")
      a.appendMemory(UserId("u1"), "m1")
      a.saveUserMd(UserId("u2"), "# Bob")
      a.appendMemory(UserId("u2"), "m2")

      let stats = a.stats()
      check stats.totalNodes == 4
      check stats.memoryNodes == 2
      check stats.profileNodes == 2
      check stats.preferenceNodes == 0
      check stats.entityNodes == 0
      check stats.embeddingNodes == 4
      check stats.totalEdges == 0

  suite "MagmaMemoryAdapter - commitments":

    setup:
      let a = newTestAdapter()

    test "saveCommitment stores open commitment metadata":
      let c = newCommitment(
        coAgent,
        "I'll send the summary tomorrow.",
        nowSec = 1_700_000_000'i64,
      )
      a.saveCommitment(UserId("u1"), c)
      let commitments = a.loadCommitments(UserId("u1"))
      check commitments.len == 1
      check commitments[0].owner == coAgent
      check commitments[0].status == csOpen
      check commitments[0].dueAt.isSome
      check commitments[0].sourceText.contains("summary")

    test "updateCommitmentStatus persists completion":
      let c = newCommitment(
        coAgent,
        "I'll send the summary tomorrow.",
        nowSec = 1_700_000_000'i64,
      )
      a.saveCommitment(UserId("u1"), c)
      check a.updateCommitmentStatus(UserId("u1"), c.id, csDone)
      let commitments = a.loadCommitments(UserId("u1"))
      check commitments.len == 1
      check commitments[0].status == csDone
      check commitments[0].score == 1.0'f32

  suite "MagmaMemoryAdapter - episodes":

    setup:
      let a = newTestAdapter()

    test "saveEpisode stores episode metadata and source memory ids":
      a.appendMemory(UserId("u1"), "Investigated the timeout spike.")
      a.appendMemory(UserId("u1"), "Patched the retry loop and latency dropped.")
      let episode = newEpisodeJournal(
        title = "Timeout spike resolved",
        summary = "A short investigation led to a retry fix that reduced latency.",
        startTs = 100'i64,
        endTs = 200'i64,
        sourceMemoryIds = @["u1_m0", "u1_m1"],
      )
      a.saveEpisode(UserId("u1"), episode)
      let episodes = a.loadEpisodes(UserId("u1"))
      check episodes.len == 1
      check episodes[0].title == "Timeout spike resolved"
      check episodes[0].summary.contains("retry fix")
      check episodes[0].startTs == 100'i64
      check episodes[0].endTs == 200'i64
      check episodes[0].sourceMemoryIds == @["u1_m0", "u1_m1"]

  suite "MagmaMemoryAdapter - lessons":

    setup:
      let a = newTestAdapter()

    test "saveLesson round-trips text confidence source episode and tags":
      let lesson = newLesson(
        text = "When latency spikes after retries, inspect retry amplification first.",
        confidence = 1.2'f32,
        sourceEpisodeId = "episode-retries",
        retrievalTags = @["latency", "retry", "incident"],
      )
      a.saveLesson(UserId("u1"), lesson)
      let lessons = a.loadLessons(UserId("u1"))
      check lessons.len == 1
      check lessons[0].text.contains("retry amplification")
      check lessons[0].confidence == 1.0'f32
      check lessons[0].sourceEpisodeId == "episode-retries"
      check lessons[0].retrievalTags == @["latency", "retry", "incident"]

    test "extractAndSaveLessons stores bounded lessons from episodes and commitment outcomes":
      let episode = newEpisodeJournal(
        title = "Retry loop investigation",
        summary = "Inspect retry amplification before increasing timeouts.\nCapture graphs before patching.",
        startTs = 100'i64,
        endTs = 200'i64,
        sourceMemoryIds = @["u1_m0", "u1_m1"],
      )
      let doneCommitment = markCompleted(newCommitment(
        coAgent,
        "I'll send the incident summary tomorrow.",
        nowSec = 100'i64,
      ), nowSec = 150'i64)
      let brokenCommitment = markBroken(newCommitment(
        coAgent,
        "I'll send the incident summary tomorrow.",
        nowSec = 100'i64,
      ), nowSec = 300'i64)
      check a.extractAndSaveLessons(
        UserId("u1"),
        @[episode],
        @[doneCommitment, brokenCommitment],
        maxLessonsPerSource = 1,
      ) == 3
      let lessons = a.loadLessons(UserId("u1"))
      check lessons.len == 3
      check lessons.anyIt(it.sourceEpisodeId == episode.id)
      check lessons.anyIt(it.sourceEpisodeId == "commitment:" & doneCommitment.id)
      check lessons.anyIt(it.sourceEpisodeId == "commitment:" & brokenCommitment.id)

  suite "MagmaMemoryAdapter - search":

    setup:
      let a = newTestAdapter()

    test "search returns empty for unknown user":
      let hits = a.search(UserId("nobody"), "query", 5)
      check hits.len == 0

    test "search finds semantic matches":
      a.appendMemory(UserId("u1"), "Nim programming language is efficient")
      a.appendMemory(UserId("u1"), "Rust has borrow checker")
      a.appendMemory(UserId("u1"), "Python is interpreted")
      let hits = a.search(UserId("u1"), "Nim programming", 5)
      check hits.len > 0

    test "search does not cross users":
      a.appendMemory(UserId("u1"), "secret data for u1")
      a.appendMemory(UserId("u2"), "different data for u2")
      let hits = a.search(UserId("u1"), "secret", 5)
      for h in hits:
        check "u2" notin h.content

    test "search returns MemoryHit with kind":
      a.appendMemory(UserId("u1"), "test memory content")
      let hits = a.search(UserId("u1"), "test memory", 5)
      if hits.len > 0:
        check hits[0].kind.len > 0

    test "search reranks top candidates when reranker is present":
      let reranked = newTestAdapter(preferPriorityRerankFn)
      reranked.appendMemory(UserId("u1"), "plain candidate about programming")
      reranked.appendMemory(UserId("u1"), "priority candidate about programming")
      let hits = reranked.search(UserId("u1"), "programming candidate", 2)
      check hits.len == 2
      check "priority" in hits[0].content.toLowerAscii()
      check hits[0].score > hits[1].score

    test "search can surface high-confidence lessons alongside memories":
      a.appendMemory(UserId("u1"), "Retry amplification caused the latency spike.")
      a.saveLesson(UserId("u1"), newLesson(
        text = "Inspect retry amplification before raising timeouts.",
        confidence = 0.95'f32,
        sourceEpisodeId = "episode-retries",
        retrievalTags = @["retry", "latency"],
      ))
      let hits = a.search(UserId("u1"), "retry latency", 3)
      check hits.anyIt(it.kind == "memory")
      check hits.anyIt(it.kind == "lesson")

  suite "MagmaMemoryAdapter - entity extraction":

    setup:
      let a = newTestAdapter()

    test "appendMemory extracts triples as edges":
      a.appendMemory(UserId("u1"), "Alice is a developer")
      let g = newMagmaGraph(testDsn)
      let edges = g.getEdges("u1_m0", edgeType = EdgeMentions)
      discard edges

    test "appendMemory creates entity nodes":
      a.appendMemory(UserId("u1"), "Alice likes Bob")
      let g = newMagmaGraph(testDsn)
      let count = g.nodeCount("u1")
      check count >= 1

  suite "MagmaMemoryAdapter - temporal context":

    setup:
      let a = newTestAdapter()

    test "search enriches with temporal neighbors":
      a.appendMemory(UserId("u1"), "Started new project")
      a.appendMemory(UserId("u1"), "Chose Nim as language")
      a.appendMemory(UserId("u1"), "Set up CI pipeline")
      let hits = a.search(UserId("u1"), "project language", 10)
      check hits.len > 0

  suite "MagmaMemoryAdapter - causal extraction":

    setup:
      let a = newTestAdapter()

    test "appendMemory creates causal edge for effect markers":
      a.appendMemory(UserId("u1"), "The deploy broke production")
      a.appendMemory(UserId("u1"), "Therefore we rolled back immediately")
      let g = newMagmaGraph(testDsn)
      let edges = g.getEdges("u1_m0", edgeType = EdgeCausal)
      check edges.len == 1
      check edges[0].toId == "u1_m1"

    test "appendMemory creates causal edge for anaphoric cause markers":
      a.appendMemory(UserId("u1"), "The cache node crashed")
      a.appendMemory(UserId("u1"), "Because of that, latency spiked for every request")
      let g = newMagmaGraph(testDsn)
      let edges = g.getEdges("u1_m0", edgeType = EdgeCausal)
      check edges.len == 1
      check edges[0].toId == "u1_m1"

  suite "MagmaMemoryAdapter - classifyQuery policy":

    test "default policy has correct weights":
      let p = defaultPolicy()
      check p.intent == qiSemantic
      check p.semanticWeight == 0.4
      check p.entityWeight   == 0.25
      check p.temporalWeight == 0.25
      check p.neighborWeight == 0.1
      check p.causalWeight   == 0.0

    test "temporal query boosts temporal weight":
      let p = classifyQuery("when did I start the project?")
      check p.intent == qiTemporal
      check p.temporalWeight > p.entityWeight

    test "entity query boosts entity weight":
      let p = classifyQuery("who is Alice?")
      check p.intent == qiEntity
      check p.entityWeight > p.temporalWeight

    test "combined query balances both":
      let p = classifyQuery("what did we discuss last time about the project?")
      check p.intent == qiHybrid
      check p.entityWeight >= 0.25
      check p.temporalWeight >= 0.25

    test "causal query boosts causal weight":
      let p = classifyQuery("why did the deployment roll back?")
      check p.intent == qiCausal
      check p.causalWeight > p.temporalWeight
      check p.causalWeight > p.entityWeight

    test "neutral query uses defaults":
      let p = classifyQuery("programming languages")
      check p.intent == qiSemantic
      check p.semanticWeight == 0.4
      check p.temporalWeight == 0.25

  suite "MagmaMemoryAdapter - RRF hybrid search":

    setup:
      let a = newTestAdapter()

    test "search combines semantic and temporal signals":
      for i in 0 ..< 5:
        a.appendMemory(UserId("u1"), "Memory item number " & $i)
      let hits = a.search(UserId("u1"), "Memory item", 3)
      check hits.len > 0

    test "search entity back-linking finds related memories":
      a.appendMemory(UserId("u1"), "Alice is a developer at TechCorp")
      a.appendMemory(UserId("u1"), "Bob works with Alice on ProjectX")
      let hits = a.search(UserId("u1"), "who is Alice", 10)
      check hits.len > 0

    test "search fallback returns recent when no semantic match":
      a.appendMemory(UserId("u1"), "completely unique content xyz123")
      let hits = a.search(UserId("u1"), "something entirely different abc789", 5)
      check hits.len > 0

    test "search does not cross users with RRF":
      a.appendMemory(UserId("u1"), "private data user one")
      a.appendMemory(UserId("u2"), "private data user two")
      let hits = a.search(UserId("u1"), "private data", 5)
      for h in hits:
        check "user two" notin h.content

    test "search respects limit with RRF":
      for i in 0 ..< 20:
        a.appendMemory(UserId("u1"), "memory entry " & $i)
      let hits = a.search(UserId("u1"), "memory entry", 3)
      check hits.len <= 3

    test "temporal query retrieves chronologically close memories":
      a.appendMemory(UserId("u1"), "Yesterday I deployed the server")
      a.appendMemory(UserId("u1"), "Today I fixed a critical bug")
      a.appendMemory(UserId("u1"), "Tomorrow I will write tests")
      let hits = a.search(UserId("u1"), "what did I do recently?", 5)
      check hits.len > 0

    test "causal query surfaces the cause memory before the effect memory":
      a.appendMemory(UserId("u1"), "The cache node crashed")
      a.appendMemory(UserId("u1"), "Because of that, latency spiked for every request")
      let hits = a.search(UserId("u1"), "what caused the latency spike?", 2)
      check hits.len == 2
      check hits[0].content == "The cache node crashed"

  suite "MagmaMemoryAdapter - toSearchFn":

    test "toSearchFn wraps search as closure":
      let a = newTestAdapter()
      a.appendMemory(UserId("u1"), "searchable content here")
      let fn = a.toSearchFn()
      check fn != nil
      let hits = fn(UserId("u1"), "searchable", 5)
      check hits.len > 0

    test "toSearchFn returns empty on unknown user":
      let a = newTestAdapter()
      let fn = a.toSearchFn()
      let hits = fn(UserId("nobody"), "query", 5)
      check hits.len == 0

else:
  echo "MagmaMemoryAdapter tests skipped: -d:withPostgres not set"
