## Adaptive debounce unit tests.
##
## Covers all three pipeops operators:
##   |>   — mergeFragments, markFlushed, flushText (unary transforms)
##   |>-> — appendFragment, shouldFlush (state as last arg)
##   >>=  — validateState >>= toMergedText (fallible Result chain)

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/debounce

# ── windowMs ──────────────────────────────────────────────────────────────────

suite "debounce — windowMs":

  test "single fragment, long message → MinWindowMs":
    check windowMs(1, 100) == MinWindowMs

  test "single fragment, short message → MinWindowMs + ShortExtMs":
    check windowMs(1, 10) == MinWindowMs + ShortExtMs

  test "two fragments, long last → MinWindowMs + PerPartExtMs":
    check windowMs(2, 100) == MinWindowMs + PerPartExtMs

  test "two fragments, short last → capped with ShortExtMs":
    check windowMs(2, 5) == MinWindowMs + PerPartExtMs + ShortExtMs

  test "many fragments clamp to MaxWindowMs":
    check windowMs(20, 5) == MaxWindowMs

  test "ShortMsgThreshold boundary — at threshold is NOT short":
    check windowMs(1, ShortMsgThreshold) == MinWindowMs

  test "ShortMsgThreshold boundary — below threshold is short":
    check windowMs(1, ShortMsgThreshold - 1) == MinWindowMs + ShortExtMs

# ── initDebounce ──────────────────────────────────────────────────────────────

suite "debounce — initDebounce":

  test "creates state with single part":
    let s = initDebounce("hello", 1000)
    check s.parts == @["hello"]
    check s.firstMs == 1000
    check s.lastMs  == 1000
    check s.flushed == false

  test "empty text is stored as-is":
    let s = initDebounce("", 500)
    check s.parts == @[""]
    check s.parts.len == 1

# ── appendFragment |>-> ───────────────────────────────────────────────────────

suite "debounce — appendFragment |>->":

  test "appends a fragment and updates lastMs":
    let s0 = initDebounce("first", 1000)
    let s1 = s0 |>-> appendFragment("second", 1500)
    check s1.parts == @["first", "second"]
    check s1.firstMs == 1000
    check s1.lastMs  == 1500
    check s1.flushed == false

  test "chained appends accumulate parts":
    let s0 = initDebounce("a", 0)
    let s1 = (s0 |>-> appendFragment("b", 100)) |>-> appendFragment("c", 200)
    check s1.parts == @["a", "b", "c"]
    check s1.lastMs == 200

  test "appending to flushed state clears flushed flag":
    let sf = initDebounce("x", 0) |> markFlushed
    check sf.flushed == true
    let s1 = sf |>-> appendFragment("y", 100)
    check s1.flushed == false
    check s1.parts == @["x", "y"]

# ── shouldFlush |>-> ──────────────────────────────────────────────────────────

suite "debounce — shouldFlush |>->":

  test "window not yet expired → false":
    let s = initDebounce("hi", 0)
    check not (s |>-> shouldFlush(100))

  test "exactly at window boundary → true":
    let s  = initDebounce("hi", 0)
    let win = windowMs(1, "hi".len)
    check s |>-> shouldFlush(win)

  test "past window → true":
    let s = initDebounce("hello world, this is a long enough message", 0)
    check s |>-> shouldFlush(MaxWindowMs + 1)

  test "already flushed → false even past window":
    let sf = initDebounce("hi", 0) |> markFlushed
    check not (sf |>-> shouldFlush(MaxWindowMs + 1))

  test "empty parts → false":
    let s = DebounceState(parts: @[], firstMs: 0, lastMs: 0)
    check not (s |>-> shouldFlush(9999))

  test "multi-part: window extends with more fragments":
    let s0  = initDebounce("a", 0)
    let s2  = (s0 |>-> appendFragment("b", 100)) |>-> appendFragment("c", 200)
    let win = windowMs(3, "c".len)
    # before window expires
    check not (s2 |>-> shouldFlush(200 + win - 1))
    # at window expiry
    check s2 |>-> shouldFlush(200 + win)

# ── markFlushed |> ────────────────────────────────────────────────────────────

