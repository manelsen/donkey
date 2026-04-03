## doctor.nim — System diagnostics for `donkey doctor`.
##
## Effectful procs that run external dependency checks and report results.
## Pure types and formatting live in core/diagnostics; this module owns the I/O.
##
## Pipeline usage:
##   runDockerCmd()      |>->  toDiagResult("docker")
##   runDockerCmd()      >>=   checkDockerCompose     -- chained binary checks
##   results             |>    countFailed             -- count hard failures
##   results             |>->  formatReport("Doctor")  -- full formatted report

import std/[os, osproc, strutils]
import ../core/pipeops
import ../core/diagnostics

# ── raw Result-returning procs (for >>= chaining) ─────────────────────────────

proc runDockerCmd*(): Result[string, string] =
  ## Checks Docker binary presence and returns version string or error.
  try:
    let (output, code) = execCmdEx("docker --version")
    if code == 0: ok(output.strip())
    else: err("docker not found (exit " & $code & ")")
  except CatchableError as e:
    err(e.msg)

proc checkDockerCompose*(dockerVersion: string): Result[string, string]
                         {.gcsafe, raises: [].} =
  ## Given docker is available, checks for the compose plugin.
  ## Designed for >>= chaining after runDockerCmd().
  ##   runDockerCmd() >>= checkDockerCompose
  try:
    let (output, code) = execCmdEx("docker compose version")
    if code == 0: ok(dockerVersion & " | compose: " & output.strip())
    else: err("docker compose plugin not available")
  except:
    err("docker compose check failed")

proc apiKeyResult(v: string; envVar: string): Result[string, string] =
  if v.len > 0: ok("set (" & $v.len & " chars)")
  else: err("not set — export " & envVar)

proc pgvectorResult(dsn: string): Result[string, string] =
  if dsn.len == 0:
    err(
      "DONKEY_PG_DSN not set — recommended: `docker compose up -d postgres` " &
      "and export `DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'`"
    )
  else:
    ok("DONKEY_PG_DSN set — pgvector available in the default build")

# ── public named checks ────────────────────────────────────────────────────────

proc checkDocker*(): DiagResult =
  ## Checks Docker binary + compose plugin via >>= chaining.
  ##   runDockerCmd() >>= checkDockerCompose  |>->  toDiagResult("docker")
  (runDockerCmd() >>= checkDockerCompose) |>-> toDiagResult("docker")

proc checkApiKey*(name: string; envVar: string): DiagResult =
  ## Checks whether an API key environment variable is set.
  ##   checkApiKey("OpenRouter", "OPENROUTER_API_KEY") |> markWarn
  apiKeyResult(getEnv(envVar), envVar) |>-> toDiagResult(name)

proc checkPgvector*(): DiagResult =
  ## Checks for Postgres + pgvector extension (optional in F1 mode).
  ## Downgrades to dsWarn — pgvector is an F2+ dependency.
  (pgvectorResult(getEnv("DONKEY_PG_DSN")) |>-> toDiagResult("pgvector")) |> markWarn

# ── orchestration ──────────────────────────────────────────────────────────────

const ApiKeyChecks = [
  ("Telegram",   "TELEGRAM_BOT_TOKEN"),
  ("OpenRouter", "OPENROUTER_API_KEY"),
  ("Zhipu/ZAI",  "ZAI_API_KEY"),
  ("Anthropic",  "ANTHROPIC_API_KEY"),
  ("Gemini",     "GEMINI_API_KEY"),
  ("MiniMax",    "MINIMAX_API_KEY"),
]

proc runDoctorChecks*(): seq[DiagResult] =
  ## Runs all dependency checks and returns the result list.
  ## Required checks (dsErr on failure): docker
  ## Advisory checks (dsWarn on failure): pgvector, API keys
  result.add checkDocker()
  result.add checkPgvector()
  for (name, envVar) in ApiKeyChecks:
    result.add checkApiKey(name, envVar) |> markWarn

proc printDoctorReport*(results: seq[DiagResult]) =
  ## Prints a formatted report to stdout.
  echo results |>-> formatReport("Donkey Doctor")
  let failed = results |> countFailed
  if failed > 0:
    echo $failed & " required check(s) failed."
  else:
    echo "All required checks passed."

proc runDoctor*(): int =
  ## Runs all checks, prints the report, returns 0 if all passed else 1.
  let results = runDoctorChecks()
  printDoctorReport(results)
  if results |> allPassed: 0 else: 1
