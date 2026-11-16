## recall_pure — shape and rendering of recalled memories.
##
## A recalled dialogue turn used to reach the model as a lone line, ranked by
## score next to unrelated hits, with no sign of what was said right before or
## right after it. A correction given in the following turn was lost unless it
## happened to rank on its own.
##
## A hit that is a dialogue turn now carries the neighbouring turns of the same
## session. This module renders such a hit as one excerpt: oldest first, inside
## explicit borders, with the retrieved entry told apart from its context.
## Hits of any other origin render alone, as before. No I/O.

import std/[algorithm, strutils]
import ./provenance_pure

const
  RecallWindowRadius* = 1
    ## Dialogue turns attached on each side of a hit. One stored turn already
    ## holds a user message and its response.
  RecallWindowMaxHits* = 3
    ## Only the best-ranked dialogue hits are expanded, to bound the context.
  RecallWindowMaxHops* = 6
    ## Nodes of other origins or sessions skipped while looking for the
    ## neighbouring turn of the same session.
  RecallNeighborMaxChars* = 2000
    ## Cap for a context entry. The retrieved entry itself is never clipped.
  RecallMaxLessons* = 3
  RecallTruncationMarker* = "\n[…truncated]"
  RecallLessonKind* = "lesson"
  RecallExcerptNote* =
    "Entries inside <conversation-excerpt> are consecutive exchanges of one " &
    "past session, oldest first. [match] marks a retrieved entry, [context] " &
    "its neighbours. An excerpt is partial: the conversation may continue " &
    "before and after it."

type
  MemoryHit* = object
    ## Single result from a memory search.
    content*:   string
    score*:     float32  ## relevance in [0, 1]; higher = more relevant
    kind*:      string   ## node kind: "memory", "lesson", "fact", …
    id*:        string   ## node id; empty when the backend has none
    timestamp*: int64    ## unix seconds; 0 when unknown
    origin*:    MemoryOrigin
    before*:    seq[MemoryHit]  ## same-session turns right before, oldest first
    after*:     seq[MemoryHit]  ## same-session turns right after, oldest first

  RecallText* = object
    memory*:  string  ## excerpts and single lines, in rank order
    lessons*: string  ## "Relevant lessons:" block, or empty

  ExcerptEntry = object
    hit:     MemoryHit
    isMatch: bool

func memorySequence*(id: string): int =
  ## Insertion number encoded in a memory id ("<user>_m<N>"), or -1.
  let marker = id.rfind("_m")
  if marker < 0 or marker + 2 >= id.len:
    return -1
  for i in marker + 2 ..< id.len:
    if id[i] notin {'0' .. '9'}:
      return -1
  try:
    parseInt(id[marker + 2 .. ^1])
  except ValueError:
    -1

func twoDigits(value: int64): string =
  if value < 10: "0" & $value else: $value

func formatUtcMinute*(unixSeconds: int64): string =
  ## "YYYY-MM-DD HH:MM UTC", computed from the value alone (no clock, no
  ## time zone database).
  let days = unixSeconds div 86_400 - (if unixSeconds mod 86_400 < 0: 1 else: 0)
  let secondOfDay = unixSeconds - days * 86_400
  # Civil-from-days (proleptic Gregorian), era-based.
  let z = days + 719_468
  let era = (if z >= 0: z else: z - 146_096) div 146_097
  let dayOfEra = z - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra div 1_460 + dayOfEra div 36_524 -
                   dayOfEra div 146_096) div 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra div 4 -
                              yearOfEra div 100)
  let monthIndex = (5 * dayOfYear + 2) div 153
  let day = dayOfYear - (153 * monthIndex + 2) div 5 + 1
  let month = if monthIndex < 10: monthIndex + 3 else: monthIndex - 9
  let year = yearOfEra + era * 400 + (if month <= 2: 1 else: 0)
  $year & "-" & twoDigits(month) & "-" & twoDigits(day) & " " &
    twoDigits(secondOfDay div 3_600) & ":" &
    twoDigits((secondOfDay mod 3_600) div 60) & " UTC"

func clipNeighbor*(text: string): string =
  ## Bounds a context entry without splitting a UTF-8 code point, and marks
  ## the cut so the reader knows text is missing.
  let trimmed = text.strip
  if trimmed.len <= RecallNeighborMaxChars:
    return trimmed
  var cut = RecallNeighborMaxChars - RecallTruncationMarker.len
  while cut > 0 and (ord(trimmed[cut]) and 0xC0) == 0x80:
    dec cut
  trimmed[0 ..< cut] & RecallTruncationMarker

func hasWindow(hit: MemoryHit): bool =
  hit.before.len > 0 or hit.after.len > 0

func flat(hit: MemoryHit): MemoryHit =
  result = hit
  result.before = @[]
  result.after = @[]

func indexOfId(entries: seq[ExcerptEntry]; id: string): int =
  if id.len == 0:
    return -1
  for i, entry in entries:
    if entry.hit.id == id:
      return i
  -1

