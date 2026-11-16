import std/unittest
import donkey/domain/memory/transcript_pure
import donkey/domain/message

func line(role, text: string; seq = 0'i64): TranscriptLine =
  TranscriptLine(role: role, text: text, seq: seq)

func conversation(first, last: int; numbered = false): seq[TranscriptLine] =
  for i in first .. last:
    result.add(line(if i mod 2 == 1: "user" else: "assistant", "m" & $i,
                    if numbered: i.int64 else: 0))

func appended(existing, history: seq[TranscriptLine]): seq[TranscriptLine] =
  for index in messagesToAppend(existing, history):
    result.add(history[index])

suite "transcript — numbered messages":

  test "empty log receives the whole history":
    check appended(@[], conversation(1, 4, numbered = true)) ==
      conversation(1, 4, numbered = true)

  test "unchanged history adds nothing":
    let history = conversation(1, 4, numbered = true)
    check appended(history, history).len == 0

  test "history trimmed at the front adds only the new messages":
    check appended(conversation(1, 20, numbered = true),
                   conversation(3, 22, numbered = true)) ==
      conversation(21, 22, numbered = true)

  test "identical repeated exchanges are all kept":
    ## Ten "ok / certo" pairs, then one more pair while the first is trimmed:
    ## by content the window looks unchanged, by number it does not.
    var log: seq[TranscriptLine]
    for i in 1 .. 20:
      log.add(line(if i mod 2 == 1: "user" else: "assistant",
                   if i mod 2 == 1: "ok" else: "certo", i.int64))
    var history = log[2 .. ^1]
    history.add(line("user", "ok", 21))
    history.add(line("assistant", "certo", 22))
    check appended(log, history) ==
      @[line("user", "ok", 21), line("assistant", "certo", 22)]

  test "rewind, a new message, then another one never duplicate":
    var log = conversation(1, 6, numbered = true)
    let x = line("user", "X", 7)
    let y = line("assistant", "Y", 8)
    let afterRewind = conversation(1, 4, numbered = true) & @[x]
    check appended(log, afterRewind) == @[x]
    log.add(appended(log, afterRewind))
    check appended(log, afterRewind).len == 0
    let next = afterRewind & @[y]
    check appended(log, next) == @[y]

  test "a message repeated after a rewind is a new message":
    let log = conversation(1, 6, numbered = true)
    let again = line("assistant", "m6", 7)
    check appended(log, conversation(1, 4, numbered = true) & @[again]) == @[again]

  test "a synthetic summary is never logged":
    let summary = line("user", "resumo", SyntheticMessageSeq)
    let history = @[summary] & conversation(5, 8, numbered = true)
    check appended(conversation(1, 6, numbered = true), history) ==
      conversation(7, 8, numbered = true)

  test "summary plus rewound window adds nothing":
    let summary = line("user", "resumo", SyntheticMessageSeq)
    let history = @[summary] & conversation(5, 6, numbered = true)
    check appended(conversation(1, 8, numbered = true), history).len == 0

  test "empty history adds nothing":
    check appended(conversation(1, 4, numbered = true), @[]).len == 0

suite "transcript — messages without numbers (older files and callers)":

  test "growing history adds only the new messages":
    check appended(conversation(1, 4), conversation(1, 6)) == conversation(5, 6)

  test "trimmed history adds only the new messages":
    check appended(conversation(1, 20), conversation(3, 22)) == conversation(21, 22)

  test "log stays complete across many trimmed saves":
    var log: seq[TranscriptLine]
    for last in countup(2, 60, 2):
      log.add(appended(log, conversation(max(1, last - 19), last)))
    check log == conversation(1, 60)

  test "a file written before numbering is extended without repeats":
    ## First save after an upgrade: the file has no numbers, the history has.
    check appended(conversation(1, 6), conversation(3, 8, numbered = true)) ==
      conversation(7, 8, numbered = true)

  test "a synthetic summary is ignored even when nothing aligns":
    let summary = line("user", "resumo", SyntheticMessageSeq)
    check appended(conversation(1, 8), @[summary] & conversation(5, 6)).len == 0

  test "rewound history keeps the log and adds what came after":
    let history = conversation(1, 4) & @[line("user", "outra pergunta")]
    check appended(conversation(1, 6), history) == @[line("user", "outra pergunta")]

  test "unrelated history is appended whole":
    check appended(conversation(1, 4), conversation(11, 12)) == conversation(11, 12)

suite "transcript — partial knowledge of what is stored":

  test "second save after an upgrade does not bring the old messages back":
    ## The file starts with lines written before numbering. After the first
    ## save it holds numbers 5 and 6 only; 1 to 4 are the unnumbered lines.
    var log = conversation(1, 4)
    let history = conversation(1, 6, numbered = true)
    log.add(appended(log, history))
    check log.len == 6
    check appended(log, history).len == 0
    let grown = conversation(1, 8, numbered = true)
    check appended(log, grown) == conversation(7, 8, numbered = true)

  test "a new message that repeats the words of an older line is still new":
    ## "ok" is in the unnumbered part, and said again as message 5.
    var log = @[line("user", "ok"), line("assistant", "certo")]
    log.add(line("user", "pergunta", 3))
    log.add(line("assistant", "resposta", 4))
    let history = @[line("user", "pergunta", 3), line("assistant", "resposta", 4),
                    line("user", "ok", 5)]
    check appended(log, history) == @[line("user", "ok", 5)]

  test "beside older unnumbered lines, a low number with new content is new":
    ## Number 4 was given at a checkpoint and rewound before any save; the
    ## unnumbered lines do not hold its text.
    var log = conversation(1, 2)
    log.add(line("user", "m6", 6))
    let history = @[line("user", "m1", 1), line("assistant", "m2", 2),
                    line("user", "nunca gravada", 4)]
    check appended(log, history) == @[line("user", "nunca gravada", 4)]

  test "a low number that is absent from the whole file is new":
    let log = @[line("user", "m1", 1), line("assistant", "m2", 2),
                line("user", "m6", 6)]
    let history = @[line("user", "m1", 1), line("assistant", "m2", 2),
                    line("user", "m4", 4)]
    check appended(log, history) == @[line("user", "m4", 4)]

suite "transcript — when the end of the file is not enough":

  test "the tail is enough while every unknown number is above it":
    let tail = conversation(101, 120, numbered = true)
    check not needsWholeTranscript(tail, conversation(111, 122, numbered = true))
    check not needsWholeTranscript(tail, conversation(101, 120, numbered = true))

  test "a number below the tail calls for the whole file":
    let tail = conversation(101, 120, numbered = true)
    check needsWholeTranscript(tail, conversation(41, 44, numbered = true))

  test "a tail without any complete record calls for the whole file":
    check needsWholeTranscript(@[], conversation(1, 2, numbered = true))

  test "a history without numbers calls for the whole file":
    ## Content is all there is to compare, so every stored line matters.
    check needsWholeTranscript(conversation(101, 120, numbered = true),
                               conversation(1, 4))
    check needsWholeTranscript(conversation(101, 120), conversation(1, 4))

  test "only synthetic messages never call for the whole file":
    check not needsWholeTranscript(
      conversation(101, 120, numbered = true),
      @[line("user", "resumo", SyntheticMessageSeq)])

  test "gap plus partial read: the missing number is written, the old ones are not":
    ## The file holds 1, 2 and 6 to 120; 4 was never saved. Only 101 to 120
    ## are in the tail. A restored checkpoint brings back 1, 2 and 4.
    let whole = @[line("user", "m1", 1), line("assistant", "m2", 2)] &
                conversation(6, 120, numbered = true)
    let tail = whole[^20 .. ^1]
    let restored = @[line("user", "m1", 1), line("assistant", "m2", 2),
                     line("user", "m4", 4)]
    check needsWholeTranscript(tail, restored)
    check appended(whole, restored) == @[line("user", "m4", 4)]

  test "a low number written late does not hide the higher ones before it":
    ## The file holds 1, 2, 6 to 120 and then 4, written after a rewind. Only
    ## the line of 4 fits in the tail; it records that 120 is in the file.
    let tail = @[TranscriptLine(role: "user", text: "m4", seq: 4, high: 120)]
    let restored = conversation(119, 120, numbered = true)
    check needsWholeTranscript(tail, restored)
    check not needsWholeTranscript(
      tail, @[line("user", "depois", 121)])

  test "highestNumber reads the watermark as well as the numbers":
    check highestNumber(@[TranscriptLine(seq: 4, high: 120)]) == 120
    check highestNumber(conversation(1, 6, numbered = true)) == 6
    check highestNumber(conversation(1, 6)) == 0

