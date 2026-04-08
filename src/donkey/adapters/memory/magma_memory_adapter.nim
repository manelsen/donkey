## magma_memory_adapter — SemanticMemoryPort backed by MAGMA multi-graph.
##
## Bridges the MemoryPort concept to the MagmaGraph relational store.
## Four orthogonal graphs (semantic, temporal, entity, causal) provide
## structured retrieval per MAGMA (arXiv:2601.03236).
##
## Compile with -d:withPostgres to activate.

import ../../core/types
import ../../ports/memory
import ../../ports/embedding
import ../../ports/multigraph_store
import ../../ports/reranking
import ../../domain/memory/commitment_pure
import ../../domain/memory/episode_pure
import ../../domain/memory/lessons_pure

when defined(withPostgres) or defined(withSqlite):
  import std/[json, strutils, times, algorithm, options, tables]
  when defined(withPostgres):
    import ./magma_graph
  when defined(withSqlite):
    import ./sqlite_magma_store
  import ../../domain/memory/graph_pure
  import ../../domain/memory/rrf

  const
    NtUserProfile = "user_profile"
    NtPreference  = "preference"
    NtMemory      = "memory"
    NtEntity      = "entity"
    NtCommitment  = "commitment"
    NtEpisode     = "episode"
    NtLesson      = "lesson"

  type
    QueryIntent* = enum
      qiSemantic, qiEntity, qiTemporal, qiCausal, qiHybrid

    QueryPolicy* = object
      intent*:         QueryIntent
      semanticWeight*: float
      entityWeight*:   float
      temporalWeight*: float
      neighborWeight*: float
      causalWeight*:   float

    SearchConfig* = object
      semanticTopKMultiplier*: int
      recentTopKMultiplier*:   int
      rerankPoolSize*:         int
      rerankWeight*:           float32

  func defaultPolicy*(): QueryPolicy =
    QueryPolicy(intent: qiSemantic, semanticWeight: 0.4, entityWeight: 0.25,
                temporalWeight: 0.25, neighborWeight: 0.1, causalWeight: 0.0)

  func defaultSearchConfig*(): SearchConfig =
    SearchConfig(
      semanticTopKMultiplier: 8,
      recentTopKMultiplier: 4,
      rerankPoolSize: 24,
      rerankWeight: 0.85'f32,
    )

  func clampUnit(score: float32): float32 =
    if score < 0.0'f32:
      0.0'f32
    elif score > 1.0'f32:
      1.0'f32
    else:
      score

  func classifyQuery*(query: string): QueryPolicy =
    result = defaultPolicy()
    let q = query.toLowerAscii()
    let temporalHints = ["when", "recent", "yesterday", "last",
                         "before", "after", "earlier", "first", "then",
                         "ago", "today", "chronolog"]
    let entityHints = ["who", "what", "where", "which", "person",
                       "people", "company", "team"]
    let causalHints = ["why", "because", "cause", "caused", "causal",
                       "led to", "lead to", "resulted in", "resulting in",
                       "due to", "reason"]
    var isTemporal = false
    var isEntity = false
    var isCausal = false
    for hint in temporalHints:
      if q.contains(hint):
        isTemporal = true
        break
    for hint in entityHints:
      if q.contains(hint):
        isEntity = true
        break
    for hint in causalHints:
      if q.contains(hint):
        isCausal = true
        break
    if isCausal:
      result.intent = qiCausal
      result.semanticWeight = 0.20
      result.entityWeight =
        if isEntity: 0.20
        else: 0.15
      result.temporalWeight =
        if isTemporal: 0.20
        else: 0.10
      result.neighborWeight = 0.10
      result.causalWeight = 1.0 - (result.semanticWeight + result.entityWeight +
                                   result.temporalWeight + result.neighborWeight)
    elif isTemporal and not isEntity:
      result.intent = qiTemporal
      result.temporalWeight = 0.40
      result.semanticWeight = 0.30
      result.entityWeight   = 0.20
      result.neighborWeight = 0.10
      result.causalWeight   = 0.0
    elif isEntity and not isTemporal:
      result.intent = qiEntity
      result.entityWeight   = 0.40
      result.semanticWeight = 0.30
      result.temporalWeight = 0.20
      result.neighborWeight = 0.10
      result.causalWeight   = 0.0
    elif isTemporal and isEntity:
      result.intent = qiHybrid
      result.semanticWeight = 0.25
      result.entityWeight   = 0.30
      result.temporalWeight = 0.30
      result.neighborWeight = 0.15
      result.causalWeight   = 0.0

  const
    CausalCarryOverMarkers = [
      "therefore", "thus", "consequently", "hence", "as a result",
      "because of that", "because of this", "for that reason",
      "this caused", "that caused", "which caused",
      "this led to", "that led to", "which led to",
      "this resulted in", "that resulted in", "which resulted in",
      "so we", "so i", "so the", "that meant", "this meant",
    ]

  func impliesPreviousCause*(text: string): bool =
    let normalized = text.toLowerAscii().replace('\n', ' ').strip()
    if normalized.len == 0:
      return false
    for marker in CausalCarryOverMarkers:
      if normalized.startsWith(marker) or normalized.contains(marker):
        return true
    false

  func causalTraversalDirection*(query: string): string =
    let normalized = query.toLowerAscii()
    if normalized.contains("what caused") or normalized.contains("why") or
       normalized.contains("because") or normalized.contains("reason"):
      return "in"
    if normalized.contains("led to") or normalized.contains("lead to") or
       normalized.contains("resulted in") or normalized.contains("effect") or
       normalized.contains("consequence"):
      return "out"
    "both"

  type
    MagmaMemoryAdapter* = ref object
      graph*:        MultigraphStorePort
      embedFn*:      EmbedFn
      rerankFn*:     RerankFn
      searchConfig*: SearchConfig

  proc newMagmaMemoryAdapter*(graph: MultigraphStorePort;
                              embedFn: EmbedFn;
                              rerankFn: RerankFn = nil;
                              searchConfig = defaultSearchConfig()): MagmaMemoryAdapter =
    graph.migrate()
    MagmaMemoryAdapter(
      graph: graph,
      embedFn: embedFn,
      rerankFn: rerankFn,
      searchConfig: searchConfig,
    )

  when defined(withPostgres):
    proc newMagmaMemoryAdapter*(dsn: string;
                                embedFn: EmbedFn;
                                rerankFn: RerankFn = nil;
                                searchConfig = defaultSearchConfig()): MagmaMemoryAdapter =
      newMagmaMemoryAdapter(newMagmaGraph(dsn).toStorePort(), embedFn, rerankFn, searchConfig)

  when defined(withSqlite):
    proc newSqliteMagmaMemoryAdapter*(dbPath: string;
                                      embedFn: EmbedFn;
                                      rerankFn: RerankFn = nil;
                                      searchConfig = defaultSearchConfig();
                                      vectorExtensionPath = ""): MagmaMemoryAdapter =
      newMagmaMemoryAdapter(
        newSqliteMagmaStoreAdapter(
          dbPath,
          vectorExtensionPath = vectorExtensionPath,
        ).toStorePort(),
        embedFn,
        rerankFn,
        searchConfig,
      )

  proc profileId*(userId: UserId): string =
    $userId & "_profile"

  proc prefId*(userId: UserId): string =
    $userId & "_prefs"

  proc memId*(a: MagmaMemoryAdapter; userId: UserId): string =
    var maxIdx = -1
    for node in a.graph.listNodes($userId, NtMemory):
      let marker = node.id.rfind("_m")
      if marker < 0:
        continue
      try:
        maxIdx = max(maxIdx, parseInt(node.id[marker + 2 .. ^1]))
      except ValueError:
        discard
    result = $userId & "_m" & $(maxIdx + 1)

  proc entId*(userId: UserId; name: string): string =
    $userId & "_ent_" & normalizeEntity(name).replace(" ", "_")

  proc commitmentNodeId*(userId: UserId; commitmentId: string): string =
    $userId & "_commit_" & commitmentId

  proc episodeNodeId*(userId: UserId; episodeId: string): string =
    $userId & "_episode_" & episodeId

  proc lessonNodeId*(userId: UserId; lessonId: string): string =
    $userId & "_lesson_" & lessonId

  func commitmentOwnerLabel(owner: CommitmentOwner): string =
    case owner
    of coUser: "user"
    of coAgent: "agent"

  func parseCommitmentOwner(raw: string): CommitmentOwner =
    case raw.toLowerAscii()
    of "user": coUser
    else: coAgent

  func commitmentStatusLabel(status: CommitmentStatus): string =
    case status
    of csOpen: "open"
    of csDone: "done"
    of csBroken: "broken"
    of csCancelled: "cancelled"

  func parseCommitmentStatus(raw: string): CommitmentStatus =
    case raw.toLowerAscii()
    of "done": csDone
    of "broken": csBroken
    of "cancelled": csCancelled
    else: csOpen

  proc commitmentMeta(c: Commitment): JsonNode =
    result = %*{
      "commitmentId": c.id,
      "owner": commitmentOwnerLabel(c.owner),
      "status": commitmentStatusLabel(c.status),
      "score": c.score,
    }
    if c.dueAt.isSome:
      result["dueAt"] = %c.dueAt.get()
    else:
      result["dueAt"] = newJNull()

  proc parseCommitment(node: MagmaNode): Commitment =
    let meta = if node.meta != nil: node.meta else: newJObject()
    let dueAtNode = meta{"dueAt"}
    let dueAt =
      if dueAtNode.kind in {JInt, JFloat}:
        some(dueAtNode.getBiggestInt().int64)
      elif dueAtNode.kind == JString and dueAtNode.getStr("").len > 0:
        try:
          some(parseBiggestInt(dueAtNode.getStr("")).int64)
        except ValueError:
          none(int64)
      else:
        none(int64)
    let owner = parseCommitmentOwner(meta{"owner"}.getStr(""))
    let status = parseCommitmentStatus(meta{"status"}.getStr(""))
    result = Commitment(
      id: meta{"commitmentId"}.getStr(node.id),
      owner: owner,
      status: status,
      dueAt: dueAt,
      score: meta{"score"}.getFloat(commitmentScore(
        Commitment(owner: owner, status: status, dueAt: dueAt), node.timestamp).float).float32,
      sourceText: node.content,
    )

  proc episodeMeta(episode: EpisodeJournal): JsonNode =
    %*{
      "episodeId": episode.id,
      "startTs": episode.startTs,
      "endTs": episode.endTs,
      "sourceMemoryIds": episode.sourceMemoryIds,
    }

  proc parseEpisode(node: MagmaNode): EpisodeJournal =
    let meta = if node.meta != nil: node.meta else: newJObject()
    var sourceMemoryIds: seq[string]
    for item in meta{"sourceMemoryIds"}:
      if item.kind == JString:
        sourceMemoryIds.add(item.getStr())
    result = EpisodeJournal(
      id: meta{"episodeId"}.getStr(node.id),
      title: node.content,
      summary: meta{"summary"}.getStr(""),
      startTs: meta{"startTs"}.getBiggestInt(0).int64,
      endTs: meta{"endTs"}.getBiggestInt(0).int64,
      sourceMemoryIds: sourceMemoryIds,
    )

  proc lessonMeta(lesson: Lesson): JsonNode =
    %*{
      "lessonId": lesson.id,
      "confidence": lesson.confidence,
      "sourceEpisodeId": lesson.sourceEpisodeId,
      "retrievalTags": lesson.retrievalTags,
    }

  proc parseLesson(node: MagmaNode): Lesson =
    let meta = if node.meta != nil: node.meta else: newJObject()
    var retrievalTags: seq[string]
    for item in meta{"retrievalTags"}:
      if item.kind == JString:
        retrievalTags.add(item.getStr())
    result = Lesson(
      id: meta{"lessonId"}.getStr(node.id),
      text: node.content,
      confidence: meta{"confidence"}.getFloat(0.0).float32,
      sourceEpisodeId: meta{"sourceEpisodeId"}.getStr(""),
      retrievalTags: retrievalTags,
    )

  func lessonConfidence(node: MagmaNode): float =
    if node.meta != nil:
      node.meta{"confidence"}.getFloat(0.0)
    else:
      0.0

  proc hasProfile*(a: MagmaMemoryAdapter; userId: UserId): bool =
    a.graph.getNode(profileId(userId)).isSome

  proc loadContext*(a: MagmaMemoryAdapter; userId: UserId): UserContext =
    var userMd = ""
    var memLines: seq[string]
    var prefMd = ""
    let profileNode = a.graph.getNode(profileId(userId))
    if profileNode.isSome:
      userMd = profileNode.get().content
    let prefNode = a.graph.getNode(prefId(userId))
    if prefNode.isSome:
      prefMd = prefNode.get().content
    let memNodes = a.graph.queryByTimeRange($userId, 0, getTime().toUnix() + 1, limit = 200)
    for m in memNodes:
      if m.nodeType == NtMemory:
        memLines.add(m.content)
    UserContext(
      userId:        userId,
      userMd:        userMd,
      memoryMd:      memLines.join("\n\n"),
      preferencesMd: prefMd,
    )

  proc stats*(a: MagmaMemoryAdapter; userId: UserId): MagmaStats =
    a.graph.statsForUser($userId)

  proc stats*(a: MagmaMemoryAdapter): MagmaStats =
    a.graph.statsGlobal()

  proc upsertNode(a: MagmaMemoryAdapter;
                  nid, userId, nodeType, content: string;
                  emb: seq[float32];
                  ts: int64;
                  meta: JsonNode = nil) =
    a.graph.upsertNode(MagmaNode(
      id: nid,
      userId: userId,
      nodeType: nodeType,
      content: content,
      embedding: emb,
      timestamp: ts,
      meta: if meta != nil: meta else: %*{},
    ))

  proc saveUserMd*(a: MagmaMemoryAdapter; userId: UserId; content: string) =
    let nid = profileId(userId)
    a.upsertNode(nid, $userId, NtUserProfile, content, a.embedFn(content), getTime().toUnix())

  proc savePreferences*(a: MagmaMemoryAdapter; userId: UserId; content: string) =
    let nid = prefId(userId)
    a.upsertNode(nid, $userId, NtPreference, content, a.embedFn(content), getTime().toUnix())

  proc saveCommitment*(a: MagmaMemoryAdapter; userId: UserId; commitment: Commitment) =
    let nid = commitmentNodeId(userId, commitment.id)
    a.upsertNode(
      nid,
      $userId,
      NtCommitment,
      commitment.sourceText,
      a.embedFn(commitment.sourceText),
      getTime().toUnix(),
      commitmentMeta(commitment),
    )

  proc loadCommitments*(a: MagmaMemoryAdapter; userId: UserId): seq[Commitment] =
    let nodes = a.graph.listNodes($userId, NtCommitment)
    if nodes.len > 0:
      for idx in countdown(nodes.high, 0):
        result.add(parseCommitment(nodes[idx]))

  proc updateCommitmentStatus*(a: MagmaMemoryAdapter;
                               userId: UserId;
                               commitmentId: string;
                               status: CommitmentStatus): bool =
    let nid = commitmentNodeId(userId, commitmentId)
    let current = a.graph.getNode(nid)
    if current.isNone:
      return false
    var commitment = parseCommitment(current.get())
    commitment.status = status
    commitment.score = commitmentScore(commitment, getTime().toUnix())
    a.upsertNode(
      nid,
      $userId,
      NtCommitment,
      commitment.sourceText,
      a.embedFn(commitment.sourceText),
      current.get().timestamp,
      commitmentMeta(commitment),
    )
    true

  proc saveEpisode*(a: MagmaMemoryAdapter; userId: UserId; episode: EpisodeJournal) =
    let nid = episodeNodeId(userId, episode.id)
    var meta = episodeMeta(episode)
    meta["summary"] = %episode.summary
    a.upsertNode(
      nid,
      $userId,
      NtEpisode,
      episode.title,
      a.embedFn(episode.title & "\n" & episode.summary),
      episode.endTs,
      meta,
    )

  proc loadEpisodes*(a: MagmaMemoryAdapter; userId: UserId): seq[EpisodeJournal] =
    let nodes = a.graph.listNodes($userId, NtEpisode)
    if nodes.len > 0:
      for idx in countdown(nodes.high, 0):
        result.add(parseEpisode(nodes[idx]))

  proc saveLesson*(a: MagmaMemoryAdapter; userId: UserId; lesson: Lesson) =
    let nid = lessonNodeId(userId, lesson.id)
    a.upsertNode(
      nid,
      $userId,
      NtLesson,
      lesson.text,
      a.embedFn(lesson.text),
      getTime().toUnix(),
      lessonMeta(lesson),
    )

  proc loadLessons*(a: MagmaMemoryAdapter; userId: UserId): seq[Lesson] =
    let nodes = a.graph.listNodes($userId, NtLesson)
    if nodes.len > 0:
      for idx in countdown(nodes.high, 0):
        result.add(parseLesson(nodes[idx]))

  proc extractAndSaveLessons*(a: MagmaMemoryAdapter;
                              userId: UserId;
                              episodes: seq[EpisodeJournal];
                              commitments: seq[Commitment];
                              maxLessonsPerSource = 1): int =
    for episode in episodes:
      for lesson in extractLessonsFromEpisode(episode, maxLessons = maxLessonsPerSource):
        a.saveLesson(userId, lesson)
        inc result
    for commitment in commitments:
      for lesson in extractLessonsFromCommitmentOutcome(
          commitment, maxLessons = maxLessonsPerSource):
        a.saveLesson(userId, lesson)
        inc result

  proc appendMemory*(a: MagmaMemoryAdapter; userId: UserId; text: string) =
    let nid = a.memId(userId)
    let emb = a.embedFn(text)
    let ts = getTime().toUnix()
    let prevMem = a.graph.getLastNode($userId, nodeType = NtMemory)
    let emptyMeta = %*{}
    discard a.graph.insertNode(MagmaNode(
      id: nid, userId: $userId, nodeType: NtMemory,
      content: text, embedding: emb, timestamp: ts, meta: emptyMeta,
    ))
    if prevMem.isSome and prevMem.get().nodeType == NtMemory:
      a.graph.linkTemporal(prevMem.get().id, nid)
      if impliesPreviousCause(text):
        discard a.graph.insertEdge(MagmaEdge(
          fromId: prevMem.get().id, toId: nid, edgeType: EdgeCausal,
          weight: 1.0, meta: emptyMeta,
        ))
    let triples = text.extractTriples().filterValidTriples()
    for t in triples:
      if t.subject.isValidEntity:
        let sId = entId(userId, t.subject)
        discard a.graph.insertNode(MagmaNode(
          id: sId, userId: $userId, nodeType: NtEntity,
          content: t.subject, timestamp: ts, meta: emptyMeta,
        ))
        discard a.graph.insertEdge(MagmaEdge(
          fromId: nid, toId: sId, edgeType: EdgeMentions,
          weight: t.confidence.float64, meta: emptyMeta,
        ))
      if t.obj.isValidEntity and t.obj != t.subject:
        let oId = entId(userId, t.obj)
        discard a.graph.insertNode(MagmaNode(
          id: oId, userId: $userId, nodeType: NtEntity,
          content: t.obj, timestamp: ts, meta: emptyMeta,
        ))
        discard a.graph.insertEdge(MagmaEdge(
          fromId: nid, toId: oId, edgeType: EdgeAbout,
          weight: t.confidence.float64, meta: emptyMeta,
        ))

  proc searchWithRerank*(a: MagmaMemoryAdapter;
                         userId: UserId;
                         query: string;
                         limit: int;
                         rerankFnOverride: RerankFn = nil): seq[MemoryHit] =
    type
      RankedMemory = object
        id:          string
        content:     string
        timestamp:   int64
        semanticScore: float
        entityScore:   float
        temporalScore: float
        neighborScore: float
        causalScore:   float
        baseScore:   float
        rerankScore: float32
        finalScore:  float32
        kind:        string

    let emb = a.embedFn(query)
    let policy = classifyQuery(query)
    let uid = $userId
    let semanticTopK = max(limit * max(a.searchConfig.semanticTopKMultiplier, 1),
                           max(a.searchConfig.rerankPoolSize, limit))
    let recentTopK = max(limit * max(a.searchConfig.recentTopKMultiplier, 1),
                         max(a.searchConfig.rerankPoolSize, limit))

    var rankedById: Table[string, RankedMemory]

    proc ensureNode(n: MagmaNode) =
      if n.id notin rankedById:
        rankedById[n.id] = RankedMemory(
          id: n.id,
          content: n.content,
          timestamp: n.timestamp,
          rerankScore: -1.0'f32,
          kind: n.nodeType,
        )

    proc addSignal(n: MagmaNode;
                   semantic = 0.0;
                   entity = 0.0;
                   temporal = 0.0;
                   neighbor = 0.0;
                   causal = 0.0) =
      ensureNode(n)
      var entry = rankedById[n.id]
      entry.semanticScore += semantic
      entry.entityScore += entity
      entry.temporalScore += temporal
      entry.neighborScore += neighbor
      entry.causalScore += causal
      entry.baseScore = entry.semanticScore + entry.entityScore +
                        entry.temporalScore + entry.neighborScore +
                        entry.causalScore
      rankedById[n.id] = entry

    let semanticHits = a.graph.searchSimilar(uid, emb, topK = semanticTopK)
    for rank, hit in semanticHits:
      if hit.node.nodeType in [NtMemory, NtLesson]:
        let lessonBoost =
          if hit.node.nodeType == NtLesson:
            clamp(hit.node.lessonConfidence, 0.35, 1.0)
          else:
            1.0
        addSignal(hit.node, semantic = rrfScoreWeighted(
          rank, policy.semanticWeight * lessonBoost))

    if policy.intent in {qiEntity, qiHybrid}:
      for hit in semanticHits:
        if hit.node.nodeType != NtMemory:
          continue
        let entityNeighbors = a.graph.traverseNeighbors(
          hit.node.id, edgeTypes = @[EdgeMentions, EdgeAbout], maxDepth = 1)
        for rank, neighbor in entityNeighbors:
          let score = rrfScoreWeighted(rank, policy.entityWeight)
          addSignal(neighbor, entity = score)
          let memNeighbors = a.graph.traverseNeighbors(
            neighbor.id, edgeTypes = @[EdgeMentions, EdgeAbout], maxDepth = 1)
          for memNode in memNeighbors:
            if memNode.nodeType == NtMemory:
              addSignal(memNode, entity = score * 0.5)

    let recentNodes = a.graph.queryByTimeRange(uid, 0, getTime().toUnix() + 1,
                                               limit = recentTopK)
    if policy.intent in {qiTemporal, qiHybrid, qiCausal}:
      for rank, node in recentNodes:
        if node.nodeType == NtMemory:
          addSignal(node, temporal = rrfScoreWeighted(rank, policy.temporalWeight))

    if policy.intent in {qiTemporal, qiHybrid}:
      for hit in semanticHits:
        if hit.node.nodeType != NtMemory:
          continue
        let temporalNeighbors = a.graph.traverseNeighbors(
          hit.node.id, edgeTypes = @[EdgeTemporal], maxDepth = 2)
        for rank, neighbor in temporalNeighbors:
          addSignal(neighbor, neighbor = rrfScoreWeighted(rank, policy.neighborWeight))

    if policy.intent in {qiCausal, qiHybrid} and policy.causalWeight > 0.0:
      let causalDirection = causalTraversalDirection(query)
      for hit in semanticHits:
        if hit.node.nodeType != NtMemory:
          continue
        let causalEdges = a.graph.getEdges(
          hit.node.id, direction = causalDirection, edgeType = EdgeCausal)
        for rank, edge in causalEdges:
          let neighborId =
            if edge.fromId == hit.node.id: edge.toId
            else: edge.fromId
          let neighbor = a.graph.getNode(neighborId)
          if neighbor.isSome and neighbor.get().nodeType == NtMemory:
            addSignal(neighbor.get(), causal = rrfScoreWeighted(rank, policy.causalWeight))

    if rankedById.len == 0:
      for m in recentNodes:
        if m.nodeType == NtMemory:
          ensureNode(m)

    var rankedMemories: seq[RankedMemory]
    for _, entry in rankedById:
      if entry.kind in [NtMemory, NtLesson]:
        rankedMemories.add(entry)
    rankedMemories.sort(proc(x, y: RankedMemory): int =
      cmp(y.baseScore, x.baseScore))

    let maxBaseScore =
      if rankedMemories.len > 0 and rankedMemories[0].baseScore > 0:
        rankedMemories[0].baseScore.float32
      else:
        0.0'f32

    for i in 0 ..< rankedMemories.len:
      rankedMemories[i].finalScore =
        if maxBaseScore > 0.0'f32:
          clampUnit(rankedMemories[i].baseScore.float32 / maxBaseScore)
        else:
          0.0'f32

    let rerankFn =
      if rerankFnOverride != nil: rerankFnOverride
      else: a.rerankFn

    if rerankFn != nil and rankedMemories.len > 1 and a.searchConfig.rerankPoolSize > 1:
      let rerankCount = min(rankedMemories.len, a.searchConfig.rerankPoolSize)
      var candidates: seq[RerankCandidate]
      candidates.setLen(rerankCount)
      for i in 0 ..< rerankCount:
        let entry = rankedMemories[i]
        candidates[i] = RerankCandidate(
          id: entry.id,
          content: entry.content,
          kind: entry.kind,
          timestamp: entry.timestamp,
          baseScore: entry.finalScore,
          semanticScore: clampUnit(entry.semanticScore.float32),
          entityScore: clampUnit(entry.entityScore.float32),
          temporalScore: clampUnit(entry.temporalScore.float32),
          neighborScore: clampUnit(entry.neighborScore.float32),
          causalScore: clampUnit(entry.causalScore.float32),
        )
      let rerankScores = rerankFn(query, candidates)
      if rerankScores.len == rerankCount:
        for i in 0 ..< rerankCount:
          rankedMemories[i].rerankScore = rerankScores[i]
          rankedMemories[i].finalScore = clampUnit(
            rerankScores[i] * a.searchConfig.rerankWeight +
            rankedMemories[i].finalScore * (1.0'f32 - a.searchConfig.rerankWeight)
          )

    rankedMemories.sort(proc(x, y: RankedMemory): int =
      let finalCmp = cmp(y.finalScore, x.finalScore)
      if finalCmp != 0:
        return finalCmp
      cmp(y.baseScore, x.baseScore))

    var hits: seq[MemoryHit]
    for entry in rankedMemories:
      if hits.len >= limit:
        break
      hits.add(MemoryHit(
        content: entry.content,
        score: entry.finalScore,
        kind: entry.kind,
      ))
    hits

  proc search*(a: MagmaMemoryAdapter; userId: UserId;
               query: string; limit: int): seq[MemoryHit] =
    a.searchWithRerank(userId, query, limit)

  proc toSearchFn*(a: MagmaMemoryAdapter): SearchFn =
    proc(userId: UserId; query: string; limit: int): seq[MemoryHit]
        {.gcsafe, raises: [].} =
      try:
        result = a.search(userId, query, limit)
      except Exception:
        result = @[]

  proc deleteUser*(a: MagmaMemoryAdapter; userId: UserId) =
    for node in a.graph.listNodes($userId):
      discard a.graph.deleteNode(node.id)

  proc clearMemory*(a: MagmaMemoryAdapter; userId: UserId) =
    for node in a.graph.listNodes($userId, NtMemory):
      discard a.graph.deleteNode(node.id)
    for node in a.graph.listNodes($userId, NtEntity):
      if a.graph.getEdges(node.id, direction = "both").len == 0:
        discard a.graph.deleteNode(node.id)

  proc resetBootstrap*(a: MagmaMemoryAdapter; userId: UserId) =
    discard a.graph.deleteNode(profileId(userId))
    discard a.graph.deleteNode(prefId(userId))

else:
  type
    MagmaMemoryAdapter* = ref object
    QueryIntent* = enum
      qiSemantic, qiEntity, qiTemporal, qiCausal, qiHybrid
    QueryPolicy* = object
      intent*:         QueryIntent
      semanticWeight*: float
      entityWeight*:   float
      temporalWeight*: float
      neighborWeight*: float
      causalWeight*:   float
    SearchConfig* = object
      semanticTopKMultiplier*: int
      recentTopKMultiplier*:   int
      rerankPoolSize*:         int
      rerankWeight*:           float32

  func defaultPolicy*(): QueryPolicy =
    QueryPolicy(intent: qiSemantic, semanticWeight: 0.4, entityWeight: 0.25,
                temporalWeight: 0.25, neighborWeight: 0.1, causalWeight: 0.0)
  func defaultSearchConfig*(): SearchConfig =
    SearchConfig(
      semanticTopKMultiplier: 8,
      recentTopKMultiplier: 4,
      rerankPoolSize: 24,
      rerankWeight: 0.85'f32,
    )
  func classifyQuery*(query: string): QueryPolicy = defaultPolicy()
  proc newMagmaMemoryAdapter*(dsn: string;
                              embedFn: EmbedFn;
                              rerankFn: RerankFn = nil;
                              searchConfig = defaultSearchConfig()): MagmaMemoryAdapter =
    MagmaMemoryAdapter()
  proc newMagmaMemoryAdapter*(graph: MultigraphStorePort;
                              embedFn: EmbedFn;
                              rerankFn: RerankFn = nil;
                              searchConfig = defaultSearchConfig()): MagmaMemoryAdapter =
    MagmaMemoryAdapter()
  proc newSqliteMagmaMemoryAdapter*(dbPath: string;
                                    embedFn: EmbedFn;
                                    rerankFn: RerankFn = nil;
                                    searchConfig = defaultSearchConfig()): MagmaMemoryAdapter =
    MagmaMemoryAdapter()
  proc hasProfile*(a: MagmaMemoryAdapter; userId: UserId): bool = false
  proc loadContext*(a: MagmaMemoryAdapter; userId: UserId): UserContext =
    UserContext(userId: userId)
  proc stats*(a: MagmaMemoryAdapter; userId: UserId): MagmaStats = MagmaStats()
  proc stats*(a: MagmaMemoryAdapter): MagmaStats = MagmaStats()
  proc saveUserMd*(a: MagmaMemoryAdapter; userId: UserId; content: string) = discard
  proc appendMemory*(a: MagmaMemoryAdapter; userId: UserId; text: string) = discard
  proc savePreferences*(a: MagmaMemoryAdapter; userId: UserId; content: string) = discard
  proc saveCommitment*(a: MagmaMemoryAdapter; userId: UserId; commitment: Commitment) = discard
  proc loadCommitments*(a: MagmaMemoryAdapter; userId: UserId): seq[Commitment] = @[]
  proc saveEpisode*(a: MagmaMemoryAdapter; userId: UserId; episode: EpisodeJournal) = discard
  proc loadEpisodes*(a: MagmaMemoryAdapter; userId: UserId): seq[EpisodeJournal] = @[]
  proc saveLesson*(a: MagmaMemoryAdapter; userId: UserId; lesson: Lesson) = discard
  proc loadLessons*(a: MagmaMemoryAdapter; userId: UserId): seq[Lesson] = @[]
  proc extractAndSaveLessons*(a: MagmaMemoryAdapter;
                              userId: UserId;
                              episodes: seq[EpisodeJournal];
                              commitments: seq[Commitment];
                              maxLessonsPerSource = 1): int = 0
  proc updateCommitmentStatus*(a: MagmaMemoryAdapter;
                               userId: UserId;
                               commitmentId: string;
                               status: CommitmentStatus): bool = false
  proc search*(a: MagmaMemoryAdapter; userId: UserId; query: string; limit: int): seq[MemoryHit] = @[]
  proc toSearchFn*(a: MagmaMemoryAdapter): SearchFn = nil
  proc deleteUser*(a: MagmaMemoryAdapter; userId: UserId) = discard
  proc clearMemory*(a: MagmaMemoryAdapter; userId: UserId) = discard
  proc resetBootstrap*(a: MagmaMemoryAdapter; userId: UserId) = discard
