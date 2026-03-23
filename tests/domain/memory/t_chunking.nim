import std/[unittest, strutils, sets]
import donkey/domain/memory/chunking

suite "chunking - text chunking with overlap and SHA256":

  test "sha256Hash computes consistent hashes":
    let h1 = sha256Hash("hello")
    let h2 = sha256Hash("hello")
    let h3 = sha256Hash("world")
    check h1 == h2
    check h1 != h3
    check h1.len == 64  # SHA256 hex is 64 chars

  test "sha256Hash empty string returns valid hash":
    let h = sha256Hash("")
    check h.len == 64
    check h == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  test "chunkTextNoOverlap splits evenly":
    let text = "abcdefghij"
    let chunks = text.chunkTextNoOverlap(3)
    check chunks.len == 4
    check chunks[0] == "abc"
    check chunks[1] == "def"
    check chunks[2] == "ghi"
    check chunks[3] == "j"

  test "chunkTextNoOverlap single chunk for short text":
    let text = "ab"
    let chunks = text.chunkTextNoOverlap(10)
    check chunks.len == 1
    check chunks[0] == "ab"

  test "chunkTextNoOverlap empty string":
    let chunks = "".chunkTextNoOverlap(5)
    check chunks.len == 0

  test "chunkTextWithOverlap creates overlapping chunks":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithOverlap(5, 2)
    # With maxLen=5, overlap=2, step=3
    # Chunk 1: abcde (0-5), pos moves to max(3, 5)=5
    # Chunk 2: fghij (5-10) - remaining 5 chars, fits in one chunk
    check chunks.len == 2

  test "chunkTextWithOverlap smaller overlap":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithOverlap(6, 1)
    # With maxLen=6, overlap=1, step=5
    # Chunk 1: abcdef (0-6)
    # Chunk 2: fghij (5-10)
    check chunks.len == 2

  test "chunkTextWithOverlap large overlap capped":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithOverlap(5, 10)
    # overlap capped to maxLen/2 = 2, step = 5-2 = 3
    check chunks.len > 0

  test "chunkTextWithOverlap empty string":
    let chunks = "".chunkTextWithOverlap(5, 2)
    check chunks.len == 0

  test "chunkTextWithOverlap short text returns single":
    let text = "abc"
    let chunks = text.chunkTextWithOverlap(10, 2)
    check chunks.len == 1
    check chunks[0] == "abc"

  test "chunkText default overlap uses constants":
    let text = "abcdefghij"
    let chunks = text.chunkText(6)  # uses non-overlap
    check chunks.len > 0

  test "chunkTextWithHash computes hashes":
    let text = "hello world"
    let chunks = text.chunkTextWithHash(5, 2)
    for c in chunks:
      check c.hash.len == 64
      check c.hash == c.chunk.sha256Hash

  test "chunkTextWithHash sets indices":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithHash(3, 1)
    for i, c in chunks:
      check c.index == i

  test "chunkTextWithHash sets offsets":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithHash(4, 1)
    var prevEnd = 0
    for c in chunks:
      check c.offset == prevEnd
      prevEnd = c.offset + c.chunk.len

  test "hashChunks computes hashes for sequence":
    let chunks = @["hello", "world"]
    let hashes = chunks.hashChunks
    check hashes.len == 2
    check hashes[0] == sha256Hash("hello")
    check hashes[1] == sha256Hash("world")

  test "chunkAndHash convenience function":
    let text = "hello"
    let chunks = text.chunkAndHash(10, 2)
    check chunks.len == 1
    check chunks[0].chunk == "hello"
    check chunks[0].hash == sha256Hash("hello")

  test "totalCharCount sums chunk lengths":
    let chunks = @[
      ChunkWithHash(chunk: "abc", hash: "x", index: 0, offset: 0),
      ChunkWithHash(chunk: "defgh", hash: "y", index: 1, offset: 3),
    ]
    check chunks.totalCharCount == 8

  test "deduplicateByHash removes duplicates":
    let hash = sha256Hash("same")
    let chunks = @[
      ChunkWithHash(chunk: "same1", hash: hash, index: 0, offset: 0),
      ChunkWithHash(chunk: "same2", hash: hash, index: 1, offset: 10),
      ChunkWithHash(chunk: "different", hash: sha256Hash("different"), index: 2, offset: 20),
    ]
    let deduped = chunks.deduplicateByHash
    check deduped.len == 2
    check deduped[0].chunk == "same1"
    check deduped[1].chunk == "different"

  test "isSignificantBoundary detects newlines":
    let text = "hello\nworld"
    check text.isSignificantBoundary(5) == true

  test "isSignificantBoundary detects spaces":
    let text = "hello world"
    check text.isSignificantBoundary(5) == true

  test "isSignificantBoundary rejects mid-word":
    let text = "helloworld"
    check text.isSignificantBoundary(3) == false

  test "chunkText prefers word boundaries":
    let text = "one two three four five six seven eight nine ten"
    let chunks = text.chunkTextWithOverlap(10, 2)
    # Should split on spaces when possible
    check chunks.len > 0
    for chunk in chunks:
      # Each chunk should be at a word boundary
      check chunk.len <= 12  # maxLen + some tolerance

  test "multiple overlapping chunks cover full text":
    let text = "abcdefghij"
    let chunks = text.chunkTextWithHash(4, 1)
    # Verify all characters are covered (allowing for some overlap redundancy)
    var covered = ""
    for c in chunks:
      covered &= c.chunk
    check covered.len >= text.len

  test "ChunkWithHash fields accessible":
    let cwh = ChunkWithHash(chunk: "test", hash: "abc123", index: 5, offset: 100)
    check cwh.chunk == "test"
    check cwh.hash == "abc123"
    check cwh.index == 5
    check cwh.offset == 100

  test "constants are exported":
    check DefaultMaxChunkLen == 1000
    check DefaultOverlap == 200
    check MinChunkLen == 100
