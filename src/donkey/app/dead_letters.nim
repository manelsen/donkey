## dead_letters — the daemon's dead letter box (second round, front 4).
##
## Replies the channel refused (domain/dead_letters_pure says which and when
## to retry) are kept in `{home}/state/dead_letters.json`, private, through
## the fs port. The box lives on the daemon loop: the outbound runtime keeps
## a failure in it, and the loop retries what is due through the send it is
## given. A file it cannot read is left alone (`problem` says why) and
## nothing is saved over it.

import std/[os, strutils]
import ../core/pipeops
import ../domain/dead_letters_pure
import ../domain/message
import ../ports/fs

type
  DeadLetterSend* = proc(m: OutboundMessage): Result[void, string] {.gcsafe.}

  DeadLetterBox* = ref object
    fs:        FsRuntimePort
    path*:     string
    letters*:  seq[DeadLetter]
    problem*:  string   ## why the file could not be read; nothing is saved then
    counter:   int

proc newDeadLetterBox*(fs: FsRuntimePort; path: string): DeadLetterBox =
  result = DeadLetterBox(fs: fs, path: path)
  let text = fs.readFile(path)
  if text.isErr:
    return   ## no file yet
  let decoded = decodeDeadLetters(text.get)
  if decoded.isErr:
    result.problem = decoded.error
  else:
    result.letters = decoded.get

proc save(box: DeadLetterBox): Result[void, string] =
  if box.problem.len > 0:
    return err("dead letters not saved: " & box.problem)
  ? box.fs.createDir(parentDir(box.path))
  box.fs.writePrivate(box.path, encodeDeadLetters(box.letters))

proc keep*(box: DeadLetterBox; m: OutboundMessage; error: string; nowMs: int64): Result[void, string] {.discardable.} =
  ## A reply whose send failed; ignored when it does not qualify.
  if box.isNil or not deadLetterEligible(m):
    return ok()
  inc box.counter
  box.letters.recordFailure("d" & $nowMs & "-" & $box.counter, m, error, nowMs)
  box.letters.prune(nowMs)
  box.save()

proc retryDue*(box: DeadLetterBox; nowMs: int64; send: DeadLetterSend): int =
  ## Sends again what is due; returns how many were tried.
  if box.isNil: return 0
  for l in dueLetters(box.letters, nowMs):
    inc result
    let sent = send(l.message)
    if sent.isOk: box.letters.retrySucceeded(l.id)
    else: box.letters.retryFailed(l.id, sent.error, nowMs)
  box.letters.prune(nowMs)
  if result > 0:
    discard box.save()
