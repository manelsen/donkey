## The memory graph statistics as SQL, shared by the PostgreSQL store
## (`magma_graph`) and the SQLite one (`sqlite_magma_store`): the same counts
## over the same columns, the stores differ only in table names and in how
## an embedding is told present.

import std/strutils
import ../../ports/multigraph_store

func nodeStatsSql*(nodesTable, hasEmbedding: string; perUser: bool): string =
  ## One row: all nodes, then memory, profile, preference and entity nodes,
  ## then nodes with an embedding (`hasEmbedding` is a SQL boolean expression).
  ## With `perUser`, one `?` parameter: the user id.
  "SELECT COUNT(*), " &
  "COALESCE(SUM(CASE WHEN node_type = 'memory' THEN 1 ELSE 0 END), 0), " &
  "COALESCE(SUM(CASE WHEN node_type = 'user_profile' THEN 1 ELSE 0 END), 0), " &
  "COALESCE(SUM(CASE WHEN node_type = 'preference' THEN 1 ELSE 0 END), 0), " &
  "COALESCE(SUM(CASE WHEN node_type = 'entity' THEN 1 ELSE 0 END), 0), " &
  "COALESCE(SUM(CASE WHEN " & hasEmbedding & " THEN 1 ELSE 0 END), 0) " &
  "FROM " & nodesTable & (if perUser: " WHERE user_id = ?" else: "")

func edgeCountSql*(edgesTable, nodesTable: string; perUser: bool): string =
  ## Edges, or with `perUser` (one `?`) the edges leaving the user's nodes.
  if perUser:
    "SELECT COUNT(*) FROM " & edgesTable & " e JOIN " & nodesTable &
      " n ON e.from_id = n.id WHERE n.user_id = ?"
  else:
    "SELECT COUNT(*) FROM " & edgesTable

func parseCount*(raw: string): int =
  ## A count column; 0 when empty or not a number.
  try: parseInt(raw) except ValueError: 0

func nodeStatsFromRow*(row: seq[string]): MagmaStats =
  ## The node counts of a `nodeStatsSql` row (edges are counted apart).
  if row.len < 6: return
  MagmaStats(
    totalNodes:      parseCount(row[0]),
    memoryNodes:     parseCount(row[1]),
    profileNodes:    parseCount(row[2]),
    preferenceNodes: parseCount(row[3]),
    entityNodes:     parseCount(row[4]),
    embeddingNodes:  parseCount(row[5]),
  )
