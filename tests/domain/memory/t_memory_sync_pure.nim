import std/[strutils, unittest]
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

  test "only the new line of a partially known paragraph is reported":
    ## Fallback writes land in MEMORY.md with no blank line between entries.
    check missingMemoryChunks("- antigo\n- novo", @["- antigo"]) == @["- novo"]
    check missingMemoryChunks("- novo\n- antigo", @["- antigo"]) == @["- novo"]

  test "consecutive new lines stay together as one chunk":
    let markdown = "- antigo\n- **User:** pergunta\n  **Response:** resposta\n- outro antigo"
    check missingMemoryChunks(markdown, @["- antigo", "- outro antigo"]) ==
      @["- **User:** pergunta\n  **Response:** resposta"]

  test "a known line in the middle splits the new content":
    check missingMemoryChunks("novo um\nconhecido\nnovo dois", @["conhecido"]) ==
      @["novo um", "novo dois"]

  test "one contiguous block returns only the lines the graph lacks":
    var lines: seq[string]
    for i in 1 .. 215:
      lines.add("- fato " & $i)
    let missing = missingMemoryChunks(lines.join("\n"), [lines[15 .. ^1].join("\n\n")])
    check missing == @[lines[0 .. 14].join("\n")]

  test "whitespace and line-ending differences do not count as new":
    let known = "  - fato com espacos  \r\n"
    check missingMemoryChunks("- fato com espacos\n", @[known]).len == 0

  test "empty markdown yields nothing":
    check missingMemoryChunks("", @["x"]).len == 0
    check missingMemoryChunks("\n\n \n", newSeq[string]()).len == 0

  test "repeated missing chunk is reported a single time":
    let markdown = "novo\n\nnovo\n\nnovo"
    check missingMemoryChunks(markdown, newSeq[string]()) == @["novo"]
