import std/[unittest, strutils]
import donkey/domain/memory/lessons_pure
import donkey/domain/memory/episode_pure
import donkey/domain/memory/commitment_pure

suite "lessons_pure":

  test "newLesson clamps confidence and preserves source metadata":
    let lesson = newLesson(
      text = "Prefer the retry budget dashboard before changing timeouts.",
      confidence = 1.4'f32,
      sourceEpisodeId = "episode-ops",
      retrievalTags = @["latency", "retry"],
    )
    check lesson.text.contains("retry budget")
    check lesson.confidence == 1.0'f32
    check lesson.sourceEpisodeId == "episode-ops"
    check lesson.retrievalTags == @["latency", "retry"]

  test "successful and failed commitment outcomes produce different lesson candidates":
    let doneCommitment = markCompleted(newCommitment(
      coAgent,
      "I'll send the report tomorrow.",
      nowSec = 100'i64,
    ), nowSec = 150'i64)
    let brokenCommitment = markBroken(newCommitment(
      coAgent,
      "I'll send the report tomorrow.",
      nowSec = 100'i64,
    ), nowSec = 250'i64)
    let doneLessons = extractLessonsFromCommitmentOutcome(doneCommitment, maxLessons = 1)
    let brokenLessons = extractLessonsFromCommitmentOutcome(brokenCommitment, maxLessons = 1)
    check doneLessons.len == 1
    check brokenLessons.len == 1
    check doneLessons[0].text != brokenLessons[0].text
    check doneLessons[0].sourceEpisodeId == "commitment:" & doneCommitment.id
    check brokenLessons[0].sourceEpisodeId == "commitment:" & brokenCommitment.id

  test "episode extraction is bounded per source":
    let episode = newEpisodeJournal(
      title = "Retry loop investigation",
      summary = "Inspect retry amplification before increasing timeouts.\nCapture graphs before patching.",
      startTs = 100'i64,
      endTs = 200'i64,
      sourceMemoryIds = @["u1_m0", "u1_m1"],
    )
    let lessons = extractLessonsFromEpisode(episode, maxLessons = 1)
    check lessons.len == 1
    check lessons[0].sourceEpisodeId == episode.id
