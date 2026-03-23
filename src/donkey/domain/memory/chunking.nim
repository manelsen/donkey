## chunking.nim — Text chunking with overlap and SHA256 hashing.
##
## Pure logic to split text into overlapping chunks and compute SHA256 hashes,
## in the style of openclaw workspace memory indexing.
##
## Usage:
##   text
##     |> chunkText(maxLen = 1000, overlap = 200)
##     |> mapIt(it.sha256Hash)
##
##   text
##     |> chunkTextWithHash(1000, 200)
##     |> mapIt((it.chunk, it.hash))

import std/[strutils, sequtils]
import nimcrypto/sha2
import ../../core/pipeops

type
  ChunkWithHash* = object
    chunk*: string
    hash*: string
    index*: int
    offset*: int

const
  DefaultMaxChunkLen* = 1000
  DefaultOverlap* = 200
  MinChunkLen* = 100

func sha256Hash*(text: string): string =
  ## Computes SHA256 hex digest of a string.
  var ctx: sha256
  ctx.init()
  ctx.update(text)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())
  ctx.clear()

func isSignificantBoundary*(text: string; pos: int): bool =
  ## Checks if position is a good chunk boundary.
  ## Prefers newline > space > hard cut.
  if pos <= 0 or pos >= text.len:
    return false
  case text[pos]
  of '\n', '\r':
    true
  of ' ', '\t', ',', ';', '.':
    # Prefer boundaries after these chars (so they are included)
    true
  else:
    false

func findBoundaryBack*(text: string; start, stop: int): int =
  ## Finds the best boundary in [stop-maxLen, stop] searching backwards.
  ## Returns -1 if no good boundary found.
  var best = -1
  for i in countdown(stop - 1, max(start, stop - DefaultMaxChunkLen)):
    if text.isSignificantBoundary(i):
      best = i
      break
  best

func findBoundaryForward*(text: string; start, stop: int): int =
  ## Finds the best boundary in [start, start+maxLen] searching forward.
  ## Returns -1 if no good boundary found.
  var best = -1
  for i in countup(start, min(stop, text.len - 1)):
    if text.isSignificantBoundary(i):
      best = i
      # Keep going to find the latest boundary
  best

func chunkTextNoOverlap*(text: string; maxLen: int): seq[string] =
  ## Splits text into non-overlapping chunks of at most maxLen.
  ## Uses splitChunks from pipeops as foundation.
  if text.len == 0:
    return @[]
  text.splitChunks(maxLen)

func chunkTextWithOverlap*(text: string; maxLen: int; overlap: int): seq[string] =
  ## Splits text into overlapping chunks of at most maxLen characters,
  ## with approximately `overlap` characters shared between adjacent chunks.
  ##
  ## Overlap is adjusted to fall on word boundaries when possible.
  if text.len == 0:
    return @[]
  if text.len <= maxLen:
    return @[text]

  let effectiveOverlap = min(overlap, maxLen div 2)
  let step = maxLen - effectiveOverlap
  var pos = 0
  var index = 0

  while pos < text.len:
    let remaining = text.len - pos
    if remaining <= maxLen:
      # Last chunk - take all remaining
      result.add(text[pos .. ^1])
      break

    # Find boundary for this chunk
    let chunkEnd = pos + maxLen
    var boundary = text.findBoundaryBack(pos, chunkEnd)

    if boundary < 0:
      # No good boundary - hard cut
      boundary = chunkEnd

    result.add(text[pos ..< boundary])
    pos = max(pos + step, boundary)
    inc index

func chunkText*(text: string; maxLen: int; overlap: int): seq[string] =
  ## Splits text into overlapping chunks (convenience wrapper).
  ## Uses DefaultMaxChunkLen and DefaultOverlap when not specified.
  text.chunkTextWithOverlap(maxLen, overlap)

func chunkText*(text: string; maxLen: int): seq[string] =
  ## Splits text into non-overlapping chunks.
  text.chunkTextNoOverlap(maxLen)

func chunkTextWithHashNoOverlap*(text: string; maxLen: int): seq[ChunkWithHash] =
  ## Chunks text without overlap and computes SHA256 for each chunk.
  let chunks = text.chunkTextNoOverlap(maxLen)
  for i, chunk in chunks:
    result.add(ChunkWithHash(
      chunk: chunk,
      hash: chunk.sha256Hash,
      index: i,
      offset: 0
    ))

func chunkTextWithOverlapPos*(text: string; maxLen: int; overlap: int): seq[(string, int)] =
  ## Splits text into overlapping chunks with their starting positions.
  if text.len == 0:
    return @[]
  if text.len <= maxLen:
    return @[(text, 0)]

  let effectiveOverlap = min(overlap, maxLen div 2)
  let step = maxLen - effectiveOverlap
  var pos = 0
  var index = 0

  while pos < text.len:
    let remaining = text.len - pos
    if remaining <= maxLen:
      result.add((text[pos .. ^1], pos))
      break

    let chunkEnd = pos + maxLen
    var boundary = text.findBoundaryBack(pos, chunkEnd)

    if boundary < 0:
      boundary = chunkEnd

    result.add((text[pos ..< boundary], pos))
    pos = max(pos + step, boundary)
    inc index

func chunkTextWithHash*(text: string; maxLen: int; overlap: int): seq[ChunkWithHash] =
  ## Chunks text with overlap and computes SHA256 for each chunk.
  if text.len == 0:
    return @[]
  if text.len <= maxLen:
    return @[ChunkWithHash(chunk: text, hash: text.sha256Hash, index: 0, offset: 0)]

  let chunksWithPos = text.chunkTextWithOverlapPos(maxLen, overlap)
  for i, (chunk, offset) in chunksWithPos:
    result.add(ChunkWithHash(
      chunk: chunk,
      hash: chunk.sha256Hash,
      index: i,
      offset: offset
    ))

func hashChunks*(chunks: seq[string]): seq[string] =
  ## Computes SHA256 hash for each chunk in sequence.
  chunks.mapIt(it.sha256Hash)

func chunkAndHash*(text: string; maxLen: int; overlap: int): seq[ChunkWithHash] =
  ## Full chunk + hash pipeline (convenience).
  text.chunkTextWithHash(maxLen, overlap)

func totalCharCount*(chunks: seq[ChunkWithHash]): int =
  ## Sum of all chunk lengths.
  chunks.foldl(a + b.chunk.len, 0)

func deduplicateByHash*(chunks: seq[ChunkWithHash]): seq[ChunkWithHash] =
  ## Removes duplicate chunks by hash (keeps first occurrence).
  var seen: seq[string] = @[]
  var outChunks: seq[ChunkWithHash] = @[]
  for chunk in chunks:
    if chunk.hash notin seen:
      seen.add(chunk.hash)
      outChunks.add(chunk)
  outChunks
