## Tests for core/hooks/hook_config.nim — Hook configuration.

import std/[unittest, strtabs, json, options]
import donkey/ports/hook
import donkey/core/hooks/hook_config
import donkey/core/types

suite "HookConfigLoader":

  test "newHookConfigLoader creates empty loader":
    let loader = newHookConfigLoader()
    check loader.configs.len == 0

  test "HookConfig can be created":
    let cfg = HookConfig(name: "test_hook", enabled: true, phase: hpPreLlm)
    check cfg.name == "test_hook"
    check cfg.enabled == true
    check cfg.phase == hpPreLlm

  test "addHookConfig adds to loader":
    var loader = newHookConfigLoader()
    loader.addHookConfig(HookConfig(name: "test", enabled: true, phase: hpPreLlm))
    check loader.configs.len == 1

  test "getHookConfig returns config by name":
    var loader = newHookConfigLoader()
    loader.addHookConfig(HookConfig(name: "hook1", enabled: true, phase: hpPreLlm))
    loader.addHookConfig(HookConfig(name: "hook2", enabled: true, phase: hpPostLlm))
    let found = loader.getHookConfig("hook1")
    check found.isSome()
    check found.get().name == "hook1"

  test "getHookConfig returns none for missing":
    var loader = newHookConfigLoader()
    let found = loader.getHookConfig("nonexistent")
    check found.isNone()

  test "getHooksForPhase returns correct configs":
    var loader = newHookConfigLoader()
    loader.addHookConfig(HookConfig(name: "pre1", enabled: true, phase: hpPreLlm))
    loader.addHookConfig(HookConfig(name: "post1", enabled: true, phase: hpPostLlm))
    loader.addHookConfig(HookConfig(name: "pre2", enabled: true, phase: hpPreLlm))
    let preHooks = loader.getHooksForPhase(hpPreLlm)
    check preHooks.len == 2

  test "enabled flag filters hooks":
    var loader = newHookConfigLoader()
    loader.addHookConfig(HookConfig(name: "enabled", enabled: true, phase: hpPreLlm))
    loader.addHookConfig(HookConfig(name: "disabled", enabled: false, phase: hpPreLlm))
    let preHooks = loader.getHooksForPhase(hpPreLlm, onlyEnabled = true)
    check preHooks.len == 1

suite "parsePhaseStr":

  test "parses pre_llm":
    let phase = parsePhaseStr("pre_llm")
    check phase.isSome()
    check phase.get() == hpPreLlm

  test "parses post_llm":
    let phase = parsePhaseStr("post_llm")
    check phase.isSome()
    check phase.get() == hpPostLlm

  test "returns none for invalid":
    let phase = parsePhaseStr("invalid")
    check phase.isNone()
