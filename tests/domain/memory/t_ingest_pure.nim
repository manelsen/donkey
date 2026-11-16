import std/[strutils, unicode, unittest]
import donkey/domain/memory/ingest_pure

suite "memory ingest chunking":

  test "splits long text into bounded chunks":
    let text = repeat("linha de teste\n", 500)
    let result = chunkForMemory(text, 1000, 100)
    check result.chunks.len > 1
    check result.truncated == false
    for chunk in result.chunks:
      check chunk.len <= 1000
      check "linha de teste" in chunk

  test "respects maxChunks and reports truncation":
    let text = repeat("abcdefghij\n", 500)
    let result = chunkForMemory(text, 500, 2)
    check result.chunks.len == 2
    check result.truncated

  test "clamps tiny chunk size to the minimum":
    let result = chunkForMemory(repeat("x", 400), 1, 10)
    check result.chunks.len == 1
    check result.chunks[0].len == 400

  test "never splits a UTF-8 code point":
    let text = repeat("ação 😀 coração ", 200)
    let result = chunkForMemory(text, 501, 100)
    check result.chunks.len > 1
    for chunk in result.chunks:
      check validateUtf8(chunk) == -1

  test "empty text yields no chunks":
    let result = chunkForMemory("", 1000, 10)
    check result.chunks.len == 0
    check result.truncated == false

  test "inline text is preserved across chunks":
    let text = "primeira parte\n\nsegunda parte\n\nterceira parte"
    let result = chunkForMemory(text, 500, 10)
    check result.chunks.len == 1
    check result.chunks[0] == text
