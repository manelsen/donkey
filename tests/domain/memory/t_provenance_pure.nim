import std/[json, unittest]
import donkey/domain/memory/provenance_pure

suite "memory provenance":

  test "origin round-trips through node meta":
    let origin = MemoryOrigin(source: msTurn, sessionId: "1763300000000")
    check originFromMeta(originToMeta(origin)) == origin

  test "meta carries stable keys":
    let meta = originToMeta(MemoryOrigin(source: msIngest, sessionId: "s1"))
    check meta["source"].getStr == "ingest"
    check meta["session_id"].getStr == "s1"

  test "unknown origin writes empty meta":
    check originToMeta(MemoryOrigin()).len == 0

  test "session is omitted when empty":
    let meta = originToMeta(MemoryOrigin(source: msConsolidation))
    check meta["source"].getStr == "consolidation"
    check not meta.hasKey("session_id")

  test "legacy, malformed or foreign meta reads as unknown":
    check originFromMeta(nil) == MemoryOrigin()
    check originFromMeta(newJObject()) == MemoryOrigin()
    check originFromMeta(%*{"source": "something-else"}).source == msUnknown
    check originFromMeta(%*{"source": 7, "session_id": 9}) == MemoryOrigin()
    check originFromMeta(newJArray()) == MemoryOrigin()

  test "turnOrigin builds a dialogue origin":
    check turnOrigin("s9") == MemoryOrigin(source: msTurn, sessionId: "s9")

  test "sameDialogue requires a turn, a session and equality":
    let a = turnOrigin("s1")
    check sameDialogue(a, turnOrigin("s1"))
    check not sameDialogue(a, turnOrigin("s2"))
    check not sameDialogue(a, MemoryOrigin(source: msIngest, sessionId: "s1"))
    check not sameDialogue(turnOrigin(""), turnOrigin(""))
