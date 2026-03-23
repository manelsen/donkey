## Tests for domain/providers/quirks — pure normalization helpers.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/providers/quirks
import donkey/domain/message

suite "quirks role mapping":

  test "mapRoleForProvider maps assistant to model for Gemini":
    check "assistant".mapRoleForProvider("gemini") == "model"

  test "mapRoleForProvider maps tool to user for Gemini":
    check "tool".mapRoleForProvider("gemini") == "user"

  test "mapRoleForProvider keeps user unchanged for Gemini":
    check "user".mapRoleForProvider("gemini") == "user"

  test "mapRoleForProvider keeps system unchanged for Gemini":
    check "system".mapRoleForProvider("gemini") == "system"

  test "mapRoleForProvider keeps roles unchanged for Anthropic":
    check "assistant".mapRoleForProvider("anthropic") == "assistant"
    check "user".mapRoleForProvider("anthropic") == "user"
    check "tool".mapRoleForProvider("anthropic") == "tool"

  test "mapRoleForProvider keeps roles unchanged for OpenAI":
    check "assistant".mapRoleForProvider("openai") == "assistant"
    check "assistant".mapRoleForProvider("openrouter") == "assistant"

  test "mapRoleForProvider unknown provider returns role unchanged":
    check "assistant".mapRoleForProvider("unknown") == "assistant"

  test "mapRolesForProvider maps all roles in history":
    let msgs = @[
      ChatMessage(role: "assistant", text: "hi"),
      ChatMessage(role: "user", text: "hello"),
    ]
    let mapped = mapRolesForProvider(msgs, "gemini")
    check mapped[0].role == "model"
    check mapped[1].role == "user"

suite "quirks history alternation":

  test "needsRoleAlternation returns true for Gemini":
    check needsRoleAlternation("gemini")

  test "needsRoleAlternation returns false for other providers":
    check not needsRoleAlternation("anthropic")
    check not needsRoleAlternation("openai")
    check not needsRoleAlternation("openrouter")

  test "mergeAdjacentRoleMessages merges consecutive same-role messages":
    let msgs = @[
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "user", text: "world"),
    ]
    let merged = mergeAdjacentRoleMessages(msgs)
    check merged.len == 1
    check merged[0].text == "hello\nworld"

  test "mergeAdjacentRoleMessages keeps different roles separate":
    let msgs = @[
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "assistant", text: "hi there"),
    ]
    let merged = mergeAdjacentRoleMessages(msgs)
    check merged.len == 2

  test "mergeAdjacentRoleMessages handles three consecutive same-role":
    let msgs = @[
      ChatMessage(role: "user", text: "one"),
      ChatMessage(role: "user", text: "two"),
      ChatMessage(role: "user", text: "three"),
    ]
    let merged = mergeAdjacentRoleMessages(msgs)
    check merged.len == 1
    check merged[0].text == "one\ntwo\nthree"

  test "mergeAdjacentRoleMessages empty input returns empty":
    let msgs: seq[ChatMessage] = @[]
    let merged = mergeAdjacentRoleMessages(msgs)
    check merged.len == 0

  test "normalizeHistoryAlternation applies merge for Gemini":
    let msgs = @[
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "user", text: "world"),
    ]
    let normalised = normalizeHistoryAlternation(msgs, "gemini")
    check normalised.len == 1

  test "normalizeHistoryAlternation is identity for OpenAI":
    let msgs = @[
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "user", text: "world"),
    ]
    let normalised = normalizeHistoryAlternation(msgs, "openai")
    check normalised.len == 2

suite "quirks normalizeForProvider":

  test "normalizeForProvider applies all normalizations for Gemini":
    let msgs = @[
      ChatMessage(role: "assistant", text: "hi"),
      ChatMessage(role: "assistant", text: "there"),
      ChatMessage(role: "user", text: "hello"),
    ]
    let normalised = normalizeForProvider(msgs, "gemini")
    check normalised.len == 2
    check normalised[0].role == "model"
    check normalised[0].text == "hi\nthere"
    check normalised[1].role == "user"

  test "normalizeForProvider is identity for OpenAI":
    let msgs = @[
      ChatMessage(role: "assistant", text: "hi"),
      ChatMessage(role: "assistant", text: "there"),
      ChatMessage(role: "user", text: "hello"),
    ]
    let normalised = normalizeForProvider(msgs, "openai")
    check normalised.len == 3
    check normalised[0].role == "assistant"
