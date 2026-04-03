## lessons_pure — reusable lessons distilled from episodes and outcomes.
## Pure functions only. No I/O.

import std/[strutils, sequtils]
import ./episode_pure
import ./commitment_pure

type
  Lesson* = object
    id*:              string
    text*:            string
    confidence*:      float32
    sourceEpisodeId*: string
    retrievalTags*:   seq[string]

func lessonIdFromText(text: string): string =
  let cleaned = text.toLowerAscii().mapIt(
    if it.isAlphaNumeric(): it else: ' '
  ).join("")
  let words = cleaned.splitWhitespace()
  words[0 ..< min(words.len, 5)].join("-")

func lessonId*(sourceEpisodeId, text: string): string =
  let slug = lessonIdFromText(text)
  if sourceEpisodeId.len > 0 and slug.len > 0:
    sourceEpisodeId & "-" & slug
  elif slug.len > 0:
    slug
  else:
    "lesson"

func clampConfidence*(confidence: float32): float32 =
  if confidence < 0.0'f32:
    0.0'f32
  elif confidence > 1.0'f32:
    1.0'f32
  else:
    confidence

func newLesson*(text: string;
                confidence: float32;
                sourceEpisodeId: string;
                retrievalTags: seq[string]): Lesson =
  Lesson(
    id: lessonId(sourceEpisodeId, text),
    text: text.strip(),
    confidence: clampConfidence(confidence),
    sourceEpisodeId: sourceEpisodeId,
    retrievalTags: retrievalTags,
  )

func extractLessonsFromEpisode*(episode: EpisodeJournal;
                                maxLessons = 2): seq[Lesson] =
  if maxLessons <= 0 or episode.summary.len == 0:
    return @[]
  for line in episode.summary.splitLines():
    let trimmed = line.strip(chars = {' ', '-', '*'})
    if trimmed.len == 0:
      continue
    result.add(newLesson(
      text = trimmed,
      confidence = 0.72'f32,
      sourceEpisodeId = episode.id,
      retrievalTags = @[episode.title.toLowerAscii(), "episode"],
    ))
    if result.len >= maxLessons:
      break

func extractLessonsFromCommitmentOutcome*(commitment: Commitment;
                                          maxLessons = 1): seq[Lesson] =
  if maxLessons <= 0:
    return @[]
  let sourceRef = "commitment:" & commitment.id
  case commitment.status
  of csDone:
    result.add(newLesson(
      text = "Successful follow-through: preserve the workflow behind '" &
             commitment.sourceText.strip() & "'.",
      confidence = 0.78'f32,
      sourceEpisodeId = sourceRef,
      retrievalTags = @["commitment", "success", "follow-through"],
    ))
  of csBroken:
    result.add(newLesson(
      text = "Missed commitment: add stronger deadline visibility for '" &
             commitment.sourceText.strip() & "'.",
      confidence = 0.84'f32,
      sourceEpisodeId = sourceRef,
      retrievalTags = @["commitment", "failure", "deadline"],
    ))
  else:
    discard
