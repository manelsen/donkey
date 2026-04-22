## Domain types + buildPrompt — pure func, zero side effects.

import std/[strutils, unittest]
import donkey/domain/message
import donkey/core/pipeops

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

  test "trimTo drops orphan tool results at the boundary":
    var h = newHistory()
    h.addUser("u1")
    h.addAssistantWithToolCalls("", @[ToolCallRequest(id: "call_1", name: "search", inputJson: "{}")])
    h.addToolResult(id = "call_1", name = "search", output = "results here")
    h.addAssistant("done")
    h.trimTo(2)
    check h.len == 1
    check h[0].role == roleAssistant
    check h[0].text == "done"

  test "trimTo preserves tool result when its assistant tool call is still retained":
    var h = newHistory()
    h.addUser("u1")
    h.addAssistantWithToolCalls("", @[ToolCallRequest(id: "call_1", name: "search", inputJson: "{}")])
    h.addToolResult(id = "call_1", name = "search", output = "results here")
    h.addAssistant("done")
    h.trimTo(3)
    check h.len == 3
    check h[0].toolCalls.len == 1
    check h[1].role == roleTool
    check h[1].toolCallId == "call_1"

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

suite "ToolDescription":

  test "holds name, description, schemaJson":
    let td = ToolDescription(name: "search", description: "web search", schemaJson: "{}")
    check td.name        == "search"
    check td.description == "web search"
    check td.schemaJson  == "{}"

suite "ToolCallRequest":

  test "holds id, name, inputJson":
    let tc = ToolCallRequest(id: "call_1", name: "search", inputJson: "{\"q\":\"nim\"}")
    check tc.id        == "call_1"
    check tc.name      == "search"
    check tc.inputJson == "{\"q\":\"nim\"}"

suite "ChatMessage vision":

  test "addUserWithImage stores text and imageUrl":
    var h = newHistory()
    h.addUserWithImage("what is this?", "https://example.com/pic.jpg")
    check h.len          == 1
    check h[0].role      == roleUser
    check h[0].text      == "what is this?"
    check h[0].imageUrl  == "https://example.com/pic.jpg"

  test "addUser leaves imageUrl empty":
    var h = newHistory()
    h.addUser("plain text")
    check h[0].imageUrl == ""

  test "addUserWithImage is trimmed by trimTo":
    var h = newHistory()
    for i in 1..5: h.addUserWithImage("img", "url")
    h.trimTo(3)
    check h.len == 3
    check h[0].imageUrl == "url"

suite "ChatMessage tool result":

  test "addToolResult adds role=tool message":
    var h = newHistory()
    h.addToolResult(id = "call_1", name = "search", output = "results here")
    check h.len          == 1
    check h[0].role      == roleTool
    check h[0].toolCallId == "call_1"
    check "search" in h[0].text
    check "results here" in h[0].text

suite "ToolResultKind":

  test "usage error label is stable":
    check toolResultKindLabel(trkUsageError) == "usage_error"

suite "CompletionResponse toolCalls":

  test "toolCalls defaults to empty seq":
    let resp = CompletionResponse(text: "hi", inputTokens: 1, outputTokens: 1)
    check resp.toolCalls.len == 0

  test "toolCalls populated when set":
    let resp = CompletionResponse(
      text: "",
      inputTokens: 5,
      outputTokens: 0,
      toolCalls: @[ToolCallRequest(id: "c1", name: "fn", inputJson: "{}")]
    )
    check resp.toolCalls.len     == 1
    check resp.toolCalls[0].name == "fn"

suite "splitChunks":

  test "short text: returns single chunk":
    let chunks = splitChunks("hello", 2000)
    check chunks.len == 1
    check chunks[0]  == "hello"

  test "exactly at limit: single chunk":
    let text = 'a'.repeat(2000)
    check splitChunks(text, 2000).len == 1

  test "one char over limit: two chunks, both within limit":
    let text = 'a'.repeat(2001)
    let chunks = splitChunks(text, 2000)
    check chunks.len == 2
    for c in chunks:
      check c.len <= 2000

  test "no text is lost":
    let text = 'z'.repeat(5500)
    let chunks = splitChunks(text, 2000)
    check chunks.join("") == text

  test "all chunks respect the limit":
    let text = 'x'.repeat(7777)
    for c in splitChunks(text, 2000):
      check c.len <= 2000

  test "prefers newline split when possible":
    ## "line one\n" (9) + "line two\n" (9) = 18 chars — fits in limit=20.
    ## "line one\nline two\n" (18) + "line three" (10) — second group too big → split.
    let text = "line one\nline two\nline three"
    let chunks = splitChunks(text, 20)
    for c in chunks:
      check c.len <= 20
    check chunks.join("") == text

suite "buildPrompt with tools":

  test "tools field carried through unchanged":
    let tools = @[ToolDescription(name: "t", description: "d", schemaJson: "{}")]
    let req = buildPrompt(system = "s", history = newHistory(), context = "", tools = tools)
    check req.tools.len     == 1
    check req.tools[0].name == "t"

  test "tools defaults to empty when not supplied":
    let req = buildPrompt(system = "s", history = newHistory(), context = "")
    check req.tools.len == 0
