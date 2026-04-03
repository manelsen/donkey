## knowledge_library_pure — document knowledge separate from autobiographical memory.
## Pure functions only. No I/O.

import std/[algorithm, sets, strutils, sequtils]

type
  KnowledgeCollection* = object
    id*:            string
    title*:         string
    allowedAgents*: seq[string]

  KnowledgeDocument* = object
    id*:           string
    collectionId*: string
    title*:        string
    mimeType*:     string

  KnowledgeChunk* = object
    id*:           string
    documentId*:   string
    collectionId*: string
    ordinal*:      int
    text*:         string
    sheetName*:    string

  KnowledgeIngestion* = object
    document*: KnowledgeDocument
    chunks*:   seq[KnowledgeChunk]

  KnowledgeSearchHit* = object
    chunk*:         KnowledgeChunk
    documentTitle*: string
    score*:         float32
    citation*:      string

func newKnowledgeCollection*(id, title: string;
                             allowedAgents: seq[string]): KnowledgeCollection =
  KnowledgeCollection(id: id, title: title, allowedAgents: allowedAgents)

func newKnowledgeDocument*(id, collectionId, title, mimeType: string): KnowledgeDocument =
  KnowledgeDocument(
    id: id,
    collectionId: collectionId,
    title: title,
    mimeType: mimeType,
  )

func newKnowledgeChunk*(id: string;
                        document: KnowledgeDocument;
                        ordinal: int;
                        text: string;
                        sheetName = ""): KnowledgeChunk =
  KnowledgeChunk(
    id: id,
    documentId: document.id,
    collectionId: document.collectionId,
    ordinal: ordinal,
    text: text,
    sheetName: sheetName,
  )

func canAccess*(agentId: string; collection: KnowledgeCollection): bool =
  agentId in collection.allowedAgents

proc accessibleChunks*(agentId: string;
                       collections: seq[KnowledgeCollection];
                       chunks: seq[KnowledgeChunk]): seq[KnowledgeChunk] =
  var allowed = initHashSet[string]()
  for collection in collections:
    if canAccess(agentId, collection):
      allowed.incl(collection.id)
  for chunk in chunks:
    if chunk.collectionId in allowed:
      result.add(chunk)

proc splitIntoChunks*(text: string; chunkSize = 400): seq[string] =
  let normalized = text.splitWhitespace().join(" ")
  if normalized.len == 0:
    return @[]
  var start = 0
  while start < normalized.len:
    let stop = min(start + max(chunkSize, 1), normalized.len)
    result.add(normalized[start ..< stop].strip())
    start = stop

proc ingestPdfDocument*(collection: KnowledgeCollection;
                        documentId, title, extractedText: string;
                        chunkSize = 400): KnowledgeIngestion =
  result.document = newKnowledgeDocument(documentId, collection.id, title, "application/pdf")
  let parts = splitIntoChunks(extractedText, chunkSize)
  for idx, part in parts:
    result.chunks.add(newKnowledgeChunk(
      documentId & "-chunk-" & $idx,
      result.document,
      idx,
      part,
    ))

proc ingestDocxDocument*(collection: KnowledgeCollection;
                         documentId, title, extractedText: string;
                         chunkSize = 400): KnowledgeIngestion =
  result.document = newKnowledgeDocument(
    documentId,
    collection.id,
    title,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  )
  let parts = splitIntoChunks(extractedText, chunkSize)
  for idx, part in parts:
    result.chunks.add(newKnowledgeChunk(
      documentId & "-chunk-" & $idx,
      result.document,
      idx,
      part,
    ))

proc ingestXlsxDocument*(collection: KnowledgeCollection;
                         documentId, title: string;
                         sheets: seq[(string, string)];
                         chunkSize = 400): KnowledgeIngestion =
  result.document = newKnowledgeDocument(
    documentId,
    collection.id,
    title,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  )
  var ordinal = 0
  for sheet in sheets:
    let sheetName = sheet[0]
    let extractedText = sheet[1]
    let parts = splitIntoChunks(extractedText, chunkSize)
    for part in parts:
      result.chunks.add(newKnowledgeChunk(
        documentId & "-chunk-" & $ordinal,
        result.document,
        ordinal,
        part,
        sheetName = sheetName,
      ))
      inc ordinal

func queryTokens(query: string): seq[string] =
  query.toLowerAscii().splitWhitespace().filterIt(it.len > 1)

func chunkScore(query: string; chunk: KnowledgeChunk): float32 =
  let lowered = chunk.text.toLowerAscii()
  let tokens = queryTokens(query)
  if tokens.len == 0:
    return 0.0'f32
  for token in tokens:
    if lowered.contains(token):
      result += 1.0'f32
  if lowered.contains(query.toLowerAscii()):
    result += 0.5'f32

proc searchKnowledgeLibrary*(query, agentId: string;
                             collections: seq[KnowledgeCollection];
                             documents: seq[KnowledgeDocument];
                             chunks: seq[KnowledgeChunk];
                             limit = 5): seq[KnowledgeSearchHit] =
  let accessible = accessibleChunks(agentId, collections, chunks)
  for chunk in accessible:
    let score = chunkScore(query, chunk)
    if score <= 0.0'f32:
      continue
    let doc = documents.filterIt(it.id == chunk.documentId)
    let title = if doc.len > 0: doc[0].title else: chunk.documentId
    result.add(KnowledgeSearchHit(
      chunk: chunk,
      documentTitle: title,
      score: score,
      citation: title & "#" & $chunk.ordinal,
    ))
  result.sort(proc(x, y: KnowledgeSearchHit): int =
    let scoreCmp = cmp(y.score, x.score)
    if scoreCmp != 0: scoreCmp else: cmp(x.citation, y.citation)
  )
  if result.len > limit:
    result.setLen(limit)

proc buildMixedRetrievalContext*(autobiographicalMemories: seq[string];
                                 knowledgeHits: seq[KnowledgeSearchHit]): string =
  var parts: seq[string]
  if autobiographicalMemories.len > 0:
    parts.add("Relevant memories:\n- " & autobiographicalMemories.join("\n- "))
  if knowledgeHits.len > 0:
    var lines: seq[string]
    for hit in knowledgeHits:
      lines.add("- [" & hit.documentTitle & "] " & hit.chunk.text)
    parts.add("Knowledge library:\n" & lines.join("\n"))
  parts.join("\n\n")
