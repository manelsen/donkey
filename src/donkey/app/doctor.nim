## doctor.nim — System diagnostics for `donkey doctor`.
##
## Effectful procs that run external dependency checks and report results.
## Pure types and formatting live in core/diagnostics; this module owns the I/O.
##
## Pipeline usage:
##
## .. code-block:: nim
##
##   runRuntimeCmd()     |>->  toDiagResult("container runtime")
##   runRuntimeCmd()     >>=   checkRuntimeCompose    -- chained binary checks
##   results             |>    countFailed             -- count hard failures
##   results             |>->  formatReport("Doctor")  -- full formatted report

import std/[os, strutils]
import ../core/pipeops
import ../core/diagnostics
import ../config/environment
import ../config/types
import ../domain/providers/descriptors
import ../domain/insights_pure
import ./credential_runtime
import ./turn_traces
import ./sandbox
import ../ports/fs
import ../ports/process

# ── raw Result-returning procs (for >>= chaining) ─────────────────────────────

proc runRuntimeCmd*(process: ProcessRuntimePort;
                    runtimeCmd = "docker"): Result[string, string] {.gcsafe, raises: [].} =
  ## Checks OCI runtime binary presence and returns version string or error.
  let ran = process.run(argvSpec(@[runtimeCmd, "--version"])).valueOr:
    return err(error)
  if ran.exitCode == 0: ok(ran.output.strip())
  else: err(runtimeCmd & " not found (exit " & $ran.exitCode & ")")

proc checkRuntimeCompose*(process: ProcessRuntimePort; runtimeCmd: string;
                          runtimeVersion: string): Result[string, string]
                          {.gcsafe, raises: [].} =
  ## Given an OCI runtime is available, checks for the compose subcommand.
  let ran = process.run(argvSpec(@[runtimeCmd, "compose", "version"])).valueOr:
    return err(runtimeCmd & " compose check failed")
  if ran.exitCode == 0: ok(runtimeVersion & " | compose: " & ran.output.strip())
  else: err(runtimeCmd & " compose plugin not available")

proc apiKeyResult(v: string; envVar: string): Result[string, string] =
  if v.len > 0: ok("set (" & $v.len & " chars)")
  else: err("not set — export " & envVar)

func endpointResult(v: string; envVar: string): Result[string, string] =
  ## `atNone` providers (ollama) are configured by an endpoint, not a key.
  if v.len > 0: ok("endpoint configured (" & envVar & ")")
  else: err("endpoint not set — export " & envVar)

func missingKeyResult(envNames: openArray[string]): Result[string, string] =
  err("not set — export " & envNames.join(" or "))

proc pgvectorResult(dsn: string): Result[string, string] =
  if dsn.len == 0:
    err(
      "DONKEY_PG_DSN not set — SQLite MAGMA is now the default; " &
      "PostgreSQL is optional and recommended for larger installs via `docker compose up -d postgres` " &
      "and export `DONKEY_PG_DSN='host=127.0.0.1 user=postgres password=donkey_pass dbname=donkey port=5432'`"
    )
  else:
    ok("DONKEY_PG_DSN set — pgvector available in the default build")

# ── public named checks ────────────────────────────────────────────────────────

proc checkContainerRuntime*(process: ProcessRuntimePort; runtimeCmd = "docker"): DiagResult =
  ## Checks OCI runtime binary + compose plugin via >>= chaining.
  (runRuntimeCmd(process, runtimeCmd) >>=
    proc(version: string): Result[string, string] {.gcsafe, raises: [].} =
      checkRuntimeCompose(process, runtimeCmd, version)
  ) |>-> toDiagResult("container runtime")

proc checkSandboxRuntime*(process: ProcessRuntimePort; fs: FsRuntimePort;
                          cfg: DonkeyConfig): DiagResult =
  sandboxAvailabilityResult(process, fs, cfg) |>-> toDiagResult("sandbox runtime")

proc checkApiKey*(env: Environment; name: string; envVar: string): DiagResult =
  ## Checks whether an API key environment variable is set.
  ##   ``checkApiKey(cfg.env, "OpenRouter", "OPENROUTER_API_KEY") |> markWarn``
  apiKeyResult(env.get(envVar), envVar) |>-> toDiagResult(name)

proc checkPgvector*(env: Environment): DiagResult =
  ## Checks for Postgres + pgvector extension (optional in F1 mode).
  ## Downgrades to dsWarn — pgvector is an F2+ dependency.
  (pgvectorResult(env.get("DONKEY_PG_DSN")) |>-> toDiagResult("pgvector")) |> markWarn

