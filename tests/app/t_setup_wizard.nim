## Tests for app/setup_wizard — pure setup generation functions.
##
## The interactive wizard is a proc driven by stdin/stdout and is not unit-tested
## here.  These tests cover the pure functions that build config/env content.

import std/[os, strutils, unittest]
import donkey/app/setup_wizard
import donkey/app/doctor
import donkey/config/loader

suite "buildTomlContent":

  test "contains home dir":
    let toml = buildTomlContent(home = "/tmp/donkey_test")
    check toml.contains("/tmp/donkey_test")
    check toml.contains("/tmp/donkey_test/paddocks")
    check toml.contains("/tmp/donkey_test/donkey.log")

  test "contains log_level key":
    let toml = buildTomlContent(home = "/tmp/x")
    check toml.contains("log_level")

  test "default log_level is info":
    let toml = buildTomlContent(home = "/tmp/x")
    check toml.contains("log_level = \"info\"")

  test "default runtime is docker":
    let toml = buildTomlContent(home = "/tmp/x")
    check toml.contains("runtime = \"docker\"")

  test "runtime can be overridden":
    let toml = buildTomlContent(home = "/tmp/x", runtime = "podman")
    check toml.contains("runtime = \"podman\"")

  test "default provider and model are rendered when provided":
    let toml = buildTomlContent(home = "/tmp/x", defaultProvider = "zai-coding",
                                defaultModel = "glm-4.7")
    check toml.contains("default_provider = \"zai-coding\"")
    check toml.contains("default_model = \"glm-4.7\"")

suite "buildEnvContent":

  test "telegram token appears when provided":
    let env = buildEnvContent(
      providers = @[("zai-coding", "key123")],
      channels = @[("telegram", "tg_token_abc")],
    )
    check "TELEGRAM_BOT_TOKEN=tg_token_abc" in env

  test "includes docker postgres recommendation":
    let env = buildEnvContent(@[], @[])
    check "docker compose up -d postgres" in env
    check "DONKEY_PG_DSN=host=127.0.0.1" in env
    check "DONKEY_SQLITE_VEC_PATH=/absolute/path/to/vec0" in env
    check "BRAVE_API_KEY=" in env

  test "generated toml uses oci mode with docker runtime":
    let toml = buildTomlContent(home = "/tmp/x")
    check "mode    = \"oci\"" in toml
    check "runtime = \"docker\"" in toml

  test "discord token appears when provided":
    let env = buildEnvContent(
      providers = @[("openrouter", "or_key")],
      channels = @[("discord", "dc_token_xyz")],
    )
    check "DISCORD_BOT_TOKEN=dc_token_xyz" in env

  test "provider key maps to correct env var for zai-coding":
    let env = buildEnvContent(@[("zai-coding", "mykey")], @[])
    check "ZAI_CODING_API_KEY=mykey" in env

  test "provider key maps to correct env var for zai-anthropic":
    let env = buildEnvContent(@[("zai-anthropic", "za-key")], @[])
    check "ZAI_ANTHROPIC_API_KEY=za-key" in env

  test "provider key maps to correct env var for openrouter":
    let env = buildEnvContent(@[("openrouter", "or123")], @[])
    check "OPENROUTER_API_KEY=or123" in env

  test "provider key maps to correct env var for anthropic":
    let env = buildEnvContent(@[("anthropic", "sk-ant")], @[])
    check "ANTHROPIC_API_KEY=sk-ant" in env

  test "provider key maps to correct env var for gemini":
    let env = buildEnvContent(@[("gemini", "gm-key")], @[])
    check "GEMINI_API_KEY=gm-key" in env

  test "multiple providers appear":
    let env = buildEnvContent(
      @[("zai-coding", "zk"), ("openrouter", "ok"), ("anthropic", "ak")],
      @[]
    )
    check "ZAI_CODING_API_KEY=zk" in env
    check "OPENROUTER_API_KEY=ok" in env
    check "ANTHROPIC_API_KEY=ak" in env

  test "omitted channel token left blank":
    let env = buildEnvContent(@[("zai-coding", "k")], @[("telegram", "tok")])
    check "DISCORD_BOT_TOKEN=" in env

  test "multiple channels both appear":
    let env = buildEnvContent(
      @[("zai-coding", "k")],
      @[("telegram", "tg"), ("discord", "dc")]
    )
    check "TELEGRAM_BOT_TOKEN=tg" in env
    check "DISCORD_BOT_TOKEN=dc" in env

  test "brave web search key appears when provided":
    let env = buildEnvContent(@[], @[], "brave-key")
    check "BRAVE_API_KEY=brave-key" in env

