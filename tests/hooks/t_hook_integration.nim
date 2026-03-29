## Integration tests for the complete hook system.

import std/[unittest, strtabs]
import donkey/ports/hook
import donkey/core/hooks/hook_executor
import donkey/core/hooks/hook_config
import donkey/core/hooks/context_injection_hook
import donkey/core/types

suite "Hook System Integration":

  test "HookExecutor with multiple phases":
    var exec = newHookExecutor()
    var preLlmCalled = false
    var postLlmCalled = false
    
    proc preHook(ctx: HookContext): HookResult {.gcsafe.} =
      preLlmCalled = true
      return newHookResultContinue(ctx)
    
    proc postHook(ctx: HookContext): HookResult {.gcsafe.} =
      postLlmCalled = true
      return newHookResultContinue(ctx)
    
    exec.registerHook(HookDefinition(name: "pre", phase: hpPreLlm, handler: preHook))
    exec.registerHook(HookDefinition(name: "post", phase: hpPostLlm, handler: postHook))
    
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    discard exec.executePhase(hpPreLlm, ctx)
    check preLlmCalled == true
    check postLlmCalled == false

  test "Hook chaining preserves context":
    var exec = newHookExecutor()
    
    proc hook1(ctx: HookContext): HookResult {.gcsafe.} =
      var modified = ctx
      modified.metadata["step1"] = "done"
      return newHookResultContinue(modified)
    
    proc hook2(ctx: HookContext): HookResult {.gcsafe.} =
      var modified = ctx
      modified.metadata["step2"] = "done"
      return newHookResultContinue(modified)
    
    exec.registerHook(HookDefinition(name: "first", phase: hpPreLlm, handler: hook1))
    exec.registerHook(HookDefinition(name: "second", phase: hpPreLlm, handler: hook2))
    
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    
    check result.kind == hrkContinue
    check result.context.metadata["step1"] == "done"
    check result.context.metadata["step2"] == "done"

  test "Hook rejection short-circuits chain":
    var exec = newHookExecutor()
    var secondCalled = false
    
    proc blocker(ctx: HookContext): HookResult {.gcsafe.} =
      return newHookResultRejected(ctx, "blocked by hook1")
    
    proc second(ctx: HookContext): HookResult {.gcsafe.} =
      secondCalled = true
      return newHookResultContinue(ctx)
    
    exec.registerHook(HookDefinition(name: "blocker", phase: hpPreLlm, handler: blocker))
    exec.registerHook(HookDefinition(name: "second", phase: hpPreLlm, handler: second))
    
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    
    check result.kind == hrkRejected
    check result.errorMessage == "blocked by hook1"
    check secondCalled == false

  test "ContextInjectionHook via makeContextInjectionHookFn":
    let hookFn = makeContextInjectionHookFn(name = "test", searchFn = nil)
    
    let ctx = newHookContext(UserId("u1"), "s1", "hello")
    let result = hookFn(ctx)
    
    check result.kind == hrkContinue
    check result.context.metadata.contains(ContextHintKey)

  test "HookConfigLoader integrates with HookExecutor":
    var loader = newHookConfigLoader()
    loader.addHookConfig(HookConfig(name: "hook1", enabled: true, phase: hpPreLlm))
    loader.addHookConfig(HookConfig(name: "hook2", enabled: true, phase: hpPostLlm))
    loader.addHookConfig(HookConfig(name: "hook3", enabled: false, phase: hpPreLlm))
    
    let preHooks = loader.getHooksForPhase(hpPreLlm, onlyEnabled = true)
    check preHooks.len == 1
    check preHooks[0].name == "hook1"

  test "Disabled executor bypasses all hooks":
    var exec = newHookExecutor(enabled = false)
    var hookCalled = false
    
    proc testHook(ctx: HookContext): HookResult {.gcsafe.} =
      hookCalled = true
      return newHookResultContinue(ctx)
    
    exec.registerHook(HookDefinition(name: "test", phase: hpPreLlm, handler: testHook))
    
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    
    check result.kind == hrkContinue
    check hookCalled == false

  test "All hook phases are defined":
    check ord(hpPreLlm) == 0
    check ord(hpPostLlm) == 1
    check ord(hpPreTool) == 2
    check ord(hpPostTool) == 3
    check ord(hpPostResponse) == 4
