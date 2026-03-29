## Tests for ports/hook.nim — Hook Port core interfaces.

import std/[unittest, options, strtabs]
import donkey/ports/hook
import donkey/core/types
import donkey/domain/message

suite "HookPort concept":

  test "HookPhase has all required phases":
    check ord(hpPreLlm) == 0
    check ord(hpPostLlm) == 1
    check ord(hpPreTool) == 2
    check ord(hpPostTool) == 3
    check ord(hpPostResponse) == 4

  test "HookContext can be created with required fields":
    let ctx = newHookContext(
      userId = UserId("user123"),
      sessionId = "session456",
      message = "Hello"
    )
    check ctx.userId == UserId("user123")
    check ctx.sessionId == "session456"
    check ctx.message == "Hello"

  test "HookContext can be created with all fields":
    var history: ConversationHistory = @[]
    history.add(ChatMessage(role: roleUser, text: "Previous"))
    let ctx = newHookContext(
      userId = UserId("user123"),
      sessionId = "session456",
      message = "Hello",
      history = some(history),
      metadata = newStringTable()
    )
    check ctx.userId == UserId("user123")
    check ctx.message == "Hello"
    check ctx.history.isSome()
    check ctx.history.get().len == 1

  test "HookResult can be Continue":
    let ctx = newHookContext(UserId("u1"), "s1", "msg")
    let result = newHookResultContinue(ctx)
    check result.kind == hrkContinue

  test "HookResult can be Modified":
    let ctx = newHookContext(UserId("u1"), "s1", "Hello")
    let result = newHookResultModified(ctx, "Hello World")
    check result.kind == hrkModified
    check result.context.message == "Hello World"

  test "HookResult can be Rejected":
    let ctx = newHookContext(UserId("u1"), "s1", "bad")
    let result = newHookResultRejected(ctx, "Message blocked")
    check result.kind == hrkRejected
    check result.errorMessage == "Message blocked"

  test "HookResult continue preserves context":
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = newHookResultContinue(ctx)
    check result.context.userId == ctx.userId
    check result.context.sessionId == ctx.sessionId

suite "HookContext immutability":

  test "context with empty message":
    let ctx = newHookContext(UserId("u1"), "s1", "")
    check ctx.message == ""

  test "context with unicode message":
    let ctx = newHookContext(UserId("u1"), "s1", "Ola Mundo")
    check ctx.message == "Ola Mundo"

suite "HookRegistry":

  test "newHookRegistry creates empty registry":
    let reg = newHookRegistry()
    check reg.hooks.len == 0

  test "registerHook adds to registry":
    var reg = newHookRegistry()
    let hook = HookDefinition(name: "test_hook", phase: hpPreLlm, handler: nil)
    reg.registerHook(hook)
    check reg.hooks.len == 1
    check reg.hooks[0].name == "test_hook"

  test "getHooksForPhase returns correct hooks":
    var reg = newHookRegistry()
    reg.registerHook(HookDefinition(name: "pre1", phase: hpPreLlm, handler: nil))
    reg.registerHook(HookDefinition(name: "post1", phase: hpPostLlm, handler: nil))
    reg.registerHook(HookDefinition(name: "pre2", phase: hpPreLlm, handler: nil))
    let preHooks = reg.getHooksForPhase(hpPreLlm)
    check preHooks.len == 2

  test "getHooksForPhase returns empty for phase with no hooks":
    var reg = newHookRegistry()
    reg.registerHook(HookDefinition(name: "pre1", phase: hpPreLlm, handler: nil))
    let postHooks = reg.getHooksForPhase(hpPostLlm)
    check postHooks.len == 0

suite "HookDefinition":

  test "HookDefinition can be created with required fields":
    let def = HookDefinition(name: "my_hook", phase: hpPreLlm, handler: nil)
    check def.name == "my_hook"
    check def.phase == hpPreLlm
    check def.handler.isNil()

  test "HookDefinition can store config":
    let def = HookDefinition(name: "rag_hook", phase: hpPreLlm, handler: nil)
    check def.config.isNone()
