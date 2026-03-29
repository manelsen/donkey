## Tests for core/hooks/hook_executor.nim — Hook execution integration.

import std/[unittest, options, strtabs]
import donkey/ports/hook
import donkey/core/hooks/hook_executor
import donkey/core/types
import donkey/domain/message

suite "HookExecutor":

  test "HookExecutor can be created":
    let exec = newHookExecutor()
    check exec.registry.hooks.len == 0
    check exec.enabled == true

  test "HookExecutor with disabled state":
    let exec = newHookExecutor(enabled = false)
    check exec.enabled == false

  test "executePhase with no hooks returns continue":
    let exec = newHookExecutor()
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    check result.kind == hrkContinue

  test "executePhase with disabled executor returns continue":
    let exec = newHookExecutor(enabled = false)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    check result.kind == hrkContinue

  test "executePhase runs registered hook":
    var exec = newHookExecutor()
    var hookCalled = false
    let hookFn: HookFn = proc(ctx: HookContext): HookResult =
      hookCalled = true
      newHookResultContinue(ctx)
    exec.registerHook(HookDefinition(name: "test", phase: hpPreLlm, handler: hookFn))
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    discard exec.executePhase(hpPreLlm, ctx)
    check hookCalled == true

  test "executePhase short-circuits on rejection":
    var exec = newHookExecutor()
    var hook2Called = false
    let hookFn1: HookFn = proc(ctx: HookContext): HookResult =
      newHookResultRejected(ctx, "blocked")
    let hookFn2: HookFn = proc(ctx: HookContext): HookResult =
      hook2Called = true
      newHookResultContinue(ctx)
    exec.registerHook(HookDefinition(name: "blocker", phase: hpPreLlm, handler: hookFn1))
    exec.registerHook(HookDefinition(name: "after_blocker", phase: hpPreLlm, handler: hookFn2))
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    check result.kind == hrkRejected
    check result.errorMessage == "blocked"
    check hook2Called == false

  test "executePhase chains modifications":
    var exec = newHookExecutor()
    let hookFn1: HookFn = proc(ctx: HookContext): HookResult =
      newHookResultModified(ctx, "modified1")
    let hookFn2: HookFn = proc(ctx: HookContext): HookResult =
      newHookResultModified(ctx, ctx.message & "_modified2")
    exec.registerHook(HookDefinition(name: "first", phase: hpPreLlm, handler: hookFn1))
    exec.registerHook(HookDefinition(name: "second", phase: hpPreLlm, handler: hookFn2))
    let ctx = newHookContext(UserId("u1"), "s1", "original")
    let result = exec.executePhase(hpPreLlm, ctx)
    check result.kind == hrkContinue
    check result.context.message == "modified1_modified2"

suite "HookExecutor - Pre-Built Hooks":

  test "makeContextInjectionHook helper":
    var exec = newHookExecutor()
    let hook = exec.makeContextInjectionHook("test_context", hpPreLlm, proc(ctx: HookContext): HookResult =
      var modified = ctx
      modified.metadata["injected"] = "true"
      newHookResultModified(modified, ctx.message)
    )
    exec.registerHook(hook)
    check exec.registry.hooks.len == 1
    check exec.registry.hooks[0].name == "test_context"

suite "HookExecutor integration patterns":

  test "context passes through phases":
    var exec = newHookExecutor()
    let hookFn: HookFn = proc(ctx: HookContext): HookResult =
      var modified = ctx
      modified.metadata["key"] = "value"
      newHookResultContinue(modified)
    exec.registerHook(HookDefinition(name: "meta", phase: hpPreLlm, handler: hookFn))
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = exec.executePhase(hpPreLlm, ctx)
    check result.context.metadata["key"] == "value"
