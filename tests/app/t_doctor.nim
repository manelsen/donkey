## t_doctor.nim — unit tests for app/doctor.nim
##
## Tests the effectful doctor checks in isolation.
## Checks that depend on external binaries use status-only assertions
## (pass or fail gracefully regardless of environment).

import std/[os, strutils, unittest]
import donkey/app/doctor
import donkey/core/diagnostics
import donkey/core/pipeops
import donkey/config/types

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

# ── checkContainerRuntime ─────────────────────────────────────────────────────

suite "doctor — checkContainerRuntime":

  test "check returns a DiagResult with runtime label":
    let r = checkContainerRuntime()
    check r.name == "container runtime"

  test "check result is either dsOk or dsErr (no crash)":
    let r = checkContainerRuntime()
    check r.status in {dsOk, dsErr}

suite "doctor — checkSandboxRuntime":

  test "oci sandbox runtime check returns a DiagResult":
    let cfg = DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker")
    let r = checkSandboxRuntime(cfg)
    check r.name == "sandbox runtime"
    check r.status in {dsOk, dsErr}

  test "none sandbox runtime is trivially ok":
    let cfg = DonkeyConfig(sandboxMode: smNone)
    let r = checkSandboxRuntime(cfg)
    check r.status == dsOk

suite "doctor — checkSandboxPolicy":

  test "sandbox policy is err for none in production":
    let cfg = DonkeyConfig(sandboxMode: smNone)
    let r = checkSandboxPolicy(cfg, devMode = false)
    check r.name == "sandbox policy"
    check r.status == dsErr

  test "sandbox policy is err when oci network is enabled in production":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxRuntimeCmd: "docker",
      sandboxAllowNetwork: true,
      sandboxReadOnlyRootfs: true
    )
    let r = checkSandboxPolicy(cfg, devMode = false)
    check r.status == dsErr

  test "sandbox policy warns when oci network is enabled in dev mode":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxRuntimeCmd: "docker",
      sandboxAllowNetwork: true,
      sandboxReadOnlyRootfs: true
    )
    let r = checkSandboxPolicy(cfg, devMode = true)
    check r.status == dsWarn

  test "sandbox policy is ok for hardened oci config":
    let cfg = DonkeyConfig(
      sandboxMode: smOci,
      sandboxRuntimeCmd: "docker",
      sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: true
    )
    let r = checkSandboxPolicy(cfg, devMode = false)
    check r.status == dsOk

# ── runDoctorChecks ────────────────────────────────────────────────────────────

suite "doctor — runDoctorChecks":

  test "returns at least runtime + pgvector + API key checks":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    check results.len >= 4    # sandbox policy + sandbox runtime + runtime + pgvector

  test "result contains runtime check":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var found = false
    for r in results:
      if r.name == "container runtime": found = true
    check found

  test "result contains sandbox runtime check":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var found = false
    for r in results:
      if r.name == "sandbox runtime": found = true
    check found

  test "result contains pgvector check":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var found = false
    for r in results:
      if r.name == "pgvector": found = true
    check found

  test "result contains sandbox policy check":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var found = false
    for r in results:
      if r.name == "sandbox policy": found = true
    check found

  test "result contains at least one API key check":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var found = false
    for r in results:
      if r.name in ["Telegram", "Discord", "ZAI Coding", "ZAI Anthropic", "OpenRouter", "Zhipu/ZAI", "Anthropic"]:
        found = true
    check found

  test "result contains discord and zai compatibility checks":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    var foundDiscord = false
    var foundZaiCoding = false
    var foundZaiAnthropic = false
    for r in results:
      if r.name == "Discord": foundDiscord = true
      if r.name == "ZAI Coding": foundZaiCoding = true
      if r.name == "ZAI Anthropic": foundZaiAnthropic = true
    check foundDiscord
    check foundZaiCoding
    check foundZaiAnthropic

  test "allPassed pipeline works on doctor results":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    # Just verify the pipeline doesn't crash; result depends on environment.
    let _ = results |> allPassed

  test "countFailed pipeline works on doctor results":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    let failed = results |> countFailed
    check failed >= 0

  test "formatReport pipeline produces non-empty output":
    let results = runDoctorChecks(DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
    let report  = results |>-> formatReport("Donkey Doctor")
    check "Donkey Doctor" in report
    check report.len > 0

suite "doctor — summary":

  test "doctor summary reflects sqlite-first defaults and smart routing":
    putEnv("DONKEY_PG_DSN", "")
    putEnv("DONKEY_MAGMA_SQLITE_PATH", "")
    putEnv("BRAVE_API_KEY", "")
    let cfg = DonkeyConfig(
      home: "/tmp/donkey-home",
      sandboxMode: smOci,
      sandboxRuntimeCmd: "docker",
      sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: true,
      sandboxAllowHostFallback: false,
    )
    let summary = buildDoctorSummary(cfg)
    check "Snapshot" in summary
    check "SQLite-first MAGMA" in summary
    check "smart routing" in summary
    check "disabled (set BRAVE_API_KEY" in summary
    check "mode=oci" in summary

  test "doctor summary reflects configured defaults and pg runtime":
    putEnv("DONKEY_PG_DSN", "postgres://localhost/test")
    putEnv("BRAVE_API_KEY", "brave-key")
    let cfg = DonkeyConfig(
      home: "/tmp/donkey-home",
      defaultProvider: "zai-coding",
      defaultModel: "glm-4.7",
      sandboxMode: smOci,
      sandboxRuntimeCmd: "docker",
      sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: true,
      sandboxAllowHostFallback: false,
    )
    let summary = buildDoctorSummary(cfg)
    check "PostgreSQL-backed MAGMA" in summary
    check "zai-coding / glm-4.7" in summary
    check "enabled via Brave Search" in summary

# ── >>= chaining with runRuntimeCmd ───────────────────────────────────────────

suite "doctor — >>= chaining":

  test "checkRuntimeCompose is chainable via >>=":
    # runRuntimeCmd either succeeds or fails; either way >>= handles it cleanly.
    let r = runRuntimeCmd() >>= proc(version: string): Result[string, string] =
      checkRuntimeCompose("docker", version)
    # Result is Ok or Err — no crash either way.
    check r.isOk or r.isErr

  test "failed runtime short-circuits compose check":
    let r = Result[string, string].err("no runtime") >>= proc(version: string): Result[string, string] =
      checkRuntimeCompose("docker", version)
    check r.isErr
    check "no runtime" in r.error
