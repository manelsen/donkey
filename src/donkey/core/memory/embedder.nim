## embedder.nim - Embedding Pipeline.
##
## Coordinates text chunking with embedding providers to produce
## vector-indexed chunks ready for pgvector storage.

import std/sequtils
import ../../core/pipeops
import ../../domain/memory/chunking
import ../../ports/embedding

type
  EmbeddedChunk* = object
    chunk*:     string
    hash*:      string
    index*:     int
    offset*:    int
    vector*:    seq[float32]
    dimensions*: int

const
  DefaultEmbeddingDimensions* = 4096

func newEmbeddedChunk*(chunk: ChunkWithHash; vector: seq[float32]): EmbeddedChunk =
  EmbeddedChunk(
    chunk:     chunk.chunk,
    hash:      chunk.hash,
    index:     chunk.index,
    offset:    chunk.offset,
    vector:    vector,
    dimensions: vector.len,
  )

func newEmbeddedChunk*(chunk: string; hash: string; index: int; offset: int;
                       vector: seq[float32]): EmbeddedChunk =
  EmbeddedChunk(
    chunk:     chunk,
    hash:      hash,
    index:     index,
    offset:    offset,
    vector:    vector,
    dimensions: vector.len,
  )

proc embedChunk*(chunk: ChunkWithHash; fn: EmbedFn): Result[EmbeddedChunk, string] =
  let vec = fn(chunk.chunk)
  if vec.len == 0:
    err("embedding failed for chunk " & $chunk.index & " (hash=" & chunk.hash & ")")
  else:
    ok(newEmbeddedChunk(chunk, vec))

proc embedChunk*(chunk: string; hash: string; index: int; offset: int;
                 fn: EmbedFn): Result[EmbeddedChunk, string] =
  let vec = fn(chunk)
  if vec.len == 0:
    err("embedding failed for chunk " & $index & " (hash=" & hash & ")")
  else:
    ok(newEmbeddedChunk(chunk, hash, index, offset, vec))

proc embedChunks*(chunks: seq[ChunkWithHash]; fn: EmbedFn): Result[seq[EmbeddedChunk], string] =
  ## Embeds chunks, skipping empty chunks silently.
  ## Empty chunks have no semantic content and would fail embedding anyway.
  var results: seq[EmbeddedChunk] = @[]
  for c in chunks:
    if c.chunk.len == 0:
      continue
    let embedded = c.embedChunk(fn)
    if embedded.isErr:
      return err(embedded.error)
    results.add(embedded.get())
  ok(results)

proc embedText*(text: string;
                fn: EmbedFn;
                maxLen = DefaultMaxChunkLen;
                overlap = DefaultOverlap): Result[seq[EmbeddedChunk], string] =
  text
    .chunkTextWithHash(maxLen, overlap)
    .embedChunks(fn)

func emptyEmbedding*(dimensions: int): seq[float32] =
  newSeq[float32](dimensions)

func totalDimensions*(chunks: seq[EmbeddedChunk]): int =
  chunks.foldl(a + b.dimensions, 0)

func hasValidEmbedding*(c: EmbeddedChunk): bool =
  c.vector.len > 0