suite "debounce — markFlushed |>":

  test "sets flushed = true":
    let s  = initDebounce("msg", 0)
    let sf = s |> markFlushed
    check sf.flushed == true

  test "parts and timestamps preserved":
    let s  = initDebounce("msg", 500)
    let sf = s |> markFlushed
    check sf.parts   == s.parts
    check sf.firstMs == s.firstMs
    check sf.lastMs  == s.lastMs

  test "original state is not mutated":
    let s  = initDebounce("msg", 0)
    let _  = s |> markFlushed
    check s.flushed == false

# ── mergeFragments |> ─────────────────────────────────────────────────────────

suite "debounce — mergeFragments |>":

  test "empty seq → empty string":
    let parts: seq[string] = @[]
    check parts |> mergeFragments == ""

  test "single part → unchanged":
    check @["hello"] |> mergeFragments == "hello"

  test "two parts → joined with newline":
    check @["hello", "world"] |> mergeFragments == "hello\nworld"

  test "three parts → joined with newlines":
    check @["a", "b", "c"] |> mergeFragments == "a\nb\nc"

  test "empty part in middle is skipped":
    check @["a", "", "b"] |> mergeFragments == "a\nb"

  test "leading empty part is included (first part)":
    check @["", "b"] |> mergeFragments == "\nb"

# ── flushText |> ─────────────────────────────────────────────────────────────

suite "debounce — flushText |>":

  test "single fragment flushes unchanged":
    let s = initDebounce("hello", 0)
    check s |> flushText == "hello"

  test "two fragments joined with newline":
    let s = (initDebounce("hello", 0)) |>-> appendFragment("world", 100)
    check s |> flushText == "hello\nworld"

  test "flushed state still returns text":
    let s = initDebounce("msg", 0) |> markFlushed
    check s |> flushText == "msg"

# ── validateState >>= toMergedText ────────────────────────────────────────────

suite "debounce — validateState >>=":

  test "valid state passes through":
    let s = initDebounce("hello", 0)
    let r = validateState(s)
    check r.isOk
    check r.get().parts == @["hello"]

  test "flushed state returns Err":
    let sf = initDebounce("hello", 0) |> markFlushed
    let r  = validateState(sf)
    check r.isErr
    check "flushed" in r.error

  test "empty parts returns Err":
    let s = DebounceState(parts: @[], firstMs: 0, lastMs: 0)
    let r = validateState(s)
    check r.isErr
    check "no fragments" in r.error

  test ">>= chains validateState into toMergedText":
    let s = initDebounce("hello", 0)
    let r = validateState(s) >>= toMergedText
    check r.isOk
    check r.get() == "hello"

  test ">>= short-circuits on flushed state":
    let sf = initDebounce("hello", 0) |> markFlushed
    let r  = validateState(sf) >>= toMergedText
    check r.isErr

  test ">>= multi-fragment merge":
    let s = (initDebounce("part1", 0)) |>-> appendFragment("part2", 100)
    let r = validateState(s) >>= toMergedText
    check r.isOk
    check r.get() == "part1\npart2"

# ── full debounce lifecycle ───────────────────────────────────────────────────

suite "debounce — full lifecycle":

  test "receive, accumulate, flush":
    let s0 = initDebounce("Hello", 0)
    check not (s0 |>-> shouldFlush(500))
    let s1 = s0 |>-> appendFragment("world", 800)
    check not (s1 |>-> shouldFlush(900))
    let win = windowMs(s1.parts.len, s1.parts[^1].len)
    check s1 |>-> shouldFlush(800 + win)
    let text = s1 |> flushText
    check "Hello" in text
    check "world" in text
    let sf = s1 |> markFlushed
    check not (sf |>-> shouldFlush(99999))

  test "single fast message flushes after MinWindowMs":
    let longMsg = "This is a complete sentence with enough words to not be short."
    let s   = initDebounce(longMsg, 1000)
    check not (s |>-> shouldFlush(1000 + MinWindowMs - 1))
    check s |>-> shouldFlush(1000 + MinWindowMs)

  test "short burst extends to MaxWindowMs":
    var s = initDebounce("a", 0)
    for i in 1..12:
      s = s |>-> appendFragment("x", int64(i) * 50)
    check windowMs(s.parts.len, 1) == MaxWindowMs
