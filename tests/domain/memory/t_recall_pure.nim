import std/[strutils, unittest]
import donkey/domain/memory/recall_pure
import donkey/domain/memory/provenance_pure

func turn(id, content: string; ts: int64; session = "s1";
          score = 0.5'f32): MemoryHit =
  MemoryHit(id: id, content: content, kind: "memory", score: score,
            timestamp: ts, origin: turnOrigin(session))

suite "recall — helpers":

  test "memorySequence reads the numeric suffix of a memory id":
    check memorySequence("u1_m0") == 0
    check memorySequence("user_with_m_inside_m42") == 42
    check memorySequence("u1_profile") == -1
    check memorySequence("u1_m") == -1
    check memorySequence("u1_m4x") == -1
    check memorySequence("") == -1

  test "formatUtcMinute renders unix seconds without touching the clock":
    check formatUtcMinute(0) == "1970-01-01 00:00 UTC"
    check formatUtcMinute(1_763_318_640) == "2025-11-16 18:44 UTC"
    check formatUtcMinute(951_782_400) == "2000-02-29 00:00 UTC"

  test "clipNeighbor bounds context and marks the cut":
    check clipNeighbor("curto") == "curto"
    let clipped = clipNeighbor(repeat("ação ", RecallNeighborMaxChars))
    check clipped.len <= RecallNeighborMaxChars
    check clipped.endsWith("[…truncated]")

suite "recall — rendering":

  test "hit without a window renders as a single tagged line":
    let text = renderRecall(@[
      MemoryHit(content: "gosta de Nim", kind: "memory", score: 0.9)])
    check text.memory == "- [memory] gosta de Nim"
    check text.lessons == ""

  test "no hits render nothing":
    let text = renderRecall(newSeq[MemoryHit]())
    check text.memory == ""
    check text.lessons == ""

  test "dialogue hit renders with its neighbours, in order, inside borders":
    var hit = turn("u1_m3", "- **User:** B\n  **Response:** rb", 200)
    hit.before = @[turn("u1_m0", "- **User:** A\n  **Response:** ra", 100)]
    hit.after = @[turn("u1_m4", "- **User:** C\n  **Response:** rc", 300)]
    let memory = renderRecall(@[hit]).memory
    let open = memory.find("<conversation-excerpt session=\"s1\"")
    let a = memory.find("- **User:** A")
    let b = memory.find("- **User:** B")
    let c = memory.find("- **User:** C")
    let close = memory.find("</conversation-excerpt>")
    check open >= 0
    check open < a and a < b and b < c and c < close
    check memory.count("[match]\n") == 1
    check memory.count("[context]\n") == 2
    check memory.find("[match]\n") < b and memory.find("[match]\n") > a
    check "entries=\"3\"" in memory
    check "from=\"1970-01-01 00:01 UTC\"" in memory

  test "the reading note appears once, and only when there is an excerpt":
    var hit = turn("u1_m3", "B", 200)
    hit.before = @[turn("u1_m2", "A", 100)]
    var other = turn("u1_m9", "Y", 900, session = "s2")
    other.before = @[turn("u1_m8", "X", 800, session = "s2")]
    let memory = renderRecall(@[hit, other]).memory
    check memory.count(RecallExcerptNote) == 1
    check memory.count("<conversation-excerpt session=") == 2
    check RecallExcerptNote notin renderRecall(@[
      MemoryHit(content: "x", kind: "memory")]).memory

  test "overlapping windows merge into one excerpt without repeats":
    var first = turn("u1_m1", "B", 200, score = 0.9)
    first.before = @[turn("u1_m0", "A", 100)]
    first.after = @[turn("u1_m2", "C", 300)]
    var second = turn("u1_m2", "C", 300, score = 0.8)
    second.before = @[turn("u1_m1", "B", 200)]
    second.after = @[turn("u1_m3", "D", 400)]
    let memory = renderRecall(@[first, second]).memory
    check memory.count("<conversation-excerpt session=") == 1
    check "entries=\"4\"" in memory
    check memory.count("[match]\n") == 2
    check memory.count("[context]\n") == 2
    for letter in ["A", "B", "C", "D"]:
      check memory.count("\n" & letter & "\n") == 1

  test "a hit already shown as context is promoted, not repeated":
    var first = turn("u1_m1", "B", 200, score = 0.9)
    first.after = @[turn("u1_m2", "C", 300)]
    let plain = turn("u1_m2", "C", 300, score = 0.4)
    let memory = renderRecall(@[first, plain]).memory
    check memory.count("\nC\n") == 1
    check memory.count("[match]\n") == 2
    check "- [memory] C" notin memory

  test "excerpts and single lines keep rank order":
    var hit = turn("u1_m5", "dialogo", 500)
    hit.before = @[turn("u1_m4", "antes", 400)]
    let fact = MemoryHit(id: "u1_m1", content: "fato solto", kind: "memory",
                         origin: MemoryOrigin(source: msIngest))
    let memory = renderRecall(@[fact, hit]).memory
    check memory.find("- [memory] fato solto") < memory.find("<conversation-excerpt session=")

  test "lessons are separated and capped":
    var hits: seq[MemoryHit]
    for i in 1 .. 5:
      hits.add(MemoryHit(content: "licao " & $i, kind: "lesson"))
    hits.add(MemoryHit(content: "fato", kind: "memory"))
    let text = renderRecall(hits)
    check text.memory == "- [memory] fato"
    check text.lessons.startsWith("Relevant lessons:\n")
    check text.lessons.count("- licao") == RecallMaxLessons
