## Automatic memory consolidation tests.
##
## Covers the deterministic episode builder, silent-memory formatting, the
## session blackboard commitment detector and the end-to-end consolidation
## orchestration with a fake MemoryRuntimePort.

import std/[os, strutils, unittest]

import donkey/app/memory_consolidation
import donkey/core/log
import donkey/core/memory/blackboard
import donkey/core/memory/silent_turn
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/memory/md_file
import donkey/domain/memory/episode_pure
import donkey/domain/message
import donkey/domain/memory/episode_pure
import donkey/domain/memory/graph_pure
import donkey/ports/memory
import donkey/ports/provider

type
  Capture = ref object
    appended:      seq[string]
    episodes:      seq[EpisodeJournal]
    lessonsCalls:  int
    lastLessonCount: int

proc capturePort(cap: Capture): MemoryRuntimePort =
  MemoryRuntimePort(
    appendExtractedMemory: proc(userId: UserId; text: string): Result[void, string]
                              {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        cap.appended.add(text)
      ok(),
    saveEpisode: proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                   {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        cap.episodes.add(episode)
      ok(),
    extractLessons: proc(userId: UserId; episodes: seq[EpisodeJournal]): Result[int, string]
                      {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        inc cap.lessonsCalls
        cap.lastLessonCount = episodes.len
      ok(2),
  )

proc historyOf(messages: openArray[(string, string)]): ConversationHistory =
  result = newHistory()
  for (role, text) in messages:
    result.add(ChatMessage(role: role, text: text))

suite "memory consolidation":

  test "builds a deterministic episode from the conversation":
    let history = historyOf([
      (roleUser, "Please fix the deployment pipeline"),
      (roleAssistant, "I will inspect the CI logs"),
      (roleUser, "The failure is in the cache step"),
      (roleAssistant, "Found it: the cache key is stale"),
    ])
    let episode = buildEpisodeFromHistory(history, "1700000000000", 1_700_000_100)
    check episode.title == "Please fix the deployment pipeline"
    check episode.summary.contains("cache key is stale")
    check episode.startTs == 1_700_000_000
    check episode.endTs == 1_700_000_100

  test "formats extracted memory with bounds and sections":
    let extracted = SilentMemoryResult(
      facts: @["Deployment uses Docker", "Cache key is stale"],
      preferences: @["Prefers Portuguese"],
      concepts: @["CI pipeline"],
      triples: @[buildTriple("user", "prefers", "Portuguese",
                             "user prefers Portuguese", 0.9)],
    )
    let rendered = formatExtractedMemory(extracted, 1234)
    check rendered.contains("## Consolidated memory (1234)")
    check rendered.contains("- Fact: Deployment uses Docker")
    check rendered.contains("- Preference: Prefers Portuguese")
    check rendered.contains("- Concept: CI pipeline")
    check rendered.contains("- Relation: user — prefers — portuguese")

  test "empty extraction produces no memory block":
    let rendered = formatExtractedMemory(SilentMemoryResult(), 1)
    check rendered.len == 0

  test "blackboard remembers user and agent commitments without duplicates":
    var bb = newBlackboard(12)
    let nowMs = 1_700_000_000_000'i64
    check rememberCommitments(bb, "Remind me to buy milk tomorrow", "", nowMs) == 1
    check rememberCommitments(bb, "", "I will send the report tomorrow", nowMs) == 1
    check bb.entries.len == 2
    # Re-detecting the same user commitment updates the entry, it does not add.
    check rememberCommitments(bb, "Remind me to buy milk tomorrow", "", nowMs) == 1
    check bb.entries.len == 2

  test "consolidates extraction, episode and lessons end to end":
    let cap = Capture()
    let port = capturePort(cap)
    let history = historyOf([
      (roleUser, "Remember that I prefer Rust for embedded work"),
      (roleAssistant, "Noted. I will keep that in mind."),
      (roleUser, "Also remind me to review the pinout tomorrow"),
      (roleAssistant, "I will follow up on the pinout review."),
    ])
    let completionText = """{
      "triples": [{"subject": "user", "predicate": "prefers", "object": "Rust", "confidence": 0.9}],
      "facts": ["User works with embedded systems"],
      "preferences": ["Prefers Rust"],
      "concepts": ["embedded systems"]
    }"""
    let completeFn: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string]
                                  {.gcsafe.} =
      {.cast(gcsafe).}:
        ok(CompletionResponse(text: completionText))

    let res = consolidateSession(
      port, completeFn, UserId("u-memory"), "1700000000000", history,
      newLogger("test.memory", lvlError))

    check res.attempted
    check res.factsSaved == 1
    check res.preferencesSaved == 1
    check res.conceptsSaved == 1
    check res.triplesSaved == 1
    check res.episodeSaved
    check res.lessonsSaved == 2
    check cap.appended.len == 1
    check cap.appended[0].contains("User works with embedded systems")
    check cap.episodes.len == 1
    check cap.episodes[0].summary.contains("pinout review")
    check cap.lessonsCalls == 1
    check cap.lastLessonCount == 1

  test "short histories are skipped":
    let cap = Capture()
    let port = capturePort(cap)
    let history = historyOf([
      (roleUser, "hi"),
      (roleAssistant, "hello"),
    ])
    let res = consolidateSession(
      port, nil, UserId("u-short"), "1", history,
      newLogger("test.memory", lvlError))
    check not res.attempted
    check res.skippedReason == "history too short"
    check cap.appended.len == 0
    check cap.episodes.len == 0

  test "md_file runtime port exposes consolidation hooks":
    let dir = getTempDir() / "donkey_memory_consolidation_port"
    removeDir(dir)
    defer: removeDir(dir)
    let port = MdFileAdapter(paddocksDir: dir).toRuntimePort()
    check port.hasMemoryConsolidation
    let uid = UserId("u-port")
    check port.appendExtractedMemory(uid, "## Consolidated\n- Fact: port works").isOk
    let episode = newEpisodeJournal(
      "Port episode", "The port persisted an episode.",
      1_700_000_000, 1_700_000_100, @[])
    check port.saveEpisode(uid, episode).isOk
    check port.extractLessons(uid, @[episode]).isOk
    let context = port.loadContext(uid)
    check context.memoryMd.contains("Fact: port works")
    check context.memoryMd.contains("Episode: Port episode")
    check context.memoryMd.contains("Lesson:")
