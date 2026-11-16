## transcript_pure — keeps a session transcript complete across saves.
##
## The session is saved from the live history, and the live history is a
## moving window: it is trimmed at the front, compaction swaps old messages
## for a summary, and a rewind drops its tail. Writing that window over the
## file on every save left each transcript holding only its last messages.
##
## The transcript is now append-only. Given what the file already holds and
## the current history, this module decides which messages are new. No I/O.

type
  TranscriptLine* = object
    role*: string
    text*: string

func commonRun(existing: openArray[TranscriptLine]; existingStart: int;
               history: openArray[TranscriptLine]; historyStart: int): int =
  ## Length of the identical run starting at the two positions.
  while existingStart + result < existing.len and
        historyStart + result < history.len and
        existing[existingStart + result] == history[historyStart + result]:
    inc result

func linesToAppend*(existing, history: openArray[TranscriptLine]): seq[TranscriptLine] =
  ## Messages of `history` that the stored transcript does not hold yet.
  ##
  ## Two alignments are tried and the longer match wins:
  ## - the end of the transcript matches a run of the history (the usual
  ##   case, also after trimming). Anything before that run in the history
  ##   was not said by anyone (a compaction summary) and is not logged;
  ## - the start of the history matches a run inside the transcript (after a
  ##   rewind). The transcript keeps the rewound messages.
  ## With no match at all the history is appended whole.
  if history.len == 0:
    return
  if existing.len == 0:
    return @history

  var tailRun = 0
  var tailEnd = 0   ## index in history right after the matched run
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

  let resumeAt =
    if tailRun >= headRun and tailRun > 0: tailEnd
    elif headRun > 0: headRun
    else: 0
  for i in resumeAt ..< history.len:
    result.add(history[i])
