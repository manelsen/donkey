## memory_consolidation — automatic memory extraction, episodes and lessons.
##
## Runs on explicit maintenance boundaries (`/compact`, `/reset`, `/new`) so it
## never adds an LLM call to the hot user turn. The silent turn extracts facts,
## preferences, concepts and relations; `contemplation` builds/writes an
## episode; lessons are distilled from that episode. The same module also
## maintains a session-scoped blackboard of detected commitments.

import std/[options, os, strutils]

import ../core/log
import ../core/memory/blackboard
import ../core/memory/silent_turn
import ../core/pipeops
import ../domain/memory/commitment_pure
import ../domain/memory/episode_pure
import ../domain/message
import ../ports/memory
import ../ports/provider
import ./contemplation

const
  MinConsolidationMessages* = 4
  MaxEpisodeSummaryChars* = 2000
  MaxEpisodeTitleChars* = 60
  MaxMemoryItems* = 20
  MaxMemoryItemChars* = 500
  MaxBlackboardContentChars* = 300

type
  ConsolidationResult* = object
    attempted*:        bool
    skippedReason*:    string
    factsSaved*:       int
    preferencesSaved*: int
    conceptsSaved*:    int
    triplesSaved*:     int
    episodeSaved*:     bool
    lessonsSaved*:     int

func clipText*(text: string; maxChars: int): string =
  if maxChars <= 0:
    return ""
  let trimmed = text.strip
  if trimmed.len <= maxChars:
    return trimmed
  if maxChars <= 16:
    return trimmed[0 ..< maxChars]
  trimmed[0 ..< maxChars - 16] & "\n[…truncated]"

func buildEpisodeFromHistory*(history: ConversationHistory;
                              sessionId: string;
                              nowSec: int64): EpisodeJournal =
  ## Deterministic episode from the current history. The LLM extraction is
  ## stored separately; this journal is the durable narrative anchor.
  var title = ""
  var lines: seq[string]
  for message in history:
    if message.text.len == 0:
      continue
    if title.len == 0 and message.role == roleUser:
      title = clipText(message.text, MaxEpisodeTitleChars)
    lines.add(message.role & ": " & clipText(message.text, 300))
  if title.len == 0:
    title = "Session " & sessionId
  let summary =
    if lines.len == 0: ""
    else: clipText(lines[max(0, lines.len - 12) .. ^1].join("\n"),
                   MaxEpisodeSummaryChars)
  var startSec = nowSec
  if sessionId.len > 0:
    try:
      let raw = parseBiggestInt(sessionId)
      if raw > 0:
        startSec = raw div 1000
    except ValueError:
      discard
  newEpisodeJournal(title, summary, startSec, nowSec, @[])

func formatExtractedMemory*(extracted: SilentMemoryResult;
                            nowMs: int64): string =
  ## Formats the silent-turn output as one bounded Markdown block.
  var lines = @["## Consolidated memory (" & $nowMs & ")"]
  for fact in extracted.facts:
    if lines.len > MaxMemoryItems * 4:
      break
    lines.add("- Fact: " & clipText(fact, MaxMemoryItemChars))
  for pref in extracted.preferences:
    if lines.len > MaxMemoryItems * 4:
      break
    lines.add("- Preference: " & clipText(pref, MaxMemoryItemChars))
  for item in extracted.concepts:
    if lines.len > MaxMemoryItems * 4:
      break
    lines.add("- Concept: " & clipText(item, MaxMemoryItemChars))
  for triple in extracted.triples:
    if lines.len > MaxMemoryItems * 4:
      break
    lines.add("- Relation: " & clipText(triple.subject, 80) & " — " &
              clipText(triple.predicate, 80) & " — " &
              clipText(triple.obj, 120))
  if lines.len == 1:
    return ""
  lines.join("\n") & "\n"

proc addOrUpdateCommitment(bb: var Blackboard;
                           commitment: Commitment;
                           nowMs: int64): bool =
  let key = "commitment:" & commitment.id
  let content = clipText(commitment.sourceText, MaxBlackboardContentChars)
  if bb.hasEntry(key):
    bb.updateEntry(key, content, PriorityHigh).isOk
  else:
    bb.addEntry(key, content, PriorityHigh, nowMs).isOk