proc sandboxPolicyResult*(cfg: DonkeyConfig;
                          devMode: bool): Result[string, string] =
  validateSandboxPolicy(cfg, devMode).map(
    proc(_: void): string =
      var details: seq[string] = @["mode=" & $cfg.sandboxMode]
      if cfg.sandboxMode == smOci:
        details.add("runtime=" & cfg.sandboxRuntimeCmd)
        details.add("network=" & (if cfg.sandboxAllowNetwork: "on" else: "off"))
        details.add("rootfs=" & (if cfg.sandboxReadOnlyRootfs: "ro" else: "rw"))
      if cfg.sandboxAllowHostFallback:
        details.add("host-fallback=on")
      else:
        details.add("host-fallback=off")
      details.join(", ")
  )

proc storageSummary*(cfg: DonkeyConfig): string =
  let pgDsn = cfg.env.stripped("DONKEY_PG_DSN")
  if pgDsn.len > 0:
    return "PostgreSQL-backed MAGMA (DONKEY_PG_DSN set)"
  when defined(withSqlite):
    let sqlitePath = cfg.env.stripped("DONKEY_MAGMA_SQLITE_PATH")
    if sqlitePath.len > 0:
      return "SQLite-first MAGMA (" & sqlitePath & ")"
    return "SQLite-first MAGMA (" & cfg.home / "state" / "magma.sqlite" & ")"
  else:
    "Markdown-first runtime (build without withSqlite)"

proc defaultModelSummary*(cfg: DonkeyConfig): string =
  if cfg.defaultProvider.len > 0 and cfg.defaultModel.len > 0:
    cfg.defaultProvider & " / " & cfg.defaultModel
  elif cfg.defaultProvider.len > 0:
    cfg.defaultProvider
  elif cfg.defaultModel.len > 0:
    cfg.defaultModel
  else:
    "smart routing"

proc webSearchSummary*(env: Environment): string =
  if env.get("BRAVE_API_KEY").len > 0:
    "enabled via Brave Search"
  else:
    "disabled (set BRAVE_API_KEY to enable web_search)"

proc buildDoctorSummary*(cfg: DonkeyConfig;
                         devMode = false): string =
  let sandboxLine = sandboxPolicyResult(cfg, devMode).valueOr: error
  result = "Snapshot\n"
  result &= "--------\n"
  result &= "- storage: " & storageSummary(cfg) & "\n"
  result &= "- default model: " & defaultModelSummary(cfg) & "\n"
  result &= "- web search: " & webSearchSummary(cfg.env) & "\n"
  result &= "- sandbox: " & sandboxLine & "\n"

proc checkSandboxPolicy*(cfg: DonkeyConfig;
                         devMode: bool): DiagResult =
  result = sandboxPolicyResult(cfg, devMode) |>-> toDiagResult("sandbox policy")
  if result.status == dsOk and devMode and (cfg.sandboxAllowNetwork or not cfg.sandboxReadOnlyRootfs or cfg.sandboxAllowHostFallback):
    result.status = dsWarn
    result.detail &= " | relaxed isolation"

# ── orchestration ──────────────────────────────────────────────────────────────

type
  DoctorProviderRow* = tuple[id, label, envVar: string]

# Labels are operator-facing text (UI policy); identity and env come from
# providerDescriptors().
const ProviderKeyLabels = [
  ("openrouter",    "OpenRouter"),
  ("openai",        "OpenAI"),
  ("deepseek",      "DeepSeek"),
  ("ollama",        "Ollama"),
  ("groq",          "Groq"),
  ("opencode-go",   "OpenCode Go"),
  ("zen",           "OpenCode Zen"),
  ("anthropic",     "Anthropic"),
  ("zai-anthropic", "ZAI Anthropic"),
  ("gemini",        "Gemini"),
  ("minimax",       "MiniMax"),
  ("zai",           "Zhipu/ZAI"),
  ("zai-coding",    "ZAI Coding"),
  ("nvidia",        "NVIDIA NIM"),
  ("mistral",       "Mistral AI"),
  ("bedrock",       "AWS Bedrock"),
  ("alibaba",       "Alibaba DashScope"),
  ("fireworks",     "Fireworks AI"),
  ("azure",         "Azure OpenAI"),
]

func providerKeyLabel(id: string): string =
  for (candidate, label) in ProviderKeyLabels:
    if candidate == id:
      return label
  id

func doctorProviderRows*(): seq[DoctorProviderRow] =
  ## Provider key checks shown by `doctor`, one row per descriptor.
  for descriptor in providerDescriptors():
    result.add((
      id: descriptor.id,
      label: providerKeyLabel(descriptor.id),
      envVar: (if descriptor.envNames.len > 0: descriptor.envNames[0] else: ""),
    ))

