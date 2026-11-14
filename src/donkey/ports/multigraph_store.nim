## MultigraphStorePort — storage boundary for MAGMA-style graph memory.
##
## This isolates graph-memory semantics from a concrete persistence backend
## such as PostgreSQL or SQLite.

import std/[json, options]

const
  EdgeTemporal* = "TEMPORAL"
  EdgeCausal*   = "CAUSAL"
  EdgeMentions* = "MENTIONS"
  EdgeAbout*    = "ABOUT"

type
  MagmaNode* = object
    id*:        string
    userId*:    string
    nodeType*:  string
    content*:   string
    embedding*: seq[float32]
    timestamp*: int64
    meta*:      JsonNode

  MagmaEdge* = object
    fromId*:   string
    toId*:     string
    edgeType*: string
    weight*:   float64
    meta*:     JsonNode

  MagmaHit* = object
    node*:   MagmaNode
    score*:  float32
    path*:   seq[string]

  MagmaStats* = object
    totalNodes*:      int
    memoryNodes*:     int
    profileNodes*:    int
    preferenceNodes*: int
    entityNodes*:     int
    embeddingNodes*:  int
    totalEdges*:      int

  MultigraphStorePort* = object
    migrate*: proc() {.gcsafe.}
    insertNode*: proc(node: MagmaNode): bool {.gcsafe.}
    upsertNode*: proc(node: MagmaNode) {.gcsafe.}
    getNode*: proc(nodeId: string): Option[MagmaNode] {.gcsafe.}
    listNodes*: proc(userId: string; nodeType: string = ""): seq[MagmaNode] {.gcsafe.}
    listNodesLimited*: proc(userId: string; nodeType: string = "";
                            limit: int): seq[MagmaNode] {.gcsafe.}
    deleteNode*: proc(nodeId: string): bool {.gcsafe.}
    insertEdge*: proc(edge: MagmaEdge): bool {.gcsafe.}
    getEdges*: proc(nodeId: string; edgeType: string = ""; direction: string = "out"): seq[MagmaEdge] {.gcsafe.}
    deleteEdges*: proc(nodeId: string; edgeType: string = ""): int {.gcsafe.}
    getLastNode*: proc(userId: string; nodeType: string = ""): Option[MagmaNode] {.gcsafe.}
    linkTemporal*: proc(fromId, toId: string) {.gcsafe.}
    searchSimilar*: proc(userId: string; embedding: seq[float32]; topK: int = 10; minScore: float32 = 0.0): seq[MagmaHit] {.gcsafe.}
    queryByTimeRange*: proc(userId: string; tsStart, tsEnd: int64; limit: int = 50): seq[MagmaNode] {.gcsafe.}
    traverseNeighbors*: proc(nodeId: string; edgeTypes: seq[string] = @[]; maxDepth: int = 2): seq[MagmaNode] {.gcsafe.}
    statsForUser*: proc(userId: string): MagmaStats {.gcsafe.}
    statsGlobal*: proc(): MagmaStats {.gcsafe.}