func blockWithId(blocks: seq[seq[ExcerptEntry]]; id: string): int =
  for i, entries in blocks:
    if indexOfId(entries, id) >= 0:
      return i
  -1

func addEntry(entries: var seq[ExcerptEntry]; entry: ExcerptEntry) =
  let existing = indexOfId(entries, entry.hit.id)
  if existing >= 0:
    if entry.isMatch:
      ## The retrieved copy is the unclipped one.
      entries[existing] = entry
  else:
    entries.add(entry)

func byInsertion(a, b: ExcerptEntry): int =
  cmp(memorySequence(a.hit.id), memorySequence(b.hit.id))

func byTimestamp(a, b: ExcerptEntry): int =
  if a.hit.timestamp != b.hit.timestamp:
    return cmp(a.hit.timestamp, b.hit.timestamp)
  byInsertion(a, b)

func sortChronologically(entries: var seq[ExcerptEntry]) =
  ## One criterion for the whole block, so the order is always consistent.
  ## Insertion number when every entry has one: the wall clock can step back
  ## between two appends, the insertion number cannot. Timestamp otherwise.
  var allNumbered = true
  for entry in entries:
    if memorySequence(entry.hit.id) < 0:
      allNumbered = false
      break
  if allNumbered:
    entries.sort(byInsertion)
  else:
    entries.sort(byTimestamp)

func renderExcerpt(entries: seq[ExcerptEntry]): string =
  let first = entries[0].hit
  result = "<conversation-excerpt session=\"" & first.origin.sessionId & "\""
  if first.timestamp > 0:
    result.add(" from=\"" & formatUtcMinute(first.timestamp) & "\"")
  result.add(" entries=\"" & $entries.len & "\">\n")
  for entry in entries:
    result.add(if entry.isMatch: "[match]\n" else: "[context]\n")
    result.add(entry.hit.content.strip & "\n")
  result.add("</conversation-excerpt>")

func renderRecall*(hits: seq[MemoryHit]): RecallText =
  ## Renders ranked hits for the model. Lessons go to their own block.
  ## Dialogue hits that carry neighbours become excerpts; windows that share
  ## an entry merge into one excerpt, and no entry is rendered twice.
  var lessonLines: seq[string]
  var ranked: seq[MemoryHit]
  for hit in hits:
    if hit.kind == RecallLessonKind:
      if lessonLines.len < RecallMaxLessons:
        lessonLines.add("- " & hit.content)
    else:
      ranked.add(hit)

  ## `owner[i]` is the block that renders ranked hit `i`, or -1 for a single
  ## line. Blocks are tracked by index, not by id, because a backend may
  ## return hits without ids. A block absorbed by a merge is emptied and
  ## forwards to the block that took its entries.
  var blocks: seq[seq[ExcerptEntry]]
  var forward: seq[int]
  var owner = newSeq[int](ranked.len)

  func resolve(forward: seq[int]; index: int): int =
    result = index
    while result >= 0 and forward[result] != result:
      result = forward[result]

  for i, hit in ranked:
    owner[i] = -1
    if not hit.hasWindow:
      continue
    var window: seq[ExcerptEntry]
    for neighbour in hit.before:
      window.add(ExcerptEntry(hit: flat(neighbour)))
    window.add(ExcerptEntry(hit: flat(hit), isMatch: true))
    for neighbour in hit.after:
      window.add(ExcerptEntry(hit: flat(neighbour)))
    var target = -1
    for entry in window:
      let found = blockWithId(blocks, entry.hit.id)
      if found < 0 or found == target:
        continue
      if target < 0:
        target = found
      else:
        for moved in blocks[found]:
          blocks[target].addEntry(moved)
        blocks[found].setLen(0)
        forward[found] = target
    if target < 0:
      blocks.add(newSeq[ExcerptEntry]())
      forward.add(blocks.high)
      target = blocks.high
    for entry in window:
      blocks[target].addEntry(entry)
    owner[i] = target

  for i, hit in ranked:
    if hit.hasWindow:
      continue
    let found = blockWithId(blocks, hit.id)
    if found >= 0:
      blocks[found].addEntry(ExcerptEntry(hit: flat(hit), isMatch: true))
      owner[i] = found

  var parts: seq[string]
  var rendered = newSeq[bool](blocks.len)
  for i, hit in ranked:
    let index = resolve(forward, owner[i])
    if index < 0:
      parts.add("- [" & hit.kind & "] " & hit.content)
    elif not rendered[index]:
      rendered[index] = true
      sortChronologically(blocks[index])
      parts.add(renderExcerpt(blocks[index]))
  if blocks.len > 0:
    parts.insert(RecallExcerptNote, 0)
  result.memory = parts.join("\n")
  if lessonLines.len > 0:
    result.lessons = "Relevant lessons:\n" & lessonLines.join("\n")
