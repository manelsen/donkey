## transcript_pure — keeps a session transcript complete across saves.
##
## The session is saved from the live history, and the live history is a
## moving window: it is trimmed at the front, compaction swaps old messages
## for a summary, and a rewind drops its tail. Writing that window over the
## file on every save left each transcript holding only its last messages.
##
## The transcript is append-only. Given what the file already holds and the
## current history, this module decides which messages are new.
##
## Messages are identified by their session number (`ChatMessage.seq`), not by
## their content: two exchanges with the same words are two messages, and a
## message rewound and written again is a new one. Content is compared only
## for histories or files that carry no numbers. No I/O.

import std/sets
import ../message

type
  TranscriptLine* = object
    role*: string
    text*: string
    seq*:  int64   ## session number; 0 when the line or message has none

func sameContent(a, b: TranscriptLine): bool =
  a.role == b.role and a.text == b.text

func commonRun(existing: openArray[TranscriptLine]; existingStart: int;
               history: openArray[TranscriptLine]; historyStart: int): int =
  ## Length of the run with the same content starting at the two positions.
  while existingStart + result < existing.len and
        historyStart + result < history.len and
        sameContent(existing[existingStart + result],
                    history[historyStart + result]):
    inc result

func resumeByContent(existing, history: openArray[TranscriptLine]): int =
  ## Index in `history` of the first message the transcript lacks, judged by
  ## content. Two alignments are tried and the longer match wins:
  ## - the end of the transcript matches a run of the history (the usual
  ##   case, also after trimming);
  ## - the start of the history matches a run inside the transcript (after a
  ##   rewind; the transcript keeps the rewound messages).
  ## With no match the whole history is new.
  ##
  ## Content cannot tell a repeated message from a stored one, so this is
  ## only used when numbers are unavailable.
  if existing.len == 0:
    return 0

  var tailRun = 0
  var tailEnd = 0
  for offset in 0 ..< history.len:
    let maxRun = min(existing.len, history.len - offset)
    if maxRun <= tailRun:
      break
    for run in countdown(maxRun, tailRun + 1):
      if commonRun(existing, existing.len - run, history, offset) == run:
        tailRun = run
        tailEnd = offset + run
        break

  var headRun = 0
  for start in 0 ..< existing.len:
    if existing.len - start <= headRun:
      break
    let run = commonRun(existing, start, history, 0)
    if run > headRun:
      headRun = run

  if tailRun >= headRun and tailRun > 0: tailEnd
  elif headRun > 0: headRun
  else: 0

func needsWholeTranscript*(tail, history: openArray[TranscriptLine]): bool =
  ## True when the end of the transcript cannot tell whether a message of
  ## `history` is stored: its number is not in the tail and is not above it
  ## (a rewind to an old checkpoint), the tail holds no numbered record, or
  ## the message has no number at all. The caller then reads the whole file.
  var storedNumbers = initHashSet[int64]()
  var highestStored = 0'i64
  for stored in tail:
    if stored.seq > 0:
      storedNumbers.incl(stored.seq)
      highestStored = max(highestStored, stored.seq)
  for message in history:
    if message.seq == SyntheticMessageSeq:
      continue
    if message.seq <= 0:
      ## No number: content is all there is, and it is compared with every
      ## stored line.
      return true
    if storedNumbers.len == 0:
      return true
    if message.seq notin storedNumbers and message.seq <= highestStored:
      return true
  false

func messagesToAppend*(existing, history: openArray[TranscriptLine]): seq[int] =
  ## Indexes of the messages in `history` that the stored transcript does not
  ## hold yet, in order. Synthetic messages (compaction summaries) are never
  ## returned.
  ##
  ## A numbered message is stored when its number is in `existing`. Lines
  ## written before numbering existed have no number; beside them, a numbered
  ## message older than the stored numbers also counts as stored when one of
  ## those lines has its content.
  ## `existing` must cover every number the history can hold: see
  ## needsWholeTranscript.
  var said: seq[int]            ## indexes of real messages in `history`
  var allNumbered = true
  for i, message in history:
    if message.seq == SyntheticMessageSeq:
      continue
    said.add(i)
    if message.seq <= 0:
      allNumbered = false
  if said.len == 0:
    return

  var storedNumbers = initHashSet[int64]()
  var highestStored = 0'i64
  var unnumbered: seq[TranscriptLine]
  for stored in existing:
    if stored.seq > 0:
      storedNumbers.incl(stored.seq)
      highestStored = max(highestStored, stored.seq)
    else:
      unnumbered.add(stored)

  if allNumbered and (existing.len == 0 or storedNumbers.len > 0):
    for i in said:
      let number = history[i].seq
      if number in storedNumbers:
        continue
      ## Only a message older than the stored numbers can be one of the
      ## unnumbered lines; above them it is new whatever its words.
      var inOlderLines = false
      if number < highestStored:
        for older in unnumbered:
          if sameContent(older, history[i]):
            inOlderLines = true
            break
      if not inOlderLines:
        result.add(i)
    return

  ## No numbers on one side: a caller that does not number its history, or the
  ## first save over a file written before numbering existed.
  var realHistory = newSeqOfCap[TranscriptLine](said.len)
  for i in said:
    realHistory.add(history[i])
  for position in resumeByContent(existing, realHistory) ..< said.len:
    result.add(said[position])