proc checkProviderRow*(env: Environment; row: DoctorProviderRow): DiagResult =
  ## The real credential check: all descriptor env names and their plural
  ## `*_KEYS` form. `atNone` providers (ollama) are endpoint-configured, not
  ## API-key providers. The detail never contains the secret.
  let descriptor = descriptorOr(row.id)
  if descriptor.authType == atNone:
    let envName = if descriptor.envNames.len > 0: descriptor.envNames[0] else: ""
    let endpoint = if envName.len > 0: env.stripped(envName) else: ""
    endpointResult(endpoint, envName) |>-> toDiagResult(row.label)
  elif configuredIn(env, row.id):
    ## `configuredIn` is the single truth: every descriptor env name and the
    ## plural `*_KEYS` form. The value is measured, never echoed.
    apiKeyResult(firstCredential(env, descriptor.envNames), row.envVar) |>->
      toDiagResult(row.label)
  else:
    missingKeyResult(descriptor.envNames) |>-> toDiagResult(row.label)

# Non-provider credentials the operator may need.
const AuxKeyChecks = [
  ("Telegram",       "TELEGRAM_BOT_TOKEN"),
  ("Discord",        "DISCORD_BOT_TOKEN"),
  ("Brave Search",   "BRAVE_API_KEY"),
]

proc checkPromptCache*(fs: FsRuntimePort; paddocksDir: string;
                       sinceMs: int64): DiagResult =
  ## E8.4: a provider whose large prompts never read from the prompt cache,
  ## from the kept traces. Advisory: the provider may not cache at all.
  const name = "Prompt cache"
  let lines = traceLines(fs, paddocksDir, sinceMs)
  if lines.len == 0:
    return DiagResult(name: name, status: dsOk,
                      detail: "no traces to judge (DONKEY_TRACES=on keeps them)")
  let silent = aggregateInsights(lines).cacheSilent
  if silent.len == 0:
    return DiagResult(name: name, status: dsOk, detail: "every provider with large prompts read from it")
  var parts: seq[string]
  for (provider, n) in silent: parts.add provider & " (" & $n & " large prompts)"
  DiagResult(name: name, status: dsWarn,
    detail: "never hit: " & parts.join(", ") & "; the provider may not cache, " &
            "or the prompt's beginning changes between requests")

proc runDoctorChecks*(process: ProcessRuntimePort; fs: FsRuntimePort;
                      cfg: DonkeyConfig; devMode = false): seq[DiagResult] =
  ## Runs all dependency checks and returns the result list.
  ## Required checks (dsErr on failure): sandbox policy, selected sandbox runtime
  ## Advisory checks (dsWarn on failure): pgvector, API keys, relaxed sandbox knobs in dev mode
  result.add checkSandboxPolicy(cfg, devMode)
  result.add checkSandboxRuntime(process, fs, cfg)
  if cfg.sandboxMode == smOci:
    result.add checkContainerRuntime(process, cfg.sandboxRuntimeCmd)
  result.add checkPgvector(cfg.env)
  for (name, envVar) in AuxKeyChecks:
    result.add checkApiKey(cfg.env, name, envVar) |> markWarn
  ## One credential probe per primary env: opencode-go and zen share
  ## OPENCODE_API_KEY, so the second row reuses the first result instead of
  ## asking the environment twice. Provider identity rows are kept.
  var probed: seq[(string, DiagResult)]
  for row in doctorProviderRows():
    let descriptor = descriptorOr(row.id)
    let primary = if descriptor.envNames.len > 0: descriptor.envNames[0] else: row.id
    var reused = -1
    for i, item in probed:
      if item[0] == primary:
        reused = i
        break
    var check: DiagResult
    if reused >= 0:
      check = probed[reused][1]
      check.name = row.label
    else:
      check = checkProviderRow(cfg.env, row)
      probed.add((primary, check))
    result.add check |> markWarn
  if cfg.paddocks.len > 0:
    result.add checkPromptCache(fs, cfg.paddocks, epochMs() - 7 * 86_400_000'i64)

proc printDoctorReport*(results: seq[DiagResult]) =
  ## Prints a formatted report to stdout.
  echo results |>-> formatReport("Donkey Doctor")
  let failed = results |> countFailed
  if failed > 0:
    echo $failed & " required check(s) failed."
  else:
    echo "All required checks passed."

proc runDoctor*(process: ProcessRuntimePort; fs: FsRuntimePort;
                cfg: DonkeyConfig; devMode = false): int =
  ## Runs all checks, prints the report, returns 0 if all passed else 1.
  echo buildDoctorSummary(cfg, devMode)
  echo ""
  let results = runDoctorChecks(process, fs, cfg, devMode)
  printDoctorReport(results)
  if results |> allPassed: 0 else: 1
