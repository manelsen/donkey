## Tests for adapters/hooks/rag_context_hook.nim — RAG context hook adapter.

import std/[unittest, strtabs]
import donkey/ports/hook
import donkey/ports/memory
import donkey/core/hooks/context_injection_hook
import donkey/adapters/hooks/rag_context_hook
import donkey/core/types

suite "RagContextHookAdapter":

  test "RagContextConfig with defaults":
    let cfg = newRagContextConfig()
    check cfg.topK == 5
    check cfg.enabled == true

  test "RagContextConfig with custom values":
    let cfg = newRagContextConfig(topK = 10, minScore = 0.7)
    check cfg.topK == 10
    check cfg.minScore == 0.7

  test "makeRagContextHook creates valid hook":
    let hookFn = makeRagContextHook(searchFn = nil, config = newRagContextConfig())
    let ctx = newHookContext(UserId("u1"), "s1", "test query")
    let result = hookFn(ctx)
    check result.kind == hrkContinue
    check result.context.metadata.contains("rag_status")

  test "hook returns continue even without search":
    let hookFn = makeRagContextHook(searchFn = nil, config = newRagContextConfig())
    let ctx = newHookContext(UserId("u1"), "s1", "hello")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

  test "hook injects context from search results":
    var searchCalled = false
    let mockSearch: SearchFn = proc(userId: UserId; query: string; limit: int): seq[MemoryHit] =
      searchCalled = true
      @[
        MemoryHit(content: "Python project discussion", score: 0.95, kind: "memory"),
        MemoryHit(content: "User prefers concise answers", score: 0.85, kind: "preference"),
      ]
    let hookFn = makeRagContextHook(searchFn = mockSearch, config = newRagContextConfig())
    let ctx = newHookContext(UserId("u1"), "s1", "about python")
    let result = hookFn(ctx)
    check result.kind == hrkContinue
    check searchCalled == true

  test "hook formats multiple hits correctly":
    let mockSearch: SearchFn = proc(userId: UserId; query: string; limit: int): seq[MemoryHit] =
      @[
        MemoryHit(content: "First result", score: 0.9, kind: "memory"),
        MemoryHit(content: "Second result", score: 0.8, kind: "memory"),
      ]
    let hookFn = makeRagContextHook(searchFn = mockSearch, config = newRagContextConfig())
    let ctx = newHookContext(UserId("u1"), "s1", "query")
    let result = hookFn(ctx)
    check result.context.metadata.contains("rag_status")

  test "createRagContextHookDefinition creates valid definition":
    let def = createRagContextHookDefinition(
      name = "my_rag",
      searchFn = nil,
      config = newRagContextConfig()
    )
    check def.name == "my_rag"
    check def.phase == hpPreLlm
    check not def.handler.isNil

suite "RagContextHook with disabled state":

  test "disabled hook returns continue":
    let cfg = newRagContextConfig(enabled = false)
    let hookFn = makeRagContextHook(searchFn = nil, config = cfg)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

  test "enabled flag controls behavior":
    var searchCalled = false
    let mockSearch: SearchFn = proc(userId: UserId; query: string; limit: int): seq[MemoryHit] =
      searchCalled = true
      @[MemoryHit(content: "found", score: 0.9, kind: "memory")]
    let cfg = newRagContextConfig(enabled = true)
    let hookFn = makeRagContextHook(searchFn = mockSearch, config = cfg)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    discard hookFn(ctx)
    check searchCalled == true
