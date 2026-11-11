import std/[options, strutils, unittest]
import donkey/domain/memory/commitment_pure

suite "commitment_pure":

  test "newCommitment builds an open commitment with source text and due date":
    let c = newCommitment(
      coUser,
      "Can you remind me tomorrow to send the invoice?",
      nowSec = 1_700_000_000'i64,
    )
    check c.id.len > 0
    check c.owner == coUser
    check c.status == csOpen
    check c.sourceText.contains("send the invoice")
    check c.dueAt.isSome
    check c.score > 0.0'f32

  test "parseUserRequestedCommitment recognizes user requests":
    let parsed = parseUserRequestedCommitment(
      "Can you remind me tomorrow to pay rent?",
      nowSec = 1_700_000_000'i64,
    )
    check parsed.isSome
    check parsed.get().owner == coUser
    check parsed.get().dueAt.isSome

  test "parseUserRequestedCommitment recognizes Portuguese requests":
    let parsed = parseUserRequestedCommitment(
      "Lembre-me de comprar leite amanhã", 1_700_000_000)
    check parsed.isSome
    check parsed.get().owner == coUser

  test "parseAgentPromisedCommitment recognizes Portuguese promises":
    let parsed = parseAgentPromisedCommitment(
      "Vou enviar o relatório amanhã", 1_700_000_000)
    check parsed.isSome
    check parsed.get().owner == coAgent

  test "parseAgentPromisedCommitment recognizes agent promises":
    let parsed = parseAgentPromisedCommitment(
      "I'll send you the summary tomorrow.",
      nowSec = 1_700_000_000'i64,
    )
    check parsed.isSome
    check parsed.get().owner == coAgent
    check parsed.get().dueAt.isSome

  test "state transitions keep id and update accountability score":
    let base = newCommitment(
      coAgent,
      "I'll follow up tomorrow.",
      nowSec = 1_700_000_000'i64,
    )
    let done = base.markCompleted()
    let broken = base.markBroken()
    let cancelled = base.cancel()

    check done.id == base.id
    check done.status == csDone
    check done.score == 1.0'f32

    check broken.status == csBroken
    check broken.score == 0.0'f32

    check cancelled.status == csCancelled
    check cancelled.score > broken.score

  test "open overdue commitments lose score":
    let c = Commitment(
      id: "c-overdue",
      owner: coAgent,
      status: csOpen,
      dueAt: some(100'i64),
      score: 0.0'f32,
      sourceText: "I'll send the file.",
    )
    check commitmentScore(c, nowSec = 200'i64) < 0.5'f32
