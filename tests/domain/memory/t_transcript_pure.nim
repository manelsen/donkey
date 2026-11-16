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