proc rememberCommitments*(bb: var Blackboard;
                          userText, assistantText: string;
                          nowMs: int64): int =
  ## Detects explicit user/agent commitments and keeps them in the session
  ## blackboard. Returns how many entries were added or updated.
  let nowSec = nowMs div 1000
  if userText.len > 0:
    let commitment = parseUserRequestedCommitment(userText, nowSec)
    if commitment.isSome and bb.addOrUpdateCommitment(commitment.get(), nowMs):
      inc result
  if assistantText.len > 0:
    let commitment = parseAgentPromisedCommitment(assistantText, nowSec)
    if commitment.isSome and bb.addOrUpdateCommitment(commitment.get(), nowMs):
      inc result

func buildContemplationMemories(history: ConversationHistory;
                                sessionId: string;
                                nowSec: int64): seq[ContemplationMemory] =
  for i, message in history:
    if message.text.len > 0:
      result.add(ContemplationMemory(
        id: sessionId & "-" & $i,
        content: message.role & ": " & clipText(message.text, 300),
        timestamp: nowSec,
      ))

proc consolidateSession*(memory: MemoryRuntimePort;
                         completeFn: CompleteFn;
                         userId: UserId;
                         sessionId: string;
                         history: ConversationHistory;
                         log: Logger): ConsolidationResult {.gcsafe, raises: [].} =
  ## Extracts memory, writes an episode and distils lessons. Best-effort:
  ## every failure is logged and never propagates to the caller.
  let mode = getEnv("DONKEY_MEMORY_CONSOLIDATE", "1").strip.toLowerAscii()
  if mode in ["0", "off", "false", "no"]:
    result.skippedReason = "disabled"
    return
  if not memory.hasMemoryConsolidation:
    result.skippedReason = "backend has no consolidation hooks"
    return
  if history.len < MinConsolidationMessages:
    result.skippedReason = "history too short"
    return

  result.attempted = true
  let nowMs = epochMs()
  let nowSec = nowMs div 1000

  if completeFn != nil:
    var extracted: Result[SilentMemoryResult, string]
    try:
      extracted = runSilentMemoryTurn(history, completeFn, userId)
    except Exception as e:
      extracted = err(Result[SilentMemoryResult, string], "silent turn raised: " & e.msg)
    if extracted.isErr:
      log.warn("memory consolidation: silent turn failed: " & extracted.error)
    else:
      let memoryBlock = formatExtractedMemory(extracted.get(), nowMs)
      if memoryBlock.len > 0:
        let saved = memory.appendExtractedMemory(userId, memoryBlock)
        if saved.isErr:
          log.warn("memory consolidation: append: " & saved.error)
        else:
          result.factsSaved = extracted.get().facts.len
          result.preferencesSaved = extracted.get().preferences.len
          result.conceptsSaved = extracted.get().concepts.len
          result.triplesSaved = extracted.get().triples.len

  let episode = buildEpisodeFromHistory(history, sessionId, nowSec)
  let memories = buildContemplationMemories(history, sessionId, nowSec)

  var episodeSaved = false
  let loadMemories = proc(): seq[ContemplationMemory] {.gcsafe.} =
    memories
  let buildEpisode = proc(items: seq[ContemplationMemory]): EpisodeJournal {.gcsafe.} =
    discard items
    episode
  let writeEpisode = proc(uid: UserId; value: EpisodeJournal) {.gcsafe.} =
    {.cast(gcsafe).}:
      let saved = memory.saveEpisode(uid, value)
      if saved.isOk:
        episodeSaved = true
      else:
        log.warn("memory consolidation: episode: " & saved.error)
  let loadUserId = proc(): UserId {.gcsafe.} = userId

  try:
    runContemplationNow(loadMemories, buildEpisode, writeEpisode, loadUserId)
  except Exception as e:
    log.warn("memory consolidation: contemplation: " & e.msg)
  result.episodeSaved = episodeSaved

  if memory.extractLessons != nil:
    let lessons = memory.extractLessons(userId, @[episode])
    if lessons.isErr:
      log.warn("memory consolidation: lessons: " & lessons.error)
    else:
      result.lessonsSaved = lessons.get()
