import std/[strutils, unittest]
import donkey/domain/memory/recall_pure
import donkey/domain/memory/provenance_pure

func turn(id, content: string; ts: int64; session = "s1";
          score = 0.5'f32): MemoryHit =
  MemoryHit(id: id, content: content, kind: "memory", score: score,
            timestamp: ts, origin: turnOrigin(session))

proc runTests*() =
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
      check renderRecall(@[
        MemoryHit(content: "gosta de Nim", kind: "memory", score: 0.9)]) ==
        "- [memory] gosta de Nim"

    test "no hits render nothing":
      check renderRecall(newSeq[MemoryHit]()) == ""

    test "dialogue hit renders with its neighbours, in order, inside borders":
      var hit = turn("u1_m3", "- **User:** B\n  **Response:** rb", 200)
      hit.before = @[turn("u1_m0", "- **User:** A\n  **Response:** ra", 100)]
      hit.after = @[turn("u1_m4", "- **User:** C\n  **Response:** rc", 300)]
      let memory = renderRecall(@[hit])
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
      let memory = renderRecall(@[hit, other])
      check memory.count(RecallExcerptNote) == 1
      check memory.count("<conversation-excerpt session=") == 2
      check RecallExcerptNote notin renderRecall(@[
        MemoryHit(content: "x", kind: "memory")])

    test "overlapping windows merge into one excerpt without repeats":
      var first = turn("u1_m1", "B", 200, score = 0.9)
      first.before = @[turn("u1_m0", "A", 100)]
      first.after = @[turn("u1_m2", "C", 300)]
      var second = turn("u1_m2", "C", 300, score = 0.8)
      second.before = @[turn("u1_m1", "B", 200)]
      second.after = @[turn("u1_m3", "D", 400)]
      let memory = renderRecall(@[first, second])
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
      let memory = renderRecall(@[first, plain])
      check memory.count("\nC\n") == 1
      check memory.count("[match]\n") == 2
      check "- [memory] C" notin memory

    test "excerpts and single lines keep rank order":
      var hit = turn("u1_m5", "dialogo", 500)
      hit.before = @[turn("u1_m4", "antes", 400)]
      let fact = MemoryHit(id: "u1_m1", content: "fato solto", kind: "memory",
                           origin: MemoryOrigin(source: msIngest))
      let memory = renderRecall(@[fact, hit])
      let factAt = memory.find("- [memory] fato solto")
      let excerptAt = memory.find("<conversation-excerpt session=")
      check factAt >= 0
      check excerptAt >= 0
      check factAt < excerptAt

    test "insertion order wins over the clock inside an excerpt":
      ## The wall clock can step back between two appends; the id cannot.
      var hit = turn("u1_m3", "afirmacao original", 500)
      hit.after = @[turn("u1_m4", "correcao posterior", 400)]
      let memory = renderRecall(@[hit])
      let original = memory.find("afirmacao original")
      let correction = memory.find("correcao posterior")
      check original >= 0
      check correction >= 0
      check original < correction

    test "entries without a sequence fall back to the timestamp":
      var hit = MemoryHit(id: "b", content: "depois", kind: "memory",
                          timestamp: 200, origin: turnOrigin("s1"))
      hit.before = @[MemoryHit(id: "a", content: "antes", kind: "memory",
                               timestamp: 100, origin: turnOrigin("s1"))]
      let memory = renderRecall(@[hit])
      check memory.find("antes") >= 0
      check memory.find("antes") < memory.find("depois")

    test "a hit without an id keeps its window":
      var hit = MemoryHit(content: "turno central", kind: "memory",
                          timestamp: 200, origin: turnOrigin("s1"))
      hit.before = @[MemoryHit(content: "turno anterior", kind: "memory",
                               timestamp: 100, origin: turnOrigin("s1"))]
      hit.after = @[MemoryHit(content: "turno seguinte", kind: "memory",
                              timestamp: 300, origin: turnOrigin("s1"))]
      let memory = renderRecall(@[hit])
      check memory.count("<conversation-excerpt session=") == 1
      check "entries=\"3\"" in memory
      let before = memory.find("turno anterior")
      let centre = memory.find("turno central")
      let after = memory.find("turno seguinte")
      check before >= 0 and centre > before and after > centre
      check "- [memory] turno central" notin memory

    test "hits without ids are never merged with each other":
      var first = MemoryHit(content: "A", kind: "memory", timestamp: 100,
                            origin: turnOrigin("s1"))
      first.after = @[MemoryHit(content: "B", kind: "memory", timestamp: 200,
                                origin: turnOrigin("s1"))]
      var second = MemoryHit(content: "X", kind: "memory", timestamp: 300,
                             origin: turnOrigin("s2"))
      second.after = @[MemoryHit(content: "Y", kind: "memory", timestamp: 400,
                                 origin: turnOrigin("s2"))]
      let memory = renderRecall(@[first, second])
      check memory.count("<conversation-excerpt session=") == 2
      check memory.count("entries=\"2\"") == 2

    test "no kind of hit gets a block of its own":
      let rendered = renderRecall(@[
        MemoryHit(content: "uma regra antiga", kind: "lesson"),
        MemoryHit(content: "fato", kind: "memory")])
      check rendered == "- [lesson] uma regra antiga\n- [memory] fato"

    test "an excerpt mixing numbered and unnumbered ids has one consistent order":
      ## Per-pair criteria would cycle here: A before B by number, B before C
      ## and C before A by time.
      var hit = MemoryHit(id: "u1_m3", content: "entrada A", kind: "memory",
                          timestamp: 500, origin: turnOrigin("s1"))
      hit.after = @[
        MemoryHit(id: "u1_m4", content: "entrada B", kind: "memory",
                  timestamp: 400, origin: turnOrigin("s1")),
        MemoryHit(id: "", content: "entrada C", kind: "memory",
                  timestamp: 450, origin: turnOrigin("s1"))]
      let memory = renderRecall(@[hit])
      let a = memory.find("entrada A")
      let b = memory.find("entrada B")
      let c = memory.find("entrada C")
      check a >= 0 and b >= 0 and c >= 0
      ## Without a number on every entry the whole block goes by timestamp.
      check b < c and c < a


when isMainModule:
  runTests()
