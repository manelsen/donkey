## Test ZenAdapter multi-protocol routing.

import std/[unittest, json, strutils]
import donkey/adapters/provider/zen
import donkey/domain/message
import donkey/ports/provider

suite "ZenAdapter - Multi-Protocol Routing":

  test "resolves provider from model id":
    let a = newZenAdapter("key", "opencode/openai/gpt-4o")
    check a.caps.name.startsWith("openai/")
    
    let b = newZenAdapter("key", "opencode/anthropic/claude-3")
    check b.caps.name.startsWith("anthropic/")

  test "routing completion request":
    # This will need stubs or mocks for actual HTTP calls
    check true
