## editor_pairing_pure — pairing an editor with a person (E10.2).
##
## The device-flow shape: the editor asks for a pairing and gets back a short
## code to show and a long secret to keep; the person types `/editor <code>`
## on a channel where they are already known; the editor then collects its
## credential with the secret. Only the person's channel sees the short code
## being used, so nothing reachable from the network can be guessed.
##
## Pure: the table is a value, the clock and the random bytes come in.

import std/strutils
import ../../core/pipeops
import ../../core/types
import ../gateway/auth_pure   # constantTimeEq

const
  EditorPairingTtlMs* = 10 * 60 * 1000'i64
  MaxPendingPairings* = 32
  PairingAlphabet* = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    ## No 0/O, 1/I: the person reads it on one screen and types it on another.
  MaxEditorNameLen = 40

type
  PendingPairing = object
    secret, code, name: string
    createdMs: int64
    userId: UserId          ## set when the person confirms

  EditorPairings* = object
    pending: seq[PendingPairing]

  EditorPairingState* = enum
    epsUnknown     ## no such pairing, or it expired
    epsPending     ## not confirmed yet
    epsConfirmed   ## confirmed; collected now, gone afterwards

  EditorPairingPoll* = object
    state*: EditorPairingState
    userId*: UserId
    name*: string

func pairingCode*(bytes: openArray[byte]): string =
  ## Six characters of the alphabet from six random bytes.
  for i in 0 ..< 6:
    result.add PairingAlphabet[int(bytes[i]) mod PairingAlphabet.len]

func editorName*(raw: string): string =
  ## What the person is told is asking ("Zed"): letters, digits, spaces and a
  ## little punctuation, at most 40 characters.
  var name = ""
  var space = false
  for c in raw:
    if c.isAlphaNumeric or c in {'.', '-', '_'}:
      name.add c
      space = false
    elif name.len > 0 and not space:
      name.add ' '
      space = true
  name = name.strip
  if name.len == 0: "editor" else: name[0 ..< min(name.len, MaxEditorNameLen)]

func live(p: PendingPairing; now: int64): bool =
  now - p.createdMs <= EditorPairingTtlMs

func prune(t: var EditorPairings; now: int64) =
  var kept: seq[PendingPairing]
  for p in t.pending:
    if p.live(now): kept.add p
  t.pending = kept

func begin*(t: var EditorPairings; secret, code, name: string; now: int64): Result[void, string] =
  t.prune(now)
  if t.pending.len >= MaxPendingPairings:
    return err("too many editors waiting to pair; try again in a few minutes")
  for p in t.pending:
    if p.code == code or constantTimeEq(p.secret, secret):
      return err("pairing code in use")
  t.pending.add PendingPairing(secret: secret, code: code, name: editorName(name), createdMs: now)
  ok()

func confirm*(t: var EditorPairings; code: string; userId: UserId; now: int64): Result[string, string] =
  ## The person typed the code; answers the editor's name to tell them.
  t.prune(now)
  let wanted = code.strip.toUpperAscii
  for p in t.pending.mitems:
    if p.code == wanted:
      if ($p.userId).len > 0:
        return err("this code was already confirmed")
      p.userId = userId
      return ok(p.name)
  err("no editor is waiting with this code")

func collect*(t: var EditorPairings; secret: string; now: int64): EditorPairingPoll =
  t.prune(now)
  for i, p in t.pending:
    if constantTimeEq(p.secret, secret):
      if ($p.userId).len == 0:
        return EditorPairingPoll(state: epsPending)
      t.pending.delete(i)
      return EditorPairingPoll(state: epsConfirmed, userId: p.userId, name: p.name)
  EditorPairingPoll(state: epsUnknown)
