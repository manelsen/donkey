## memory_sync_pure — decides which MEMORY.md paragraphs the graph still lacks.
##
## MEMORY.md is the human-editable view; the graph is the structured store.
## Entries are appended to the file without a blank line between them, so a
## blank-line split does not line up with what the graph stores: a paragraph
## can be "tail of entry A + head of entry B". Comparing whole paragraphs
## against the graph therefore reports text that is already stored.
##
## The comparison here is per line: only lines that exist nowhere in the graph
## are missing, and consecutive missing lines are kept together. No I/O.

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
  ## Returns the text of `markdownMemory` that `knownTexts` lacks. Inside each
  ## blank-line-separated paragraph, consecutive unknown lines form one chunk
  ## and known lines are left out, so a partially stored paragraph never
  ## brings its stored lines back. Chunks come trimmed, in file order, each
  ## one at most once.
  if markdownMemory.strip.len == 0:
    return
  let known = knownLineSet(knownTexts)
  var reported = initHashSet[string]()
  var run: seq[string]

  template flushRun() =
    if run.len > 0:
      let chunk = run.join("\n").strip
      run.setLen(0)
      if chunk.len > 0 and chunk notin reported:
        reported.incl(chunk)
        result.add(chunk)

  for line in markdownMemory.replace("\r\n", "\n").split('\n'):
    let normalized = normalizedLine(line)
    if normalized.len == 0 or normalized in known:
      ## A blank line ends the paragraph; a known line ends the new run.
      flushRun()
    else:
      run.add(line.strip(leading = false))
  flushRun()
