## Tests for adapters/hooks/memory_capture_hook.nim — Memory capture hook.

import std/[unittest, strtabs]
import donkey/ports/hook
import donkey/adapters/hooks/memory_capture_hook
import donkey/core/types

suite "MemoryCaptureHook":

  test "MemoryCaptureConfig with defaults":
    let cfg = newMemoryCaptureConfig()
    check cfg.captureFacts == true
    check cfg.captureDecisions == true
    check cfg.capturePreferences == true
    check cfg.enabled == true

  test "MemoryCaptureConfig with custom values":
    let cfg = newMemoryCaptureConfig(captureFacts = false)
    check cfg.captureFacts == false

  test "makeMemoryCaptureHook creates valid hook":
    let hookFn = makeMemoryCaptureHook(
      appendMemoryFn = nil,
      config = newMemoryCaptureConfig()
    )
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

  test "hook returns continue without appendFn":
    let hookFn = makeMemoryCaptureHook(
      appendMemoryFn = nil,
      config = newMemoryCaptureConfig()
    )
    let ctx = newHookContext(UserId("u1"), "s1", "hello world")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

  test "createMemoryCaptureHookDefinition creates valid definition":
    let def = createMemoryCaptureHookDefinition(
      name = "my_capture",
      appendMemoryFn = nil,
      config = newMemoryCaptureConfig()
    )
    check def.name == "my_capture"
    check def.phase == hpPostLlm

  test "formatMemoryEntry creates valid entry":
    let entry = formatMemoryEntry("Test content", "Fact")
    check entry.len > 0

  test "disabled hook returns continue":
    let cfg = newMemoryCaptureConfig(enabled = false)
    let hookFn = makeMemoryCaptureHook(appendMemoryFn = nil, config = cfg)
    let ctx = newHookContext(UserId("u1"), "s1", "test")
    let result = hookFn(ctx)
    check result.kind == hrkContinue

  test "enabled config allows hook to run":
    let cfg = newMemoryCaptureConfig(enabled = true)
    let hookFn = makeMemoryCaptureHook(appendMemoryFn = nil, config = cfg)
    let ctx = newHookContext(UserId("u1"), "s1", "test message")
    let result = hookFn(ctx)
    check result.kind == hrkContinue
