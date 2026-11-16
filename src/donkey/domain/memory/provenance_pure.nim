## provenance_pure — where a stored memory came from.
##
## Every memory node used to be written with empty meta, so a captured
## dialogue turn, an ingested document chunk and a consolidated fact were
## indistinguishable at recall time. The origin is recorded in the node meta
## under stable keys; nodes written before this module read as `msUnknown`.
## No I/O.

import std/json

const
  OriginSourceKey*  = "source"
  OriginSessionKey* = "session_id"

type
  MemorySource* = enum
    msUnknown       = "unknown"        ## legacy node or backend without origin
    msTurn          = "turn"           ## one captured user/assistant exchange
    msIngest        = "ingest"         ## chunk written by `memory_ingest`
    msConsolidation = "consolidation"  ## facts extracted at /compact, /reset, /new
    msMarkdown      = "markdown"       ## paragraph imported from MEMORY.md

  MemoryOrigin* = object
    source*:    MemorySource
    sessionId*: string   ## session that produced the memory; empty if none

func turnOrigin*(sessionId: string): MemoryOrigin =
  MemoryOrigin(source: msTurn, sessionId: sessionId)

func parseMemorySource*(raw: string): MemorySource =
  for candidate in MemorySource:
    if candidate != msUnknown and $candidate == raw:
      return candidate
  msUnknown

func originToMeta*(origin: MemoryOrigin): JsonNode =
  ## Unknown origin writes `{}`, so untagged writes stay byte-identical to
  ## what the store held before.
  result = newJObject()
  if origin.source != msUnknown:
    result[OriginSourceKey] = %($origin.source)
  if origin.sessionId.len > 0:
    result[OriginSessionKey] = %origin.sessionId

func originFromMeta*(meta: JsonNode): MemoryOrigin =
  if meta.isNil or meta.kind != JObject:
    return
  let source = meta.getOrDefault(OriginSourceKey)
  if not source.isNil and source.kind == JString:
    result.source = parseMemorySource(source.getStr)
  let session = meta.getOrDefault(OriginSessionKey)
  if not session.isNil and session.kind == JString:
    result.sessionId = session.getStr

func sameDialogue*(a, b: MemoryOrigin): bool =
  ## True when both memories are turns of the same, identified session.
  a.source == msTurn and b.source == msTurn and
    a.sessionId.len > 0 and a.sessionId == b.sessionId
