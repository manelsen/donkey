import std/unittest
import donkey/domain/memory/transcript_pure

func line(role, text: string): TranscriptLine =
  TranscriptLine(role: role, text: text)

func conversation(first, last: int): seq[TranscriptLine] =
  for i in first .. last:
    result.add(line(if i mod 2 == 1: "user" else: "assistant", "m" & $i))

suite "transcript — what a history snapshot adds to the stored log":

  test "empty log receives the whole history":
    check linesToAppend(newSeq[TranscriptLine](), conversation(1, 4)) ==
      conversation(1, 4)

  test "unchanged history adds nothing":
    check linesToAppend(conversation(1, 4), conversation(1, 4)).len == 0

  test "growing history adds only the new messages":
    check linesToAppend(conversation(1, 4), conversation(1, 6)) ==
      conversation(5, 6)

  test "history trimmed at the front still adds only the new messages":
    ## The live history keeps the last N messages; the log keeps everything.
    check linesToAppend(conversation(1, 20), conversation(3, 22)) ==
      conversation(21, 22)

  test "stored log stays complete across many trimmed saves":
    var log: seq[TranscriptLine]
    for last in countup(2, 60, 2):
      let first = max(1, last - 19)
      log.add(linesToAppend(log, conversation(first, last)))
    check log == conversation(1, 60)

  test "a synthetic summary at the head of the history is not logged":
    ## Compaction replaces old messages with a summary that nobody said.
    let history = @[line("system", "resumo")] & conversation(5, 8)
    check linesToAppend(conversation(1, 6), history) == conversation(7, 8)

  test "summary keeps being ignored on later saves":
    var log = conversation(1, 6)
    let summary = @[line("system", "resumo")]
    log.add(linesToAppend(log, summary & conversation(5, 8)))
    log.add(linesToAppend(log, summary & conversation(5, 10)))
    check log == conversation(1, 10)

  test "rewound history keeps the log and adds what came after":
    ## Messages 5 and 6 were rewound; the log is append-only and keeps them.
    let history = conversation(1, 4) & @[line("user", "outra pergunta")]
    check linesToAppend(conversation(1, 6), history) ==
      @[line("user", "outra pergunta")]

  test "rewind alone adds nothing":
    check linesToAppend(conversation(1, 6), conversation(1, 4)).len == 0

  test "repeated identical messages do not confuse the alignment":
    let log = @[line("user", "ok"), line("assistant", "certo"),
                line("user", "ok"), line("assistant", "certo")]
    let history = log & @[line("user", "ok"), line("assistant", "feito")]
    check linesToAppend(log, history) ==
      @[line("user", "ok"), line("assistant", "feito")]

  test "unrelated history is appended whole":
    check linesToAppend(conversation(1, 4), conversation(11, 12)) ==
      conversation(11, 12)

  test "empty history adds nothing":
    check linesToAppend(conversation(1, 4), newSeq[TranscriptLine]()).len == 0
