## memory_sync_pure — decides which MEMORY.md paragraphs the graph still lacks.
##
## MEMORY.md is the human-editable view; the graph is the structured store.
## Entries are appended to the file without a blank line between them, so a
## blank-line split does not line up with what the graph stores: a paragraph
## can be "tail of entry A + head of entry B". Comparing whole paragraphs
## against the graph therefore reports text that is already stored.
##
## The comparison here is per line: a paragraph is missing only when at least
## one of its lines exists nowhere in the graph. No I/O.

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

func missingMemoryChunks*(markdownMemory: string;
                          knownTexts: openArray[string]): seq[string] =
  ## Returns the blank-line-separated paragraphs of `markdownMemory` that carry
  ## at least one line absent from `knownTexts`. Paragraphs come back trimmed,
  ## in file order, each one at most once.
  if markdownMemory.strip.len == 0:
    return
  let known = knownLineSet(knownTexts)
  var reported = initHashSet[string]()
  for chunk in markdownMemory.replace("\r\n", "\n").split("\n\n"):
    let trimmed = chunk.strip
    if trimmed.len == 0 or trimmed in reported:
      continue
    var hasNewLine = false
    for line in trimmed.splitLines():
      let normalized = normalizedLine(line)
      if normalized.len > 0 and normalized notin known:
        hasNewLine = true
        break
    if hasNewLine:
      reported.incl(trimmed)
      result.add(trimmed)
