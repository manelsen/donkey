## Adaptive message debounce — pure domain logic (nullclaw-style).
## Merges split messages using a timing/length-adaptive window (1.2 s–8 s).
##
## Split detection: when a channel delivers a user's thought in multiple rapid
## packets, debounce holds the first fragment open and accumulates subsequent
## fragments until the window expires.  The window adapts to typing speed:
## more fragments → longer window; long last fragment → shorter window.
##
## Pipeline topology (pipeops):
##   |>   — mergeFragments, markFlushed, flushText   (unary pure transforms)
##   |>-> — appendFragment, shouldFlush              (state/parts as last arg)
##   >>=  — validateState, toMergedText              (fallible Result chain)

import ./pipeops

# ── constants ──────────────────────────────────────────────────────────────────

const
  MinWindowMs*       = 1_200i64  ## base debounce window (1.2 s)
  MaxWindowMs*       = 8_000i64  ## maximum debounce window (8 s)
  PerPartExtMs*      = 800i64    ## extra ms added per additional fragment
  ShortMsgThreshold* = 40        ## chars — last fragment below this extends window
  ShortExtMs*        = 600i64    ## extra ms added when last fragment is short

# ── types ──────────────────────────────────────────────────────────────────────

type
  DebounceState* = object
    parts*:   seq[string]  ## collected text fragments (oldest first)
    firstMs*: int64        ## monotonic ms when first fragment arrived
    lastMs*:  int64        ## monotonic ms when last fragment arrived
    flushed*: bool         ## true after flush — reset via initDebounce

# ── pure window computation ────────────────────────────────────────────────────

func windowMs*(partCount: int; lastLen: int): int64 =
  ## Adaptive debounce window in milliseconds.
  ## More fragments → longer hold.  Short last message → extra hold.
  let base = MinWindowMs + (int64(partCount) - 1) * PerPartExtMs
  let ext   = if lastLen < ShortMsgThreshold: ShortExtMs else: 0i64
  min(base + ext, MaxWindowMs)

# ── state constructors and transformers ────────────────────────────────────────

func initDebounce*(text: string; nowMs: int64): DebounceState =
  ## Creates a fresh DebounceState for the first fragment.
  DebounceState(parts: @[text], firstMs: nowMs, lastMs: nowMs)

func appendFragment*(text: string; nowMs: int64; state: DebounceState): DebounceState =
  ## Appends a fragment and resets the deadline; does not mark flushed.
  ## Designed for |>->: `state |>-> appendFragment(text, nowMs)`
  DebounceState(
    parts:   state.parts & @[text],
    firstMs: state.firstMs,
    lastMs:  nowMs,
    flushed: false,
  )

func shouldFlush*(nowMs: int64; state: DebounceState): bool =
  ## True when the adaptive window has expired and state is not already flushed.
  ## Designed for |>->: `state |>-> shouldFlush(nowMs)`
  if state.flushed or state.parts.len == 0: return false
  let lastLen = state.parts[^1].len
  let win     = windowMs(state.parts.len, lastLen)
  nowMs - state.lastMs >= win

func markFlushed*(state: DebounceState): DebounceState =
  ## Returns a copy of state with flushed = true.
  ## Designed for |>: `state |> markFlushed`
  DebounceState(
    parts:   state.parts,
    firstMs: state.firstMs,
    lastMs:  state.lastMs,
    flushed: true,
  )

# ── fragment merging ───────────────────────────────────────────────────────────

func mergeFragments*(parts: seq[string]): string =
  ## Joins fragments with single newlines; skips empty parts.
  ## Designed for |>: `state.parts |> mergeFragments`
  if parts.len == 0: return ""
  if parts.len == 1: return parts[0]
  result = parts[0]
  for i in 1 ..< parts.len:
    if parts[i].len == 0: continue
    result &= "\n" & parts[i]

func flushText*(state: DebounceState): string =
  ## Returns the merged text of all fragments.
  ## Designed for |>: `state |> flushText`
  state.parts |> mergeFragments

# ── Result-returning functions for >>= chaining ────────────────────────────────

func validateState*(state: DebounceState): Result[DebounceState, string] =
  ## Err if state is already flushed or has no fragments; otherwise Ok(state).
  ## Entry point for >>= pipelines: `validateState(s) >>= toMergedText`
  if state.flushed:
    err("debounce state already flushed")
  elif state.parts.len == 0:
    err("debounce state has no fragments")
  else:
    ok(state)

func toMergedText*(state: DebounceState): Result[string, string] =
  ## Extracts merged text from a validated state (always succeeds when called).
  ## Designed for >>= chaining after validateState.
  ok(state |> flushText)
