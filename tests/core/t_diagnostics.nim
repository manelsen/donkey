## t_diagnostics.nim — unit tests for core/diagnostics.nim
##
## Covers DiagResult construction, status transitions, counters,
## and pipeline-operator usage (|>, |>->, >>=).

import std/[strutils, unittest]
import donkey/core/diagnostics
import donkey/core/pipeops

# ── toDiagResult (|>-> friendly) ──────────────────────────────────────────────

suite "diagnostics — toDiagResult":

  test "Ok result gives dsOk":
    let r = toDiagResult("docker", Result[string, string].ok("v24.0"))
    check r.status == dsOk
    check r.name   == "docker"
    check "v24.0"  in r.detail

  test "Err result gives dsErr":
    let r = toDiagResult("docker", Result[string, string].err("not found"))
    check r.status == dsErr
    check r.name   == "docker"
    check "not found" in r.detail

  test "|>-> pipes Result as last arg to toDiagResult":
    let r = Result[string, string].ok("v24") |>-> toDiagResult("binary")
    check r.status == dsOk
    check r.name   == "binary"

  test "|>-> Err pipes correctly":
    let r = Result[string, string].err("missing") |>-> toDiagResult("tool")
    check r.status == dsErr

# ── markWarn (|> friendly) ────────────────────────────────────────────────────

suite "diagnostics — markWarn":

  test "markWarn downgrades dsErr to dsWarn":
    let r = toDiagResult("pg", Result[string, string].err("not set")) |> markWarn
    check r.status == dsWarn

  test "markWarn preserves dsOk":
    let r = toDiagResult("pg", Result[string, string].ok("set")) |> markWarn
    check r.status == dsOk

  test "markWarn preserves dsWarn":
    let r = DiagResult(name: "x", status: dsWarn, detail: "d") |> markWarn
    check r.status == dsWarn

  test "markWarn preserves name and detail":
    let r = toDiagResult("pg", Result[string, string].err("reason")) |> markWarn
    check r.name   == "pg"
    check "reason" in r.detail

# ── countFailed (|> friendly) ─────────────────────────────────────────────────

suite "diagnostics — countFailed":

  test "empty seq gives 0":
    let results: seq[DiagResult] = @[]
    check (results |> countFailed) == 0

  test "all ok gives 0":
    let results = @[
      toDiagResult("a", Result[string, string].ok("good")),
      toDiagResult("b", Result[string, string].ok("good")),
    ]
    check (results |> countFailed) == 0

  test "one error gives 1":
    let results = @[
      toDiagResult("a", Result[string, string].ok("good")),
      toDiagResult("b", Result[string, string].err("bad")),
    ]
    check (results |> countFailed) == 1

  test "two errors give 2":
    let results = @[
      toDiagResult("a", Result[string, string].err("x")),
      toDiagResult("b", Result[string, string].err("y")),
    ]
    check (results |> countFailed) == 2

  test "warnings do not count as failures":
    let results = @[
      toDiagResult("a", Result[string, string].err("warn")) |> markWarn,
    ]
    check (results |> countFailed) == 0

# ── allPassed (|> friendly) ───────────────────────────────────────────────────

suite "diagnostics — allPassed":

  test "all ok → true":
    let results = @[toDiagResult("a", Result[string, string].ok("good"))]
    check results |> allPassed

  test "any err → false":
    let results = @[toDiagResult("a", Result[string, string].err("bad"))]
    check not (results |> allPassed)

  test "warnings count as passed":
    let results = @[toDiagResult("a", Result[string, string].err("opt")) |> markWarn]
    check results |> allPassed

  test "empty seq → true (vacuously)":
    let results: seq[DiagResult] = @[]
    check results |> allPassed

# ── formatResult (|> friendly) ────────────────────────────────────────────────

suite "diagnostics — formatResult":

  test "ok result contains [OK] and name":
    let line = toDiagResult("docker", Result[string, string].ok("v24.0")) |> formatResult
    check "[OK]"  in line
    check "docker" in line
    check "v24.0"  in line

  test "err result contains [FAIL]":
    let line = toDiagResult("docker", Result[string, string].err("not found")) |> formatResult
    check "[FAIL]" in line

  test "warn result contains [WARN]":
    let line = (toDiagResult("pg", Result[string, string].err("opt")) |> markWarn) |> formatResult
    check "[WARN]" in line

# ── formatReport (|>-> friendly) ──────────────────────────────────────────────

suite "diagnostics — formatReport":

  test "report contains title":
    let results = @[toDiagResult("docker", Result[string, string].ok("v24"))]
    let report  = results |>-> formatReport("Donkey Doctor")
    check "Donkey Doctor" in report

  test "report contains all check names":
    let results = @[
      toDiagResult("docker",   Result[string, string].ok("v24")),
      toDiagResult("pgvector", Result[string, string].err("opt")) |> markWarn,
    ]
    let report = results |>-> formatReport("Diagnostics")
    check "docker"   in report
    check "pgvector" in report

  test "report includes status markers":
    let results = @[
      toDiagResult("a", Result[string, string].ok("pass")),
      toDiagResult("b", Result[string, string].err("fail")),
    ]
    let report = results |>-> formatReport("Test")
    check "[OK]"   in report
    check "[FAIL]" in report

# ── >>= chaining ──────────────────────────────────────────────────────────────

suite "diagnostics — Result >>= chaining":

  test ">>= Ok passes value through":
    func addSuffix(s: string): Result[string, string] {.gcsafe, raises: [].} =
      ok(s & "-checked")
    let r = Result[string, string].ok("v24") >>= addSuffix
    check r.isOk
    check r.get() == "v24-checked"

  test ">>= Err short-circuits":
    func addSuffix(s: string): Result[string, string] {.gcsafe, raises: [].} =
      ok(s & "-checked")
    let r = Result[string, string].err("missing") >>= addSuffix
    check r.isErr
    check "missing" in r.error

  test ">>= into toDiagResult via |>->":
    func validate(s: string): Result[string, string] {.gcsafe, raises: [].} =
      if s.len > 0: ok(s) else: err("empty")
    let r = (Result[string, string].ok("v24") >>= validate) |>-> toDiagResult("tool")
    check r.status == dsOk
