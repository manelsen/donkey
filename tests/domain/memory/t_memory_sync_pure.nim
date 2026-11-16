import std/unittest
import donkey/domain/memory/memory_sync_pure

suite "memory sync — chunks missing from the graph":

  test "nothing is missing when every line is already known":
    let markdown = "- **User:** qual o prazo?\n  **Response:** sexta.\n"
    check missingMemoryChunks(markdown, @[markdown]).len == 0

  test "chunk that spans two stored entries is not reimported":
    ## Entries are appended to MEMORY.md without a blank line between them, so
    ## a blank-line split yields "tail of A + head of B". Both halves are known.
    let entryA = "- **User:** pergunta A\n  **Response:** primeiro paragrafo\n\nsegundo paragrafo de A\n"
    let entryB = "- **User:** pergunta B\n  **Response:** resposta B\n"
    check missingMemoryChunks(entryA & entryB, @[entryA, entryB]).len == 0

  test "paragraph absent from the graph is reported once, trimmed":
    let known = "- fato antigo\n"
    let markdown = known & "\n\n  anotacao feita a mao  \n\n"
    check missingMemoryChunks(markdown, @[known]) == @["anotacao feita a mao"]

  test "chunk with one new line among known lines is still reported":
    let known = "linha conhecida"
    let markdown = "linha conhecida\nlinha nova"
    check missingMemoryChunks(markdown, @[known]) ==
      @["linha conhecida\nlinha nova"]

  test "whitespace and line-ending differences do not count as new":
    let known = "  - fato com espacos  \r\n"
    check missingMemoryChunks("- fato com espacos\n", @[known]).len == 0

  test "empty markdown yields nothing":
    check missingMemoryChunks("", @["x"]).len == 0
    check missingMemoryChunks("\n\n \n", newSeq[string]()).len == 0

  test "repeated missing chunk is reported a single time":
    let markdown = "novo\n\nnovo\n\nnovo"
    check missingMemoryChunks(markdown, newSeq[string]()) == @["novo"]
