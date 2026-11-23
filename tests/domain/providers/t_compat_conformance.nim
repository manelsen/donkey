## Table-driven conformance for the OpenAI-compatible profiles (US-006).
##
## Each row adds a profile and the wire differences it promises. A profile that
## loses a hook fails here without a new per-adapter suite.

import std/[json, unittest]
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_nvidia
import donkey/domain/providers/profile_alibaba
import donkey/domain/providers/profile_fireworks
import donkey/adapters/provider/zhipu
import donkey/adapters/provider/minimax
import donkey/adapters/provider/openrouter

type
  ProfileExpectation = object
    name:               string
    providerIds:        seq[string]   ## descriptor ids this profile serves
    profile:            CompatProfile
    toolChoice:         bool
    toolResultName:     bool
    imageWithToolCalls: bool
    includeReasoning:   bool
    reasoningSplit:     bool
    streamOptions:      bool
    emptyContent:       bool

proc expectations(): seq[ProfileExpectation] =
  @[
    ProfileExpectation(name: "openai-default", providerIds: @["openai"],
      profile: defaultOpenAiProfile(),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: true, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "groq", providerIds: @["groq"],
      profile: defaultOpenAiProfile(id = "groq"),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: true, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "deepseek", providerIds: @["deepseek"],
      profile: defaultOpenAiProfile(id = "deepseek"),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: true, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "opencode-go", providerIds: @["opencode-go"],
      profile: defaultOpenAiProfile(id = "opencode-go"),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: true, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "zen", providerIds: @["zen"],
      profile: defaultOpenAiProfile(id = "zen"),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: true, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "zhipu", providerIds: @["zai", "zai-coding"],
      profile: zhipuCompatProfile(),
      toolChoice: true, toolResultName: false, imageWithToolCalls: false,
      includeReasoning: false, reasoningSplit: false, streamOptions: false,
      emptyContent: true),
    ProfileExpectation(name: "minimax", providerIds: @["minimax"],
      profile: miniMaxCompatProfile(),
      toolChoice: false, toolResultName: false, imageWithToolCalls: false,
      includeReasoning: false, reasoningSplit: true, streamOptions: false,
      emptyContent: true),
    ProfileExpectation(name: "openrouter", providerIds: @["openrouter"],
      profile: openRouterCompatProfile(),
      toolChoice: true, toolResultName: false, imageWithToolCalls: false,
      includeReasoning: true, reasoningSplit: false, streamOptions: true,
      emptyContent: true),
    ProfileExpectation(name: "nvidia", providerIds: @["nvidia"],
      profile: nvidiaCompatProfile(),
      toolChoice: false, toolResultName: false, imageWithToolCalls: true,
      includeReasoning: false, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "alibaba", providerIds: @["alibaba"],
      profile: alibabaCompatProfile(),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: false, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
    ProfileExpectation(name: "fireworks", providerIds: @["fireworks"],
      profile: fireworksCompatProfile(),
      toolChoice: false, toolResultName: true, imageWithToolCalls: true,
      includeReasoning: false, reasoningSplit: false, streamOptions: false,
      emptyContent: false),
  ]

proc toolRequest(): CompletionRequest =
  CompletionRequest(
    messages: @[ChatMessage(role: roleUser, text: "consulte")],
    tools: @[ToolDescription(name: "search", description: "b",
                             schemaJson: """{"type":"object"}""")])

proc toolResultRequest(): CompletionRequest =
  CompletionRequest(messages: @[
    ChatMessage(role: roleTool, text: "saída", toolCallId: "t1")])

proc imageWithToolsRequest(): CompletionRequest =
  CompletionRequest(messages: @[
    ChatMessage(role: roleAssistant, text: "q",
                imageUrl: "data:image/png;base64,QUJD",
                toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                             inputJson: "{}")])])

proc build(c: ProfileExpectation; req: CompletionRequest; stream = false): JsonNode =
  buildCompatRequestBody(c.profile, "m", req, stream)

proc runTests*() =
  suite "compat conformance":

    for c in expectations():
      test c.name & " keeps the tool_choice contract":
        let body = build(c, toolRequest())
        check body.hasKey("tool_choice") == c.toolChoice

      test c.name & " keeps the tool-result name contract":
        let body = build(c, toolResultRequest())
        check body["messages"][0].hasKey("name") == c.toolResultName

      test c.name & " keeps the reasoning contract":
        let body = build(c, CompletionRequest(reasoning: true))
        check body.hasKey("include_reasoning") == c.includeReasoning
        if c.reasoningSplit:
          check body["reasoning_split"].getBool()
        else:
          check not body.hasKey("reasoning_split")

      test c.name & " keeps the image/tool-call precedence":
        let body = build(c, imageWithToolsRequest())
        let content = body["messages"][0]["content"]
        if c.imageWithToolCalls:
          check content.kind == JArray
        else:
          check content.kind == JString

      test c.name & " keeps the empty-content contract":
        let body = build(c, CompletionRequest(messages: @[
          ChatMessage(role: roleUser, text: "")]))
        check body["messages"][0].hasKey("content") == c.emptyContent

      test c.name & " keeps the streaming body contract":
        let body = build(c, CompletionRequest(), stream = true)
        check body["stream"].getBool()
        if c.streamOptions:
          check body["stream_options"]["include_usage"].getBool()
        else:
          check not body.hasKey("stream_options")

    test "the table detects a profile that loses a hook":
      ## Negative control: with tool_choice disabled, the OpenRouter row's
      ## expectation (toolChoice=true) would fail. This proves the assertions are
      ## live, not vacuous.
      var wrong = openRouterCompatProfile()
      wrong.quirks.toolChoiceAuto = false
      let body = buildCompatRequestBody(wrong, "m", toolRequest())
      check not body.hasKey("tool_choice")

    test "every chat-completions descriptor has a conformance row":
      ## A provider with a descriptor but no row would silently skip conformance.
      ## Every `ptOpenAiChat` descriptor must be claimed by exactly one row.
      var covered: seq[string]
      for c in expectations():
        for id in c.providerIds:
          check id notin covered       ## no descriptor claimed twice
          covered.add id
      for descriptor in providerDescriptors():
        if descriptor.transport == ptOpenAiChat:
          check descriptor.id in covered

when isMainModule:
  runTests()
