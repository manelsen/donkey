## Tests for the per-chat Telegram flood window.

import std/[tables, unittest]
import donkey/core/channels/flood_gate

suite "flood gate — per chat window":

  test "TG-012: a fresh chat is open":
    let gate = newFloodGate()
    check gate.remainingMs(10, 1_000) == 0

  test "TG-012: a retry_after closes only that chat":
    let gate = newFloodGate()
    gate.noteRetryAfter(10, 4_000, 1_000)
    check gate.remainingMs(10, 1_000) == 4_000
    check gate.remainingMs(10, 4_000) == 1_000
    check gate.remainingMs(10, 5_000) == 0
    check gate.remainingMs(11, 1_000) == 0

  test "TG-012: a shorter penalty does not shorten the window":
    let gate = newFloodGate()
    gate.noteRetryAfter(10, 4_000, 1_000)
    gate.noteRetryAfter(10, 1_000, 2_000)
    check gate.remainingMs(10, 2_000) == 3_000

  test "TG-012: a longer penalty extends the window":
    let gate = newFloodGate()
    gate.noteRetryAfter(10, 1_000, 1_000)
    gate.noteRetryAfter(10, 5_000, 1_500)
    check gate.remainingMs(10, 1_500) == 5_000

  test "TG-012: expired windows are dropped":
    let gate = newFloodGate()
    gate.noteRetryAfter(10, 1_000, 1_000)
    gate.noteRetryAfter(11, 9_000, 1_000)
    gate.clearExpired(3_000)
    check gate.windows.len == 1
    check gate.windows.hasKey(11)

  test "TG-012: a nil gate is safe":
    var gate: FloodGate
    check gate.remainingMs(1, 1) == 0
    gate.noteRetryAfter(1, 1_000, 1)
    check gate.remainingMs(1, 1) == 0

suite "flood gate — retry_after parsing":

  test "TG-012: parses the API parameters":
    let error = """Telegram API error [sendMessage]: {"ok":false,"error_code":429,"description":"Too Many Requests: retry after 7","parameters":{"retry_after":7}}"""
    check parseRetryAfterMs(error) == 7_000
    check isFloodRefusal(error)

  test "TG-012: tolerates spaces after the colon":
    check parseRetryAfterMs("""{"parameters":{"retry_after": 3}}""") == 3_000

  test "TG-012: a non-flood error is not a refusal":
    check parseRetryAfterMs("chat not found") == 0
    check not isFloodRefusal("chat not found")
    check parseRetryAfterMs("""{"retry_after":0}""") == 0

suite "flood gate — chunk retry decision":

  test "TG-013: a flood refusal is retried once":
    let error = """{"parameters":{"retry_after":2}}"""
    check shouldRetryChunk(error, false)
    check not shouldRetryChunk(error, true)

  test "TG-013: other errors are not retried":
    check not shouldRetryChunk("chat not found", false)
