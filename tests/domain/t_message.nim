## Domain types + buildPrompt — pure func, zero side effects.

import std/[strutils, unittest]
import donkey/domain/message

suite "Message types":

  test "InboundMessage carries text and sender":
    let msg = InboundMessage(userId: UserId("u1"), text: "olá")
    check msg.text    == "olá"
    check $msg.userId == "u1"

  test "ConversationHistory starts empty":
    let h = newHistory()
    check h.len == 0

  test "history appends user then assistant turns":
    var h = newHistory()
    h.addUser("pergunta")
    h.addAssistant("resposta")
    check h.len == 2
    check h[0].role == roleUser
    check h[1].role == roleAssistant

  test "history trims to maxLen keeping the most recent turns":
    var h = newHistory()
    for i in 1..10:
      h.addUser($i)
    h.trimTo(5)
    check h.len == 5
    check h[0].text == "6"   # oldest retained

suite "buildPrompt":

  test "includes system prompt":
    let req = buildPrompt(
      system   = "Você é o Donkey.",
      history  = newHistory(),
      context  = "",
    )
    check req.system == "Você é o Donkey."

  test "appends memory context to system when non-empty":
    let req = buildPrompt(
      system   = "Base.",
      history  = newHistory(),
      context  = "Ana tem uma filha chamada Beatriz.",
    )
    check req.system.contains("Ana tem uma filha")

  test "carries conversation history":
    var h = newHistory()
    h.addUser("oi")
    h.addAssistant("olá")
    let req = buildPrompt(system = "", history = h, context = "")
    check req.messages.len == 2

  test "empty history produces empty messages":
    let req = buildPrompt(system = "s", history = newHistory(), context = "")
    check req.messages.len == 0

suite "needsOnboarding":
  # File-system check lives in the memory adapter.
  # The domain only decides: no profile → onboard.

  test "true when user has no profile":
    check needsOnboarding(hasUserProfile = false)

  test "false when user already has profile":
    check not needsOnboarding(hasUserProfile = true)
