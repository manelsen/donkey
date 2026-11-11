## commitment_pure — explicit promise / commitment domain model.
## Pure functions only. No I/O.

import std/[options, sequtils, strutils]
from std/unicode import toLower
import ../reminder

type
  CommitmentOwner* = enum
    coUser, coAgent

  CommitmentStatus* = enum
    csOpen, csDone, csBroken, csCancelled

  Commitment* = object
    id*:         string
    owner*:      CommitmentOwner
    status*:     CommitmentStatus
    dueAt*:      Option[int64]
    score*:      float32
    sourceText*: string

func slugToken(text: string): string =
  let cleaned = text.toLowerAscii().mapIt(
    if it.isAlphaNumeric(): it else: ' '
  ).join("")
  let words = cleaned.splitWhitespace()
  words[0 ..< min(words.len, 4)].join("-")

func commitmentId*(owner: CommitmentOwner; sourceText: string): string =
  let prefix = if owner == coUser: "user" else: "agent"
  let slug = slugToken(sourceText)
  if slug.len > 0: prefix & "-" & slug else: prefix & "-commitment"

func containsAny(text: string; patterns: openArray[string]): bool =
  for pattern in patterns:
    if text.contains(pattern):
      return true
  false

func extractDueAt*(sourceText: string; nowSec: int64): Option[int64] =
  let lower = toLower(sourceText)
  if "tomorrow" in lower or "amanhã" in lower or "amanha" in lower:
    return some(nowSec + 86_400)
  let normalized = sourceText.multiReplace((",", " "), ("?", " "), (".", " "))
  for token in normalized.splitWhitespace():
    if token.startsWith("+"):
      return some(parseWhen(token, nowSec))
    if token.len == 10 and token[4] == '-' and token[7] == '-':
      return some(parseWhen(token, nowSec))
    if token.len >= 19 and token[4] == '-' and token[7] == '-' and token[10] in {'T', ' '}:
      return some(parseWhen(token, nowSec))
  none(int64)

func commitmentScore*(c: Commitment; nowSec: int64 = 0): float32 =
  case c.status
  of csDone:
    1.0'f32
  of csBroken:
    0.0'f32
  of csCancelled:
    0.35'f32
  of csOpen:
    if c.dueAt.isSome and nowSec > 0 and c.dueAt.get() < nowSec:
      0.25'f32
    elif c.dueAt.isSome:
      0.85'f32
    else:
      0.7'f32

func newCommitment*(owner: CommitmentOwner;
                    sourceText: string;
                    nowSec: int64 = 0;
                    dueAt: Option[int64] = none(int64)): Commitment =
  let resolvedDueAt =
    if dueAt.isSome: dueAt
    else: extractDueAt(sourceText, nowSec)
  result = Commitment(
    id: commitmentId(owner, sourceText),
    owner: owner,
    status: csOpen,
    dueAt: resolvedDueAt,
    score: 0.0'f32,
    sourceText: sourceText.strip(),
  )
  result.score = commitmentScore(result, nowSec)

func parseUserRequestedCommitment*(sourceText: string;
                                   nowSec: int64 = 0): Option[Commitment] =
  let lower = toLower(sourceText)
  if lower.containsAny([
      "remind me",
      "can you remind",
      "could you remind",
      "please remember to",
      "don't let me forget",
      "can you send",
      "could you send",
      "can you follow up",
      "could you follow up",
      "can you check",
      "could you check",
      "lembre-me",
      "lembre de",
      "lembra de",
      "não esqueça",
      "nao esqueca",
      "pode lembrar",
      "pode enviar",
      "pode verificar",
      "pode acompanhar",
      "me avise",
      "me avisa",
    ]):
    return some(newCommitment(coUser, sourceText, nowSec))
  none(Commitment)

func parseAgentPromisedCommitment*(sourceText: string;
                                   nowSec: int64 = 0): Option[Commitment] =
  let lower = toLower(sourceText)
  if lower.containsAny([
      "i will",
      "i'll",
      "i promise",
      "i can follow up",
      "i can send",
      "i can check",
      "i will remind",
      "i will send",
      "i will follow up",
      "i will check",
      "vou enviar",
      "vou lembrar",
      "vou verificar",
      "vou acompanhar",
      "eu vou",
      "prometo",
      "posso enviar",
      "posso verificar",
      "posso acompanhar",
    ]):
    return some(newCommitment(coAgent, sourceText, nowSec))
  none(Commitment)

func withStatus(c: Commitment; status: CommitmentStatus; nowSec: int64 = 0): Commitment =
  result = c
  result.status = status
  result.score = commitmentScore(result, nowSec)

func markCompleted*(c: Commitment; nowSec: int64 = 0): Commitment =
  c.withStatus(csDone, nowSec)

func markBroken*(c: Commitment; nowSec: int64 = 0): Commitment =
  c.withStatus(csBroken, nowSec)

func cancel*(c: Commitment; nowSec: int64 = 0): Commitment =
  c.withStatus(csCancelled, nowSec)
