## doctor.nim — System diagnostics for `donkey doctor`.
##
## Effectful procs that run external dependency checks and report results.
## Pure types and formatting live in core/diagnostics; this module owns the I/O.
##
## Pipeline usage:
##   runRuntimeCmd()     |>->  toDiagResult("container runtime")
##   runRuntimeCmd()     >>=   checkRuntimeCompose    -- chained binary checks
##   results             |>    countFailed             -- count hard failures
##   results             |>->  formatReport("Doctor")  -- full formatted report

import std/[os, osproc, strutils]
import ../core/pipeops
import ../core/diagnostics

# ── raw Result-returning procs (for >>= chaining) ─────────────────────────────

proc runRuntimeCmd*(runtimeCmd = "docker"): Result[string, string] =
  ## Checks OCI runtime binary presence and returns version string or error.
  try:
    let (output, code) = execCmdEx(runtimeCmd.quoteShell & " --version")
    if code == 0: ok(output.strip())
    else: err(runtimeCmd & " not found (exit " & $code & ")")
  except CatchableError as e:
    err(e.msg)

proc checkRuntimeCompose*(runtimeCmd: string;
                          runtimeVersion: string): Result[string, string]
                          {.gcsafe, raises: [].} =
  ## Given an OCI runtime is available, checks for the compose subcommand.
  try:
    let (output, code) = execCmdEx(runtimeCmd.quoteShell & " compose version")
    if code == 0: ok(runtimeVersion & " | compose: " & output.strip())
    else: err(runtimeCmd & " compose plugin not available")
  except:
    err(runtimeCmd & " compose check failed")

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

proc checkContainerRuntime*(runtimeCmd = "docker"): DiagResult =
  ## Checks OCI runtime binary + compose plugin via >>= chaining.
  (runRuntimeCmd(runtimeCmd) >>=
    proc(version: string): Result[string, string] {.gcsafe, raises: [].} =
      checkRuntimeCompose(runtimeCmd, version)
  ) |>-> toDiagResult("container runtime")

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

proc runDoctorChecks*(runtimeCmd = "docker"): seq[DiagResult] =
  ## Runs all dependency checks and returns the result list.
  ## Required checks (dsErr on failure): container runtime
  ## Advisory checks (dsWarn on failure): pgvector, API keys
  result.add checkContainerRuntime(runtimeCmd)
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

proc runDoctor*(runtimeCmd = "docker"): int =
  ## Runs all checks, prints the report, returns 0 if all passed else 1.
  let results = runDoctorChecks(runtimeCmd)
  printDoctorReport(results)
  if results |> allPassed: 0 else: 1
