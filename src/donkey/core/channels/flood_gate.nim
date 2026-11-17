## flood_gate.nim — per-chat flood window for the Telegram Bot API.
##
## The API applies its send limit per chat and answers 429 with
## `parameters.retry_after`. Remembering that deadline per chat avoids hitting
## the API again inside the penalty, and keeps one chat's penalty from
## serialising every other chat.
##
## Pure state: callers pass the current time, so the window is testable without
## sleeping.

import std/[strutils, tables]
import ../pipeops

type
  FloodGate* = ref object
    ## chatId → epoch ms when the chat accepts sends again.
    windows*: Table[int64, int64]

const FloodMaxWaitMs* = 5_000'i64
  ## Longest wait applied inline; a longer penalty is left for the next send.

func newFloodGate*(): FloodGate =
  FloodGate(windows: initTable[int64, int64]())

proc noteRetryAfter*(gate: FloodGate; chatId: int64;
                     retryAfterMs, nowMs: int64) =
  ## Records the penalty returned by the API. Zero or negative values are
  ## ignored, and a shorter penalty never shortens an active window.
  if gate.isNil or retryAfterMs <= 0:
    return
  let untilMs = nowMs + retryAfterMs
  if untilMs > gate.windows.getOrDefault(chatId, 0'i64):
    gate.windows[chatId] = untilMs

func remainingMs*(gate: FloodGate; chatId: int64; nowMs: int64): int64 =
  ## Milliseconds until `chatId` accepts sends again; 0 when open.
  if gate.isNil:
    return 0
  let untilMs = gate.windows.getOrDefault(chatId, 0'i64)
  if untilMs <= nowMs: 0 else: untilMs - nowMs

proc clearExpired*(gate: FloodGate; nowMs: int64) =
  ## Drops windows that already elapsed, so the table does not grow forever.
  if gate.isNil:
    return
  var expired: seq[int64] = @[]
  for chatId, untilMs in gate.windows:
    if untilMs <= nowMs:
      expired.add(chatId)
  for chatId in expired:
    gate.windows.del(chatId)

func parseRetryAfterMs*(errorText: string): int64 =
  ## Behavior derived from hermes-agent (MIT) fix 404b06ac4f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-012
  ##
  ## Extracts `parameters.retry_after` (seconds) from the API error text.
  ## Returns 0 when the error is not a flood refusal.
  const marker = "\"retry_after\":"
  let at = errorText.find(marker)
  if at < 0:
    return 0
  var i = at + marker.len
  while i < errorText.len and errorText[i] in {' ', '\t'}:
    inc i
  var digits = ""
  while i < errorText.len and errorText[i] in {'0' .. '9'}:
    digits.add(errorText[i])
    inc i
  if digits.len == 0:
    return 0
  let seconds = try:
    parseInt(digits)
  except ValueError:
    return 0
  if seconds <= 0: 0 else: int64(seconds) * 1000

func isFloodRefusal*(errorText: string): bool =
  ## True when the API refused the call for flood control.
  parseRetryAfterMs(errorText) > 0

func shouldRetryChunk*(errorText: string; alreadyRetried: bool): bool =
  ## Behavior derived from hermes-agent (MIT) fix 595f3a289c; see
  ## docs/hermes-mining/telegram/CASES.md#tg-013
  ##
  ## A chunk refused by flood control is retried once, after the window; the
  ## chunks already delivered are never resent.
  not alreadyRetried and isFloodRefusal(errorText)
