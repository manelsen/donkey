## t_embedder.nim - tests for core/memory/embedder.nim

import std/[unittest, strutils, sequtils]
import donkey/core/pipeops
import donkey/core/memory/embedder
import donkey/domain/memory/chunking
import donkey/ports/embedding

suite "embedder - EmbeddedChunk construction":

  test "newEmbeddedChunk from ChunkWithHash":
    let cwh = ChunkWithHash(chunk: "hello world", hash: "abc123", index: 0, offset: 0)
    let vec = @[1.0'f32, 2.0'f32, 3.0'f32]
    let ec = newEmbeddedChunk(cwh, vec)
    check ec.chunk == "hello world"
    check ec.hash == "abc123"
    check ec.index == 0
    check ec.offset == 0
    check ec.vector == vec
    check ec.dimensions == 3

  test "newEmbeddedChunk from individual fields":
    let ec = newEmbeddedChunk("test", "xyz789", 2, 50, @[0.1'f32, 0.2'f32])
    check ec.chunk == "test"
    check ec.hash == "xyz789"
    check ec.index == 2
    check ec.offset == 50
    check ec.vector == @[0.1'f32, 0.2'f32]
    check ec.dimensions == 2

  test "dimensions reflects vector.len":
    let cwh = ChunkWithHash(chunk: "x", hash: "y", index: 0, offset: 0)
    let ec1 = newEmbeddedChunk(cwh, @[1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32])
    check ec1.dimensions == 4

  test "empty vector has dimensions 0":
    let cwh = ChunkWithHash(chunk: "x", hash: "y", index: 0, offset: 0)
    let ec = newEmbeddedChunk(cwh, @[])
    check ec.dimensions == 0

suite "embedder - embedChunk with EmbedFn":

  test "embedChunk succeeds with valid embedding":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      if t == "hello":
        @[1.0'f32, 0.0'f32, 0.5'f32]
      else:
        @[]
    let cwh = ChunkWithHash(chunk: "hello", hash: "abc", index: 0, offset: 0)
    let result = cwh.embedChunk(fn)
    check result.isOk
    check result.get().chunk == "hello"
    check result.get().vector == @[1.0'f32, 0.0'f32, 0.5'f32]

  test "embedChunk fails with empty embedding":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let cwh = ChunkWithHash(chunk: "hello", hash: "abc", index: 0, offset: 0)
    let result = cwh.embedChunk(fn)
    check result.isErr
    check "embedding failed" in result.error

  test "embedChunk from raw fields succeeds":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      @[1.0'f32, 2.0'f32]
    let result = "hello".embedChunk("abc", 1, 10, fn)
    check result.isOk
    check result.get().chunk == "hello"
    check result.get().index == 1
    check result.get().offset == 10

  test "embedChunk from raw fields fails on empty vector":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let result = "hello".embedChunk("abc", 1, 10, fn)
    check result.isErr

suite "embedder - embedChunks with seq[ChunkWithHash]":

  test "embedChunks succeeds for multiple chunks":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      if t == "chunk1":
        @[1.0'f32, 0.0'f32]
      elif t == "chunk2":
        @[0.0'f32, 1.0'f32]
      else:
        @[]
    let chunks = @[
      ChunkWithHash(chunk: "chunk1", hash: "h1", index: 0, offset: 0),
      ChunkWithHash(chunk: "chunk2", hash: "h2", index: 1, offset: 10),
    ]
    let result = chunks.embedChunks(fn)
    check result.isOk
    check result.get().len == 2
    check result.get()[0].vector == @[1.0'f32, 0.0'f32]
    check result.get()[1].vector == @[0.0'f32, 1.0'f32]

  test "embedChunks fails on first error":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      if t == "chunk1":
        @[1.0'f32]
      else:
        @[]
    let chunks = @[
      ChunkWithHash(chunk: "chunk1", hash: "h1", index: 0, offset: 0),
      ChunkWithHash(chunk: "chunk2", hash: "h2", index: 1, offset: 10),
    ]
    let result = chunks.embedChunks(fn)
    check result.isErr
    check "embedding failed" in result.error

  test "embedChunks empty seq returns empty":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let result = @[].embedChunks(fn)
    check result.isOk
    check result.get().len == 0

suite "embedder - embedText full pipeline":

  test "embedText chunks and embeds":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      if t.len > 0:
        @[1.0'f32, 2.0'f32]
      else:
        @[]
    let result = "hello world test".embedText(fn, maxLen = 1000, overlap = 200)
    check result.isOk
    let chunks = result.get()
    check chunks.len >= 1
    for c in chunks:
      check c.vector == @[1.0'f32, 2.0'f32]
      check c.dimensions == 2
      check c.hash == c.chunk.sha256Hash

  test "embedText fails on embed error":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let result = "hello".embedText(fn, maxLen = 1000, overlap = 200)
    check result.isErr

  test "embedText empty string returns empty":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let result = "".embedText(fn)
    check result.isOk
    check result.get().len == 0

  test "embedText preserves chunk metadata":
    let fn: EmbedFn = proc(t: string): seq[float32] =
      if t.len > 0:
        @[0.5'f32]
      else:
        @[]
    let result = "hello world".embedText(fn, maxLen = 5, overlap = 1)
    check result.isOk
    let chunks = result.get()
    check chunks.len > 0
    for ec in chunks:
      check ec.index >= 0
      check ec.offset >= 0
      check ec.hash == ec.chunk.sha256Hash

suite "embedder - helper functions":

  test "emptyEmbedding creates zero vector":
    let vec = emptyEmbedding(4096)
    check vec.len == 4096
    for v in vec:
      check v == 0.0'f32

  test "emptyEmbedding zero dimensions":
    let vec = emptyEmbedding(0)
    check vec.len == 0

  test "totalDimensions sums across chunks":
    let chunks = @[
      newEmbeddedChunk("a", "h", 0, 0, @[1.0'f32, 2.0'f32]),
      newEmbeddedChunk("b", "h", 1, 10, @[3.0'f32, 4.0'f32, 5.0'f32]),
    ]
    check chunks.totalDimensions == 5

  test "totalDimensions empty seq":
    let emptyChunks: seq[EmbeddedChunk] = @[]
    check emptyChunks.totalDimensions == 0

  test "hasValidEmbedding true for non-empty vector":
    let ec = newEmbeddedChunk("x", "h", 0, 0, @[1.0'f32])
    check ec.hasValidEmbedding

  test "hasValidEmbedding false for empty vector":
    let ec = newEmbeddedChunk("x", "h", 0, 0, @[])
    check not ec.hasValidEmbedding

suite "embedder - EmbeddingPort concept satisfaction":

  test "EmbedFn works as embedding function":
    var called = false
    let fn: EmbedFn = proc(t: string): seq[float32] =
      called = true
      @[1.0'f32]
    let vec = fn("test")
    check called
    check vec == @[1.0'f32]

  test "EmbedFn returns empty on error":
    let fn: EmbedFn = proc(t: string): seq[float32] = @[]
    let vec = fn("any string")
    check vec.len == 0
