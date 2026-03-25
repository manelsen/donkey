## Tests for app/setup_wizard — pure setup generation functions.
##
## The interactive wizard is a proc driven by stdin/stdout and is not unit-tested
## here.  These tests cover the pure functions that build config/env content.

import std/[os, strutils, unittest]
import donkey/app/setup_wizard

suite "buildTomlContent":

  test "contains home dir":
    let toml = buildTomlContent(home = "/tmp/donkey_test")
    check toml.contains("/tmp/donkey_test")

  test "contains log_level key":
    let toml = buildTomlContent(home = "/tmp/x")
    check toml.contains("log_level")

  test "default log_level is info":
    let toml = buildTomlContent(home = "/tmp/x")
    check toml.contains("log_level = \"info\"")

suite "buildEnvContent":

  test "telegram token appears when provided":
    let env = buildEnvContent(
      providerName = "zai-coding",
      apiKey = "key123",
      channels = @[("telegram", "tg_token_abc")],
    )
    check env.contains("TELEGRAM_BOT_TOKEN=tg_token_abc")

  test "discord token appears when provided":
    let env = buildEnvContent(
      providerName = "openrouter",
      apiKey = "or_key",
      channels = @[("discord", "dc_token_xyz")],
    )
    check env.contains("DISCORD_BOT_TOKEN=dc_token_xyz")

  test "provider key maps to correct env var for zai-coding":
    let env = buildEnvContent("zai-coding", "mykey", @[])
    check env.contains("ZAI_CODING_API_KEY=mykey")

  test "provider key maps to correct env var for openrouter":
    let env = buildEnvContent("openrouter", "or123", @[])
    check env.contains("OPENROUTER_API_KEY=or123")

  test "provider key maps to correct env var for anthropic":
    let env = buildEnvContent("anthropic", "sk-ant", @[])
    check env.contains("ANTHROPIC_API_KEY=sk-ant")

  test "provider key maps to correct env var for gemini":
    let env = buildEnvContent("gemini", "gm-key", @[])
    check env.contains("GEMINI_API_KEY=gm-key")

  test "omitted channel token left blank":
    let env = buildEnvContent("zai-coding", "k", @[("telegram", "tok")])
    check env.contains("DISCORD_BOT_TOKEN=\n") or
          env.contains("DISCORD_BOT_TOKEN=")

  test "multiple channels both appear":
    let env = buildEnvContent("zai-coding", "k",
      @[("telegram", "tg"), ("discord", "dc")])
    check env.contains("TELEGRAM_BOT_TOKEN=tg")
    check env.contains("DISCORD_BOT_TOKEN=dc")

suite "providerEnvVar":

  test "zai-coding":   check providerEnvVar("zai-coding")   == "ZAI_CODING_API_KEY"
  test "zai":          check providerEnvVar("zai")          == "ZAI_API_KEY"
  test "openrouter":   check providerEnvVar("openrouter")   == "OPENROUTER_API_KEY"
  test "anthropic":    check providerEnvVar("anthropic")    == "ANTHROPIC_API_KEY"
  test "gemini":       check providerEnvVar("gemini")       == "GEMINI_API_KEY"
  test "minimax":      check providerEnvVar("minimax")      == "MINIMAX_API_KEY"
  test "deepseek":     check providerEnvVar("deepseek")     == "DEEPSEEK_API_KEY"
  test "openai":       check providerEnvVar("openai")       == "OPENAI_API_KEY"
  test "unknown":      check providerEnvVar("unknown")      == ""

suite "setupAlreadyDone":

  test "returns false when toml missing":
    check not setupAlreadyDone("/tmp/donkey_nonexistent_xyz")

  test "returns true when toml exists":
    let dir = "/tmp/donkey_test_setup_done"
    createDir(dir)
    writeFile(dir / "donkey.toml", "home = \"" & dir & "\"\n")
    check setupAlreadyDone(dir)
    removeDir(dir)
