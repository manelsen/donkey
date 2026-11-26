## t_doctor.nim — unit tests for app/doctor.nim
##
## Tests the effectful doctor checks in isolation.
## Checks that depend on external binaries use status-only assertions
## (pass or fail gracefully regardless of environment).

import std/[os, sequtils, strutils, unittest]
import donkey/app/doctor
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/process/process_adapter

let testProcess = newProcessAdapter()
let testFs = newFsAdapter()
import donkey/core/diagnostics
import donkey/core/pipeops
import donkey/config/types
import donkey/config/environment

# ── checkApiKey ────────────────────────────────────────────────────────────────

let noEnv = Environment()


proc runTests*() =
  suite "doctor — checkApiKey":

    test "returns dsErr when env var is not set":
      let r = checkApiKey(noEnv, "TestProvider", "_DONKEY_TEST_KEY_ABSENT")
      check r.name == "TestProvider"
      # env var is empty → dsErr (caller decides to markWarn)
      check r.status == dsErr
      check "not set" in r.detail

    test "returns dsOk when env var is set":
      let env = environmentOf({"_DONKEY_TEST_KEY_PRESENT": "sk-test-12345"})
      let r = checkApiKey(env, "TestProvider", "_DONKEY_TEST_KEY_PRESENT")
      check r.status == dsOk
      check "set" in r.detail

    test "detail includes char count when key is set":
      let env = environmentOf({"_DONKEY_TEST_KEY_LEN": "abc123"})
      let r = checkApiKey(env, "Len", "_DONKEY_TEST_KEY_LEN")
      check r.status == dsOk
      check "6" in r.detail    # len("abc123") == 6

    test "markWarn downgrades missing key to dsWarn":
      let r = checkApiKey(noEnv, "Optional", "_DONKEY_TEST_KEY_WARN") |> markWarn
      check r.status == dsWarn

  # ── checkPgvector ──────────────────────────────────────────────────────────────

  suite "doctor — checkPgvector":

    test "returns dsWarn when DONKEY_PG_DSN is not set":
      let r = checkPgvector(noEnv)
      check r.name   == "pgvector"
      check r.status == dsWarn    # always advisory
      check "docker compose up -d postgres" in r.detail

    test "returns dsOk when DONKEY_PG_DSN is set (DSN is configured)":
      let r = checkPgvector(environmentOf({"DONKEY_PG_DSN": "postgres://localhost/test"}))
      check r.status == dsOk      # DSN is set — configuration looks ok

  # ── checkContainerRuntime ─────────────────────────────────────────────────────

  suite "doctor — checkContainerRuntime":

    test "check returns a DiagResult with runtime label":
      let r = checkContainerRuntime(testProcess)
      check r.name == "container runtime"

    test "check result is either dsOk or dsErr (no crash)":
      let r = checkContainerRuntime(testProcess)
      check r.status in {dsOk, dsErr}

    test "a runtime with compose is ok, decided by the process port alone":
      var calls: seq[seq[string]]
      let fake = ProcessRuntimePort(run: proc(spec: ProcessSpec):
          Result[ProcessOutput, string] {.gcsafe, raises: [].} =
        calls.add spec.argv
        ok(ProcessOutput(output: "v1", exitCode: 0)))
      let r = checkContainerRuntime(fake, "podman")
      check r.status == dsOk
      check calls == @[@["podman", "--version"], @["podman", "compose", "version"]]

    test "a runtime that cannot be started is an error":
      check checkContainerRuntime(unavailableProcess()).status == dsErr

  suite "doctor — checkSandboxRuntime":

    test "oci sandbox runtime check returns a DiagResult":
      let cfg = DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker")
      let r = checkSandboxRuntime(testProcess, testFs, cfg)
      check r.name == "sandbox runtime"
      check r.status in {dsOk, dsErr}

    test "none sandbox runtime is trivially ok":
      let cfg = DonkeyConfig(sandboxMode: smNone)
      let r = checkSandboxRuntime(testProcess, testFs, cfg)
      check r.status == dsOk

    test "invalid sandbox runtime reports config error":
      let cfg = DonkeyConfig(sandboxMode: smNone, invalidSandboxMode: "wasmer")
      let r = checkSandboxRuntime(testProcess, testFs, cfg)
      check r.status == dsErr
      check "invalid" in r.detail
      check "wasmer" in r.detail

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
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      check results.len >= 4    # sandbox policy + sandbox runtime + runtime + pgvector

    test "result contains runtime check":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      var found = false
      for r in results:
        if r.name == "container runtime": found = true
      check found

    test "result contains sandbox runtime check":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      var found = false
      for r in results:
        if r.name == "sandbox runtime": found = true
      check found

    test "result contains pgvector check":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      var found = false
      for r in results:
        if r.name == "pgvector": found = true
      check found

    test "result contains sandbox policy check":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      var found = false
      for r in results:
        if r.name == "sandbox policy": found = true
      check found

    test "result contains at least one API key check":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      var found = false
      for r in results:
        if r.name in ["Telegram", "Discord", "ZAI Coding", "ZAI Anthropic", "OpenRouter", "Zhipu/ZAI", "Anthropic"]:
          found = true
      check found

    test "result contains discord and zai compatibility checks":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
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
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      # Just verify the pipeline doesn't crash; result depends on environment.
      let _ = results |> allPassed

    test "countFailed pipeline works on doctor results":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      let failed = results |> countFailed
      check failed >= 0

    test "formatReport pipeline produces non-empty output":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smOci, sandboxRuntimeCmd: "docker"))
      let report  = results |>-> formatReport("Donkey Doctor")
      check "Donkey Doctor" in report
      check report.len > 0

  suite "doctor — summary":

    test "doctor summary reflects sqlite-first defaults and smart routing":
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
      let cfg = DonkeyConfig(
        env: environmentOf({"DONKEY_PG_DSN": "postgres://localhost/test",
                            "BRAVE_API_KEY": "brave-key"}),
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

  # ── provider credentials ──────────────────────────────────────────────────────

  suite "doctor — provider credentials":

    test "accepts any descriptor env name, not only the first":
      let env = environmentOf({"ZHIPU_API_KEY": "zk-fallback"})
      let row = doctorProviderRows().filterIt(it.id == "zai-coding")[0]
      let r = checkProviderRow(env, row)
      check r.name == "ZAI Coding"
      check r.status == dsOk
      check "set (" in r.detail

    test "accepts the plural *_KEYS form":
      let env = environmentOf({"OPENAI_API_KEYS": "sk-a,sk-b"})
      let row = doctorProviderRows().filterIt(it.id == "openai")[0]
      check checkProviderRow(env, row).status == dsOk

    test "an endpoint provider is configured by its endpoint, not a key":
      let row = doctorProviderRows().filterIt(it.id == "ollama")[0]
      let missing = checkProviderRow(noEnv, row)
      check missing.status == dsErr
      check "OLLAMA_BASE_URL" in missing.detail
      let configured = checkProviderRow(
        environmentOf({"OLLAMA_BASE_URL": "http://localhost:11434"}), row)
      check configured.status == dsOk
      check "endpoint" in configured.detail

    test "the formatted report never prints the secret, only its length":
      const secret = "sk-doctor-super-secret-value"
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(
        sandboxMode: smNone, env: environmentOf({"OPENROUTER_API_KEY": secret})))
      let report = results |>-> formatReport("Donkey Doctor")
      check secret notin report
      check "set (" & $secret.len & " chars)" in report

  # ── >>= chaining with runRuntimeCmd ───────────────────────────────────────────

  suite "doctor — >>= chaining":

    test "checkRuntimeCompose is chainable via >>=":
      # runRuntimeCmd either succeeds or fails; either way >>= handles it cleanly.
      let process = testProcess
      let r = runRuntimeCmd(process) >>= proc(version: string): Result[string, string] =
        checkRuntimeCompose(process, "docker", version)
      # Result is Ok or Err — no crash either way.
      check r.isOk or r.isErr

    test "failed runtime short-circuits compose check":
      let process = testProcess
      let r = Result[string, string].err("no runtime") >>= proc(version: string): Result[string, string] =
        checkRuntimeCompose(process, "docker", version)
      check r.isErr
      check "no runtime" in r.error

