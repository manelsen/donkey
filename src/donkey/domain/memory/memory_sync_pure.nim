## memory_sync_pure — decides which MEMORY.md paragraphs the graph still lacks.
##
## MEMORY.md is the human-editable view; the graph is the structured store.
## Entries are appended to the file without a blank line between them, so a
## blank-line split does not line up with what the graph stores: a paragraph
## can be "tail of entry A + head of entry B". Comparing whole paragraphs
## against the graph therefore reports text that is already stored.
##
## The comparison here is per entry (a list item with its continuation lines,
## or a run of prose): an entry is missing when any of its lines exists
## nowhere in the graph. No I/O.

import std/[sets, strutils]

func normalizedLine(line: string): string =
  line.strip

func knownLineSet(knownTexts: openArray[string]): HashSet[string] =
  result = initHashSet[string]()
  for text in knownTexts:
    for line in text.splitLines():
      let normalized = normalizedLine(line)
      if normalized.len > 0:
        result.incl(normalized)

func startsListItem(line: string): bool =
  ## True for "- x", "* x", "+ x" and "1. x" at the start of the line.
  ## Indented lines are continuations, never a new item.
  if line.len < 2 or line[0] in {' ', '\t'}:
    return false
  if line[0] in {'-', '*', '+'}:
    return line[1] == ' '
  var i = 0
  while i < line.len and line[i] in {'0' .. '9'}:
    inc i
  i > 0 and i + 1 < line.len and line[i] == '.' and line[i + 1] == ' '

func missingMemoryChunks*(markdownMemory: string;
                          knownTexts: openArray[string]): seq[string] =
  ## Returns the entries of `markdownMemory` that `knownTexts` lacks.
  ##
  ## An entry is a list item with its continuation lines, or a run of prose
  ## lines; a blank line always ends it. An entry is missing when at least one
  ## of its lines is stored nowhere, and it is then returned whole, so a
  ## question never loses an answer that happens to match a stored line.
  ## Entries whose lines are all stored are left out, so a partially stored
  ## paragraph does not bring its stored entries back. Consecutive missing
  ## entries of a paragraph form one chunk. Chunks come trimmed, in file
  ## order, each one at most once.
  if markdownMemory.strip.len == 0:
    return
  let known = knownLineSet(knownTexts)
  var reported = initHashSet[string]()
  var run: seq[string]     ## lines of consecutive missing entries
  var entry: seq[string]   ## lines of the entry being read
  var entryIsMissing = false

  template flushRun() =
    if run.len > 0:
      let chunk = run.join("\n").strip
      run.setLen(0)
      if chunk.len > 0 and chunk notin reported:
        reported.incl(chunk)
        result.add(chunk)

  template closeEntry() =
    if entry.len > 0:
      if entryIsMissing:
        run.add(entry)
      else:
        flushRun()
      entry.setLen(0)
      entryIsMissing = false

  for rawLine in markdownMemory.replace("\r\n", "\n").split('\n'):
    let line = rawLine.strip(leading = false)
    let normalized = normalizedLine(line)
    if normalized.len == 0:
      closeEntry()
      flushRun()
      continue
    if startsListItem(line):
      closeEntry()
    entry.add(line)
    if normalized notin known:
      entryIsMissing = true
  closeEntry()
  flushRun()
