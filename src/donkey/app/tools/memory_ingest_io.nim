## memory_ingest_io.nim — filesystem/IO shell for `memory_ingest`.
##
## The app layer only orchestrates; this module owns path validation, file
## reads, chunking and Result propagation through the memory port.

import std/[os, strutils]
import ../../core/pipeops
import ../../core/types
import ../../domain/memory/ingest_pure
import ../../ports/memory
import ../../ports/fs

type
  MemoryIngestStats* = object
    chunks*:    int
    bytes*:     int
    truncated*: bool
    source*:    string

proc ingestMemoryText*(memory: MemoryRuntimePort; uid: UserId;
                       text, source: string;
                       chunkChars = MaxIngestChunkChars;
                       maxChunks = MaxIngestMaxChunks):
                       Result[MemoryIngestStats, string] =
  if text.strip.len == 0:
    return err("no text to ingest")
  if '\0' in text:
    return err("binary file rejected")
  let chunked = chunkForMemory(text, chunkChars, maxChunks)
  if chunked.chunks.len == 0:
    return err("no text to ingest")
  if chunked.truncated:
    return err("file exceeds the chunk limit; split it before ingesting")
  for chunk in chunked.chunks:
    let saved = memory.appendMemoryChecked(uid, chunk)
    if saved.isErr:
      return err(saved.error)
  ok(MemoryIngestStats(
    chunks: chunked.chunks.len,
    bytes: text.len,
    truncated: false,
    source: source,
  ))

proc ingestMemoryFile*(memory: MemoryRuntimePort; uid: UserId;
                       paddockDir, path: string;
                       chunkChars = MaxIngestChunkChars;
                       maxChunks = MaxIngestMaxChunks;
                       fs: FsRuntimePort = unavailableFs()):
                       Result[MemoryIngestStats, string] =
  if paddockDir.len == 0:
    return err("memory workspace unavailable")
  let paddock = paddockDir
  let candidate = if path.isAbsolute: path else: paddock / path
  let realPaddock = fs.canonicalPath(paddock).valueOr:
    return err(error)
  let realFile = fs.canonicalPath(candidate).valueOr:
    return err(error)
  if realFile != realPaddock and
     not realFile.startsWith(realPaddock & $DirSep):
    return err("path outside paddock: " & path)
  if not fileExists(realFile) or dirExists(realFile):
    return err("file not found: " & path)
  let size = fs.fileSize(realFile).valueOr:
    return err(error)
  if size > 2_000_000:
    return err("file exceeds the 2 MB ingest limit")
  let text = fs.readFile(realFile).valueOr:
    return err(error)
  ingestMemoryText(memory, uid, text, path, chunkChars, maxChunks)