proc runPromptCacheTests*() =
  suite "doctor — prompt cache (E8.4)":
    proc tracesWith(provider: string; cacheRead: int): string =
      let home = getTempDir() / "donkey_doctor_cache_" & provider
      removeDir(home)
      createDir(home / "state" / "traces")
      var body = ""
      for i in 0 ..< 6:
        body.add """{"ts":""" & $(2_000_000_000_000'i64 + i) & ""","user":"u","provider":"""" &
          provider & """","tokens":{"input":5000,"output":5,"cache_read":""" & $cacheRead &
          ""","cache_write":0},"outcome":"ok"}""" & "\n"
      writeFile(home / "state" / "traces" / "2033-05-18.jsonl", body)
      home / "paddocks"

    test "a provider whose large prompts never hit the cache is a warning":
      let r = checkPromptCache(newFsAdapter(), tracesWith("anthropic", 0), sinceMs = 0)
      check r.status == dsWarn and "anthropic" in r.detail

    test "a provider that reads from the cache passes":
      check checkPromptCache(newFsAdapter(), tracesWith("openrouter", 3000), sinceMs = 0).status == dsOk

    test "no traces passes, saying why it cannot tell":
      let r = checkPromptCache(newFsAdapter(), getTempDir() / "donkey_doctor_none" / "paddocks", 0)
      check r.status == dsOk and "DONKEY_TRACES" in r.detail

when isMainModule:
  runTests()
  runPromptCacheTests()
