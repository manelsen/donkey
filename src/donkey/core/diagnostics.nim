## diagnostics.nim — Pure diagnostic result types and pipeline-friendly functions.
##
## Models system dependency checks as typed results that compose cleanly
## via pipeops operators.
##
## Boundary: no Chronos, no I/O — only `func` and `import ./pipeops`.
##
## Pipeline usage:
##   runDockerCmd() |>-> toDiagResult("docker")   -- convert Result to DiagResult
##   r              |>  markWarn                   -- downgrade err to advisory
##   results        |>  countFailed                -- count hard failures
##   results        |>-> formatReport("Donkey Doctor")  -- full formatted report

import std/strutils
import ./pipeops

type
  DiagStatus* = enum
    dsOk    ## check passed — dependency is present and functional
    dsWarn  ## advisory — system can run but may be degraded (optional dep)
    dsErr   ## hard failure — required dependency is missing

  DiagResult* = object
    name*:   string
    status*: DiagStatus
    detail*: string

# ── construction (|>-> friendly — Result value is last arg) ───────────────────

func toDiagResult*(name: string; r: Result[string, string]): DiagResult =
  ## Converts a Result[string, string] into a DiagResult.
  ##   runDockerCmd() |>-> toDiagResult("docker")
  if r.isOk:
    DiagResult(name: name, status: dsOk,  detail: r.get())
  else:
    DiagResult(name: name, status: dsErr, detail: r.error)

# ── unary transforms (|> friendly — single arg, returns same shape) ───────────

func markWarn*(r: DiagResult): DiagResult =
  ## Downgrades dsErr to dsWarn; leaves dsOk and dsWarn unchanged.
  ## Use for optional dependencies that should not block startup.
  ##   optionalCheck |> markWarn
  if r.status == dsErr:
    DiagResult(name: r.name, status: dsWarn, detail: r.detail)
  else:
    r

func formatResult*(r: DiagResult): string =
  ## Formats a single check result as a human-readable tagged line.
  ##   check |> formatResult
  let marker = case r.status
    of dsOk:   "  [OK]  "
    of dsWarn: " [WARN] "
    of dsErr:  " [FAIL] "
  marker & r.name & ": " & r.detail

func countFailed*(results: seq[DiagResult]): int =
  ## Counts checks with dsErr status (warnings are not failures).
  ##   results |> countFailed
  for r in results:
    if r.status == dsErr: inc result

func allPassed*(results: seq[DiagResult]): bool =
  ## True when no check has dsErr status (warnings are allowed).
  ##   results |> allPassed
  (results |> countFailed) == 0

# ── last-arg transforms (|>-> friendly — seq is last arg) ─────────────────────

func formatReport*(title: string; results: seq[DiagResult]): string =
  ## Formats a full diagnostic report with title header and all check lines.
  ##   results |>-> formatReport("Donkey Doctor")
  result = title & "\n"
  result &= repeat('-', title.len) & "\n"
  for r in results:
    result &= (r |> formatResult) & "\n"
