## Tests for core/hooks/context_injection_hook.nim — Abstract context injection.

import std/[unittest, strtabs]
import donkey/ports/hook
import donkey/ports/memory
import donkey/core/hooks/context_injection_hook
import donkey/core/types

suite "ContextInjectionHook":

  test "makeContextInjectionHookFn creates valid hook":
    let hookFn = makeContextInjectionHookFn(name = "test_injection", searchFn = nil)
    let ctx = newHookContext(UserId("u1"), "s1", "Hello")
    let result = hookFn(ctx)
    check result.kind == hrkContinue
    check result.context.metadata.contains(ContextHintKey)

  test "hook without searchFn returns continue":
    let hookFn = makeContextInjectionHookFn("test", searchFn = nil)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

suite "Context injection via metadata":

  test "hook injects context_hint in metadata":
    let hookFn = makeContextInjectionHookFn("test", searchFn = nil)
    let ctx = newHookContext(UserId("u1"), "s1", "Hello")
    let result = hookFn(ctx)
    check result.context.metadata.contains(ContextHintKey)

  test "hook injects memory_hits in metadata":
    let hookFn = makeContextInjectionHookFn("test", searchFn = nil)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = hookFn(ctx)
    check result.context.metadata.contains(MemoryHitsKey)

suite "formatContextHint":

  test "empty hits returns empty string":
    let hint = formatContextHint(@[])
    check hint == ""

  test "single hit formats correctly":
    let hits = @[MemoryHit(content: "Test content", score: 0.9, kind: "memory")]
    let hint = formatContextHint(hits)
    check hint.len > 0
    check hint != "Contexto relevante:"

  test "long content truncated":
    var longContent = ""
    for i in 0..<300:
      longContent &= "x"
    let hits = @[MemoryHit(content: longContent, score: 0.9, kind: "memory")]
    let hint = formatContextHint(hits)
    check hint.len < 300

  test "multiple hits formats correctly":
    let hits = @[
      MemoryHit(content: "First memory", score: 0.9, kind: "memory"),
      MemoryHit(content: "Second memory", score: 0.8, kind: "memory"),
    ]
    let hint = formatContextHint(hits, topK = 5)
    check hint.len > 0

suite "Hook function signature":

  test "returns HookFn compatible type":
    let hookFn = makeContextInjectionHookFn("test", searchFn = nil)
    let ctx = newHookContext(UserId("u1"), "s1", "msg")
    let result = hookFn(ctx)
    check result.kind in {hrkContinue, hrkModified, hrkRejected}
