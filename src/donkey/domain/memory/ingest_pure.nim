## ingest_pure.nim — bounded, UTF-8-safe chunking for memory ingestion.
##
## No I/O. The caller reads the file, enforces size/type limits, and appends
## each returned chunk to the memory port.

import std/strutils

const
  DefaultIngestChunkChars* = 2_000
  MinIngestChunkChars*     = 500
  MaxIngestChunkChars*     = 8_000
  DefaultIngestMaxChunks*  = 100
  MaxIngestMaxChunks*      = 500

func clampChunkChars*(value: int): int =
  if value <= 0: DefaultIngestChunkChars
  elif value < MinIngestChunkChars: MinIngestChunkChars
  elif value > MaxIngestChunkChars: MaxIngestChunkChars
  else: value

func clampMaxChunks*(value: int): int =
  if value <= 0: DefaultIngestMaxChunks
  elif value < 1: 1
  elif value > MaxIngestMaxChunks: MaxIngestMaxChunks
  else: value

func isUtf8ContinuationByte(ch: char): bool =
  (ord(ch) and 0xC0) == 0x80

func chunkForMemory*(text: string;
                     chunkChars = DefaultIngestChunkChars;
                     maxChunks = DefaultIngestMaxChunks):
                     tuple[chunks: seq[string], truncated: bool] =
  ## Splits text at newline boundaries when possible, never in the middle of a
  ## UTF-8 code point, and stops after maxChunks non-empty chunks.
  let cap = clampChunkChars(chunkChars)
  let limit = clampMaxChunks(maxChunks)
  if text.len == 0:
    return (newSeq[string](), false)

  var chunks: seq[string] = @[]
  var i = 0
  while i < text.len and chunks.len < limit:
    var endIdx = min(text.len, i + cap)
    if endIdx < text.len:
      let newline = text.rfind('\n', i, endIdx - 1)
      if newline >= i + max(1, cap div 2):
        endIdx = newline + 1
      else:
        while endIdx > i and isUtf8ContinuationByte(text[endIdx]):
          dec endIdx
    if endIdx <= i:
      endIdx = min(text.len, i + 1)
    let piece = text[i ..< endIdx].strip
    if piece.len > 0:
      chunks.add(piece)
    i = endIdx

  (chunks, i < text.len)
