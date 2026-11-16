## magma_memory_adapter — SemanticMemoryPort backed by MAGMA multi-graph.
##
## Bridges the MemoryPort concept to the MagmaGraph relational store.
## Four orthogonal graphs (semantic, temporal, entity, causal) provide
## structured retrieval per MAGMA (arXiv:2601.03236).
##
## Compile with -d:withPostgres to activate.

import ../../core/types
import ../../core/pipeops
import ../../ports/memory
import ../../ports/embedding
import ../../ports/multigraph_store
import ../../ports/reranking
import ../../domain/memory/commitment_pure
import ../../domain/memory/decay
import ../../domain/memory/episode_pure
import ../../domain/memory/provenance_pure
import ../../domain/memory/query_policy_pure

export query_policy_pure  ## the policy lives in the domain; kept visible here

when defined(withPostgres) or defined(withSqlite):
  import std/[json, strutils, times, algorithm, options, tables]
  when defined(withPostgres):
    import ./magma_graph
  when defined(withSqlite):
    import ./sqlite_magma_store
  import ../../domain/memory/session_search_pure
  import ../../domain/memory/rrf

  const
    NtUserProfile = "user_profile"
    NtPreference  = "preference"
    NtMemory      = "memory"
    NtEntity      = "entity"
    NtCommitment  = "commitment"
    NtEpisode     = "episode"

    ContextMemoryNodeLimit = 200
      ## Memory nodes returned by loadContext, newest first.
    MemoryContentReadLimit = 16 * 1024 * 1024
      ## Per-node content cap for those reads; above any stored memory.
    LexicalCandidateLimit  = 2000
      ## Most recent memory nodes scanned for literal query terms.
    LexicalCandidateContentBytes = 4096
      ## Content read per candidate for that scan.

  type
    SearchConfig* = object
      semanticTopKMultiplier*: int
      recentTopKMultiplier*:   int
      rerankPoolSize*:         int
      rerankWeight*:           float32

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

  proc commitmentNodeId*(userId: UserId; commitmentId: string): string =
    $userId & "_commit_" & commitmentId

  proc episodeNodeId*(userId: UserId; episodeId: string): string =
    $userId & "_episode_" & episodeId

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

  proc hasProfile*(a: MagmaMemoryAdapter; userId: UserId): bool =
    a.graph.getNode(profileId(userId)).isSome

  proc readContext*(a: MagmaMemoryAdapter;
                    userId: UserId): Result[UserContext, string] =
    ## The user's context as the graph holds it. An error means the graph
    ## could not be read, which is not the same as a graph with nothing in it.
    var userMd = ""
    var memLines: seq[string]
    var prefMd = ""
    let profileNode = a.graph.getNode(profileId(userId))
    if profileNode.isSome:
      userMd = profileNode.get().content
    let prefNode = a.graph.getNode(prefId(userId))
    if prefNode.isSome:
      prefMd = prefNode.get().content
    ## Filter by type in the query: entity and episode nodes share the
    ## same table and would otherwise push memories out of the window.
    let memNodes = ? a.graph.listNodesLimited(
      $userId, NtMemory, ContextMemoryNodeLimit, MemoryContentReadLimit)
    for m in memNodes:
      memLines.add(m.content)
    ok(UserContext(
      userId:        userId,
      userMd:        userMd,
      memoryMd:      memLines.join("\n\n"),
      preferencesMd: prefMd,
    ))

  proc loadContext*(a: MagmaMemoryAdapter; userId: UserId): UserContext =
    ## readContext for callers that treat an unreadable graph as empty.
    a.readContext(userId).valueOr(UserContext(userId: userId))

  proc loadUserMd*(a: MagmaMemoryAdapter; userId: UserId): string =
    let node = a.graph.getNode(profileId(userId))
    if node.isSome: node.get().content else: ""

  proc loadPreferences*(a: MagmaMemoryAdapter; userId: UserId): string =
    let node = a.graph.getNode(prefId(userId))
    if node.isSome: node.get().content else: ""

  proc hasContext*(a: MagmaMemoryAdapter;
                   userId: UserId): Result[bool, string] =
    ## Whether the graph holds anything of this user: a profile, preferences
    ## or at least one memory. The memory read goes first because it is the
    ## one that reports a graph that cannot be read; "nothing found" must
    ## never be concluded from a failed read.
    let one = ? a.graph.listNodesLimited($userId, NtMemory, 1, 1)
    ok(one.len > 0 or
       a.graph.getNode(profileId(userId)).isSome or
       a.graph.getNode(prefId(userId)).isSome)

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

  proc appendMemory*(a: MagmaMemoryAdapter; userId: UserId; text: string;
                     origin = MemoryOrigin()): Result[void, string]
                     {.discardable.} =
    ## Errors when the store did not take the node. The store reports that
    ## as a plain refusal, so the message is this adapter's.
    let nid = a.memId(userId)
    let emb = a.embedFn(text)
    let ts = getTime().toUnix()
    let prevMem = a.graph.getLastNode($userId, nodeType = NtMemory)
    let stored = a.graph.insertNode(MagmaNode(
      id: nid, userId: $userId, nodeType: NtMemory,
      content: text, embedding: emb, timestamp: ts,
      meta: originToMeta(origin),
    ))
    if not stored:
      return err("memory graph did not store the entry " & nid)
    ## The only structure kept between memories is their order. Entity and
    ## causal edges came from English sentence patterns and are not written.
    if prevMem.isSome and prevMem.get().nodeType == NtMemory:
      a.graph.linkTemporal(prevMem.get().id, nid)
    ok()

  proc adjacentMemoryId(a: MagmaMemoryAdapter; nodeId, direction: string): string =
    ## Id on the other end of the TEMPORAL edge closest to `nodeId`. Stores
    ## written before insertion-order chaining can hold several edges on one
    ## node; the nearest insertion number is the real neighbour.
    let current = memorySequence(nodeId)
    var bestGap = high(int)
    for edge in a.graph.getEdges(nodeId, edgeType = EdgeTemporal,
                                 direction = direction):
      let otherId = if direction == "in": edge.fromId else: edge.toId
      let other = memorySequence(otherId)
      let gap =
        if current < 0 or other < 0: high(int) - 1
        else: abs(other - current)
      if gap < bestGap:
        bestGap = gap
        result = otherId

  proc dialogueNeighbours(a: MagmaMemoryAdapter; nodeId: string;
                          origin: MemoryOrigin;
                          direction: string): seq[MemoryHit] =
    ## Up to RecallWindowRadius turns of the same session next to `nodeId`,
    ## oldest first. `direction` is "in" for earlier turns, "out" for later
    ## ones. Nodes of another origin or session sit on the same chain and are
    ## skipped, within RecallWindowMaxHops.
    var cursor = nodeId
    var hops = 0
    while result.len < RecallWindowRadius and hops < RecallWindowMaxHops:
      inc hops
      let nextId = a.adjacentMemoryId(cursor, direction)
      if nextId.len == 0:
        break
      let node = a.graph.getNode(nextId)
      if node.isNone:
        break
      cursor = nextId
      let found = node.get()
      let foundOrigin = originFromMeta(found.meta)
      if found.nodeType != NtMemory or not sameDialogue(origin, foundOrigin):
        continue
      let neighbour = MemoryHit(
        content: clipNeighbor(found.content),
        kind: found.nodeType,
        id: found.id,
        timestamp: found.timestamp,
        origin: foundOrigin,
      )
      if direction == "in":
        result.insert(neighbour, 0)
      else:
        result.add(neighbour)

  proc searchWithRerank*(a: MagmaMemoryAdapter;
                         userId: UserId;
                         query: string;
                         limit: int;
                         rerankFnOverride: RerankFn = nil): seq[MemoryHit] =
    ## Hybrid recall: ranked lists by embedding, by literal terms and, for
    ## queries about time, by recency and temporal adjacency are fused by
    ## reciprocal rank. With no embedding available the literal terms alone
    ## still rank.
    type
      RankedMemory = object
        id:          string
        content:     string
        timestamp:   int64
        semanticScore: float
        lexicalScore:  float
        temporalScore: float
        neighborScore: float
        baseScore:   float
        rerankScore: float32
        finalScore:  float32
        kind:        string
        origin:      MemoryOrigin

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
          origin: originFromMeta(n.meta),
        )

    proc addSignal(n: MagmaNode;
                   semantic = 0.0;
                   lexical = 0.0;
                   temporal = 0.0;
                   neighbor = 0.0) =
      ensureNode(n)
      var entry = rankedById[n.id]
      entry.semanticScore += semantic
      entry.lexicalScore += lexical
      entry.temporalScore += temporal
      entry.neighborScore += neighbor
      entry.baseScore = entry.semanticScore + entry.lexicalScore +
                        entry.temporalScore + entry.neighborScore
      rankedById[n.id] = entry

    let semanticHits = a.graph.searchSimilar(uid, emb, topK = semanticTopK)
    for rank, hit in semanticHits:
      if hit.node.nodeType == NtMemory:
        addSignal(hit.node, semantic = rrfScoreWeighted(
          rank, policy.semanticWeight))

    ## Literal terms, over the most recent memory nodes. The candidate read
    ## carries no meta and may clip content, so each ranked node is fetched
    ## whole before it joins the pool.
    let lexicalCandidates = a.graph.listNodesLimited(
      uid, NtMemory, LexicalCandidateLimit, LexicalCandidateContentBytes)
    if lexicalCandidates.isOk:
      var texts = newSeqOfCap[string](lexicalCandidates.get().len)
      for candidate in lexicalCandidates.get():
        texts.add(candidate.content)
      for rank, index in rankTextsLexically(texts, query, semanticTopK):
        let node = a.graph.getNode(lexicalCandidates.get()[index].id)
        if node.isSome and node.get().nodeType == NtMemory:
          addSignal(node.get(), lexical = rrfScoreWeighted(
            rank, policy.lexicalWeight))

    let recentNodes = a.graph.queryByTimeRange(uid, 0, getTime().toUnix() + 1,
                                               limit = recentTopK)
    if policy.intent == qiTemporal:
      for rank, node in recentNodes:
        if node.nodeType == NtMemory:
          addSignal(node, temporal = rrfScoreWeighted(rank, policy.temporalWeight))
      for hit in semanticHits:
        if hit.node.nodeType != NtMemory:
          continue
        let temporalNeighbors = a.graph.traverseNeighbors(
          hit.node.id, edgeTypes = @[EdgeTemporal], maxDepth = 2)
        for rank, neighbor in temporalNeighbors:
          addSignal(neighbor, neighbor = rrfScoreWeighted(rank, policy.neighborWeight))

    if rankedById.len == 0:
      for m in recentNodes:
        if m.nodeType == NtMemory:
          ensureNode(m)

    var rankedMemories: seq[RankedMemory]
    for _, entry in rankedById:
      if entry.kind == NtMemory:
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
          lexicalScore: clampUnit(entry.lexicalScore.float32),
          temporalScore: clampUnit(entry.temporalScore.float32),
          neighborScore: clampUnit(entry.neighborScore.float32),
        )
      let rerankScores = rerankFn(query, candidates)
      if rerankScores.len == rerankCount:
        for i in 0 ..< rerankCount:
          rankedMemories[i].rerankScore = rerankScores[i]
          rankedMemories[i].finalScore = clampUnit(
            rerankScores[i] * a.searchConfig.rerankWeight +
            rankedMemories[i].finalScore * (1.0'f32 - a.searchConfig.rerankWeight)
          )

    let nowSec = getTime().toUnix()
    for i in 0 ..< rankedMemories.len:
      if rankedMemories[i].timestamp > 0:
        rankedMemories[i].finalScore = clampUnit(
          decayedRelevance(rankedMemories[i].finalScore,
                           rankedMemories[i].timestamp, nowSec))

    rankedMemories.sort(proc(x, y: RankedMemory): int =
      let finalCmp = cmp(y.finalScore, x.finalScore)
      if finalCmp != 0:
        return finalCmp
      cmp(y.baseScore, x.baseScore))

    var hits: seq[MemoryHit]
    var expanded = 0
    for entry in rankedMemories:
      if hits.len >= limit:
        break
      var hit = MemoryHit(
        content: entry.content,
        score: entry.finalScore,
        kind: entry.kind,
        id: entry.id,
        timestamp: entry.timestamp,
        origin: entry.origin,
      )
      if expanded < RecallWindowMaxHits and entry.kind == NtMemory and
         entry.origin.source == msTurn and entry.origin.sessionId.len > 0:
        hit.before = a.dialogueNeighbours(entry.id, entry.origin, "in")
        hit.after = a.dialogueNeighbours(entry.id, entry.origin, "out")
        inc expanded
      hits.add(hit)
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
    SearchConfig* = object
      semanticTopKMultiplier*: int
      recentTopKMultiplier*:   int
      rerankPoolSize*:         int
      rerankWeight*:           float32

  func defaultSearchConfig*(): SearchConfig =
    SearchConfig(
      semanticTopKMultiplier: 8,
      recentTopKMultiplier: 4,
      rerankPoolSize: 24,
      rerankWeight: 0.85'f32,
    )
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
  proc appendMemory*(a: MagmaMemoryAdapter; userId: UserId; text: string;
                     origin = MemoryOrigin()): Result[void, string]
                     {.discardable.} = err("no memory graph backend in this build")
  proc loadUserMd*(a: MagmaMemoryAdapter; userId: UserId): string = ""
  proc loadPreferences*(a: MagmaMemoryAdapter; userId: UserId): string = ""
  proc readContext*(a: MagmaMemoryAdapter;
                    userId: UserId): Result[UserContext, string] =
    err("no memory graph backend in this build")
  proc hasContext*(a: MagmaMemoryAdapter;
                   userId: UserId): Result[bool, string] =
    err("no memory graph backend in this build")
  proc savePreferences*(a: MagmaMemoryAdapter; userId: UserId; content: string) = discard
  proc saveCommitment*(a: MagmaMemoryAdapter; userId: UserId; commitment: Commitment) = discard
  proc loadCommitments*(a: MagmaMemoryAdapter; userId: UserId): seq[Commitment] = @[]
  proc saveEpisode*(a: MagmaMemoryAdapter; userId: UserId; episode: EpisodeJournal) = discard
  proc loadEpisodes*(a: MagmaMemoryAdapter; userId: UserId): seq[EpisodeJournal] = @[]
  proc updateCommitmentStatus*(a: MagmaMemoryAdapter;
                               userId: UserId;
                               commitmentId: string;
                               status: CommitmentStatus): bool = false
  proc search*(a: MagmaMemoryAdapter; userId: UserId; query: string; limit: int): seq[MemoryHit] = @[]
  proc toSearchFn*(a: MagmaMemoryAdapter): SearchFn = nil
  proc deleteUser*(a: MagmaMemoryAdapter; userId: UserId) = discard
  proc clearMemory*(a: MagmaMemoryAdapter; userId: UserId) = discard
  proc resetBootstrap*(a: MagmaMemoryAdapter; userId: UserId) = discard