suite "providerEnvVar":

  test "zai-coding":   check providerEnvVar("zai-coding")   == "ZAI_CODING_API_KEY"
  test "zai":          check providerEnvVar("zai")          == "ZAI_API_KEY"
  test "zai-anthropic": check providerEnvVar("zai-anthropic") == "ZAI_ANTHROPIC_API_KEY"
  test "openrouter":   check providerEnvVar("openrouter")   == "OPENROUTER_API_KEY"
  test "anthropic":    check providerEnvVar("anthropic")    == "ANTHROPIC_API_KEY"
  test "gemini":       check providerEnvVar("gemini")       == "GEMINI_API_KEY"
  test "minimax":      check providerEnvVar("minimax")      == "MINIMAX_API_KEY"
  test "deepseek":     check providerEnvVar("deepseek")     == "DEEPSEEK_API_KEY"
  test "openai":       check providerEnvVar("openai")       == "OPENAI_API_KEY"
  test "unknown":      check providerEnvVar("unknown")      == ""

suite "setupAlreadyDone":

  test "returns false when toml missing":
    let tmpHome = getTempDir() / "donkey_cfg_missing_xyz"
    if dirExists(tmpHome): removeDir(tmpHome)
    createDir(tmpHome)
    putEnv("XDG_CONFIG_HOME", tmpHome)
    defer:
      delEnv("XDG_CONFIG_HOME")
      if dirExists(tmpHome): removeDir(tmpHome)
    check not setupAlreadyDone()

  test "returns true when toml exists":
    let tmpHome = getTempDir() / "donkey_test_setup_done_cfg"
    if dirExists(tmpHome): removeDir(tmpHome)
    createDir(tmpHome / "donkey")
    putEnv("XDG_CONFIG_HOME", tmpHome)
    defer:
      delEnv("XDG_CONFIG_HOME")
      if dirExists(tmpHome): removeDir(tmpHome)
    writeFile(tmpHome / "donkey" / "donkey.toml", "home = \"/tmp/x\"\n")
    check setupAlreadyDone()

suite "setup paths and snapshot":

  test "config and env paths resolve inside XDG config home":
    let tmpHome = getTempDir() / "donkey_cfg_paths_xyz"
    if dirExists(tmpHome): removeDir(tmpHome)
    createDir(tmpHome)
    putEnv("XDG_CONFIG_HOME", tmpHome)
    defer:
      delEnv("XDG_CONFIG_HOME")
      if dirExists(tmpHome): removeDir(tmpHome)
    check configFilePath() == tmpHome / "donkey" / "donkey.toml"
    check envFilePath() == tmpHome / "donkey" / "donkey.env"

  test "generated config produces coherent runtime snapshot":
    let testDir = getTempDir() / "donkey_setup_snapshot"
    if dirExists(testDir): removeDir(testDir)
    createDir(testDir)
    defer:
      if dirExists(testDir): removeDir(testDir)
    let tomlContent = buildTomlContent(
      home = testDir,
      logLevel = "info",
      runtime = "docker",
      defaultProvider = "zai-coding",
      defaultModel = "glm-4.7",
    )
    let tomlPath = testDir / "donkey.toml"
    writeFile(tomlPath, tomlContent)
    let cfg = loadConfig(tomlPath)
    let summary = buildDoctorSummary(cfg)
    check "SQLite-first MAGMA" in summary
    check "zai-coding / glm-4.7" in summary
    check "mode=oci, runtime=docker" in summary
