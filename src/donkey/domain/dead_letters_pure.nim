## dead_letters_pure — replies the channel refused (second round, front 4).
##
## A plain text reply whose send failed is kept with its text and tried
## again at 1, 5 and 30 minutes; a fourth failure leaves it dead, visible to
## the operator (`donkey ctl deliveries`), until it is a week old. Partial
## stream pieces, edits, media and keyboards are not kept: an edit or a
## piece makes no sense later, and a file may be gone. A reply split in pieces that failed
## midway is sent whole again, so its first pieces may repeat: a reply that
## never arrives is the worse failure.

import std/[json, strutils]
import ../core/pipeops
import ../core/types
import ./message

const
  RetryDelaysMs* = [60_000'i64, 5 * 60_000, 30 * 60_000]
  MaxAgeMs* = 7 * 24 * 3_600_000'i64
  MaxDeadLetters* = 200
  PreviewChars = 80

type
  DeadLetter* = object
    id*:        string
    userId*:    string
    channel*:   ChannelKind
    replyTo*:   string
    text*:      string
    isHtml*:    bool
    attempts*:  int
    createdMs*: int64
    nextAtMs*:  int64
    lastError*: string
    dead*:      bool

func deadLetterEligible*(m: OutboundMessage): bool =
  ## A stream's final answer (not partial) is sent whole, so it qualifies.
  m.text.strip.len > 0 and not m.isPartial and
    m.editTargetId.len == 0 and m.replacementSlot.len == 0 and
    m.mediaUrl.len == 0 and m.keyboard.len == 0 and not m.replaceKeyboard

func schedule(l: var DeadLetter; error: string; nowMs: int64) =
  l.lastError = error
  if l.attempts > RetryDelaysMs.len:
    l.dead = true
    l.nextAtMs = 0
  else:
    l.nextAtMs = nowMs + RetryDelaysMs[l.attempts - 1]

func recordFailure*(letters: var seq[DeadLetter]; id: string; m: OutboundMessage;
                    error: string; nowMs: int64) =
  var l = DeadLetter(id: id, userId: $m.userId, channel: m.channel, replyTo: m.replyTo,
                     text: m.text, isHtml: m.isHtml, attempts: 1,
                     createdMs: nowMs)
  l.schedule(error, nowMs)
  letters.add l

func retryFailed*(letters: var seq[DeadLetter]; id, error: string; nowMs: int64) =
  for l in letters.mitems:
    if l.id == id:
      inc l.attempts
      l.schedule(error, nowMs)

func retrySucceeded*(letters: var seq[DeadLetter]; id: string) =
  var kept: seq[DeadLetter]
  for l in letters:
    if l.id != id: kept.add l
  letters = kept

func dueLetters*(letters: seq[DeadLetter]; nowMs: int64): seq[DeadLetter] =
  for l in letters:
    if not l.dead and l.nextAtMs > 0 and l.nextAtMs <= nowMs:
      result.add l

func prune*(letters: var seq[DeadLetter]; nowMs: int64) =
  var kept: seq[DeadLetter]
  for l in letters:
    if nowMs - l.createdMs <= MaxAgeMs: kept.add l
  if kept.len > MaxDeadLetters:
    kept = kept[kept.len - MaxDeadLetters .. ^1]
  letters = kept

func message*(l: DeadLetter): OutboundMessage =
  OutboundMessage(userId: UserId(l.userId), channel: l.channel, text: l.text,
                  replyTo: l.replyTo, isHtml: l.isHtml)

proc encodeDeadLetters*(letters: seq[DeadLetter]): string =
  var arr = newJArray()
  for l in letters:
    arr.add(%* {"id": l.id, "user": l.userId, "channel": $l.channel, "reply_to": l.replyTo,
                "text": l.text, "html": l.isHtml, "attempts": l.attempts,
                "created_ms": l.createdMs, "next_at_ms": l.nextAtMs,
                "last_error": l.lastError, "dead": l.dead})
  $arr

proc decodeDeadLetters*(text: string): Result[seq[DeadLetter], string] =
  if text.strip.len == 0:
    return ok(newSeq[DeadLetter]())
  let j =
    try: parseJson(text)
    except CatchableError: return err("the dead letters file is not JSON")
  if j.kind != JArray:
    return err("the dead letters file is not a list")
  var letters: seq[DeadLetter]
  for it in j:
    var kind: ChannelKind
    var found = false
    for k in ChannelKind:
      if $k == it{"channel"}.getStr:
        kind = k
        found = true
    if not found: continue   ## a channel this build no longer has
    letters.add DeadLetter(
      id: it{"id"}.getStr, userId: it{"user"}.getStr, channel: kind,
      replyTo: it{"reply_to"}.getStr, text: it{"text"}.getStr, isHtml: it{"html"}.getBool,
      attempts: it{"attempts"}.getInt,
      createdMs: it{"created_ms"}.getBiggestInt, nextAtMs: it{"next_at_ms"}.getBiggestInt,
      lastError: it{"last_error"}.getStr, dead: it{"dead"}.getBool)
  ok(letters)

func operatorLine*(l: DeadLetter): string =
  var preview = l.text.replace("\n", " ")
  if preview.len > PreviewChars: preview = preview[0 ..< PreviewChars] & "…"
  l.id & "  " & $l.channel & "  " & l.userId & "  " &
    (if l.dead: "dead" else: "retry " & $l.attempts & "/" & $RetryDelaysMs.len) &
    "  " & l.lastError & "  «" & preview & "»"
