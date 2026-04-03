## t_doctor.nim — unit tests for app/doctor.nim
##
## Tests the effectful doctor checks in isolation.
## Checks that depend on external binaries use status-only assertions
## (pass or fail gracefully regardless of environment).

import std/[os, strutils, unittest]
import donkey/app/doctor
import donkey/core/diagnostics
import donkey/core/pipeops

# ── checkApiKey ────────────────────────────────────────────────────────────────

suite "doctor — checkApiKey":

  test "returns dsErr when env var is not set":
    putEnv("_DONKEY_TEST_KEY_ABSENT", "")
    let r = checkApiKey("TestProvider", "_DONKEY_TEST_KEY_ABSENT")
    check r.name == "TestProvider"
    # env var is empty → dsErr (caller decides to markWarn)
    check r.status == dsErr
    check "not set" in r.detail

  test "returns dsOk when env var is set":
    putEnv("_DONKEY_TEST_KEY_PRESENT", "sk-test-12345")
    let r = checkApiKey("TestProvider", "_DONKEY_TEST_KEY_PRESENT")
    check r.status == dsOk
    check "set" in r.detail

  test "detail includes char count when key is set":
    putEnv("_DONKEY_TEST_KEY_LEN", "abc123")
    let r = checkApiKey("Len", "_DONKEY_TEST_KEY_LEN")
    check r.status == dsOk
    check "6" in r.detail    # len("abc123") == 6

  test "markWarn downgrades missing key to dsWarn":
    putEnv("_DONKEY_TEST_KEY_WARN", "")
    let r = checkApiKey("Optional", "_DONKEY_TEST_KEY_WARN") |> markWarn
    check r.status == dsWarn

# ── checkPgvector ──────────────────────────────────────────────────────────────

suite "doctor — checkPgvector":

  test "returns dsWarn when DONKEY_PG_DSN is not set":
    let saved = getEnv("DONKEY_PG_DSN")
    putEnv("DONKEY_PG_DSN", "")
    let r = checkPgvector()
    check r.name   == "pgvector"
    check r.status == dsWarn    # always advisory
    check "docker compose up -d postgres" in r.detail
    if saved.len > 0: putEnv("DONKEY_PG_DSN", saved)

  test "returns dsOk when DONKEY_PG_DSN is set (DSN is configured)":
    putEnv("DONKEY_PG_DSN", "postgres://localhost/test")
    let r = checkPgvector()
    check r.status == dsOk      # DSN is set — configuration looks ok
    putEnv("DONKEY_PG_DSN", "")

# ── checkDocker ────────────────────────────────────────────────────────────────

suite "doctor — checkDocker":

  test "check returns a DiagResult with name 'docker'":
    let r = checkDocker()
    check r.name == "docker"

  test "check result is either dsOk or dsErr (no crash)":
    let r = checkDocker()
    check r.status in {dsOk, dsErr}

# ── runDoctorChecks ────────────────────────────────────────────────────────────

suite "doctor — runDoctorChecks":

  test "returns at least docker + pgvector + API key checks":
    let results = runDoctorChecks()
    check results.len >= 2    # at least docker + pgvector

  test "result contains docker check":
    let results = runDoctorChecks()
    var found = false
    for r in results:
      if r.name == "docker": found = true
    check found

  test "result contains pgvector check":
    let results = runDoctorChecks()
    var found = false
    for r in results:
      if r.name == "pgvector": found = true
    check found

  test "result contains at least one API key check":
    let results = runDoctorChecks()
    var found = false
    for r in results:
      if r.name in ["Telegram", "OpenRouter", "Zhipu/ZAI", "Anthropic"]:
        found = true
    check found

  test "allPassed pipeline works on doctor results":
    let results = runDoctorChecks()
    # Just verify the pipeline doesn't crash; result depends on environment.
    let _ = results |> allPassed

  test "countFailed pipeline works on doctor results":
    let results = runDoctorChecks()
    let failed = results |> countFailed
    check failed >= 0

  test "formatReport pipeline produces non-empty output":
    let results = runDoctorChecks()
    let report  = results |>-> formatReport("Donkey Doctor")
    check "Donkey Doctor" in report
    check report.len > 0

# ── >>= chaining with runDockerCmd ────────────────────────────────────────────

suite "doctor — >>= chaining":

  test "checkDockerCompose is chainable via >>=":
    # runDockerCmd either succeeds or fails; either way >>= handles it cleanly.
    let r = runDockerCmd() >>= checkDockerCompose
    # Result is Ok or Err — no crash either way.
    check r.isOk or r.isErr

  test "failed docker short-circuits compose check":
    let r = Result[string, string].err("no docker") >>= checkDockerCompose
    check r.isErr
    check "no docker" in r.error
