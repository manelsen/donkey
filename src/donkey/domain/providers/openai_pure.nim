## openai_pure.nim — pure OpenAI / OpenRouter wire-format helpers.
##
## Formats `CompletionRequest` into an OpenAI-compatible JSON request body,
## and parses an OpenAI JSON response into a `CompletionResponse`.
##
## No I/O, no side effects. All functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (req |> buildRequestBody)
##   |>->  — last-arg pipe         (json |>-> parseResponseFrom)
##   >>=   — Result chain          (body >>= parseResponse)
##
## OpenAI API reference:
##   https://platform.openai.com/docs/api-reference/chat/create
##   https://platform.openai.com/docs/api-reference/chat/object

import std/json
import ../../core/pipeops
import ../../domain/message

# ── OpenAI wire types ─────────────────────────────────────────────────────────

type
  OpenAIMessage* = object
    role*:       string
    content*:    string
    imageUrl*:   string    ## data URL or http(s) URL for a vision turn
    name*:       string    ## optional; for function responses
    toolCalls*:  seq[OpenAIToolCall]
    toolCallId*: string    ## for tool role messages

  OpenAIToolCall* = object
    id*:       string
    typ*:      string     ## always "function"
    function*: OpenAIFunction

  OpenAIFunction* = object
    name*:      string
    arguments*: string    ## JSON string of arguments object

  OpenAIFunctionTool* = object
    name*:        string
    description*: string
    parameters*: JsonNode  ## JSON Schema object

  OpenAIUsage* = object
    promptTokens*:     int
    completionTokens*: int
    totalTokens*:      int

  OpenAIChoice* = object
    message*:       OpenAIMessage
    finishReason*:  string

  OpenAIResponse* = object
    id*:      string
    model*:   string
    choices*: seq[OpenAIChoice]
    usage*:   OpenAIUsage

  OpenAiWireQuirks* = object
    ## Wire differences between OpenAI-compatible providers. Defaults are the
    ## OpenAI behavior; a profile turns on only what its provider needs.
    toolResultName*:        bool  ## send `name` on a tool result (dup of content)
    emptyContentKey*:       bool  ## send `content: ""` for an empty plain turn
    toolCallsEmptyContent*: bool  ## send `content: ""` on an assistant tool call
    imageEmptyTextPart*:    bool  ## send an empty text part before the image
    imageWithToolCalls*:    bool  ## keep the image when the message has tool calls
    toolChoiceAuto*:        bool  ## add tool_choice="auto" when tools are present
    omitStreamKey*:         bool  ## non-streaming bodies omit `stream`
    includeReasoningField*: bool  ## send include_reasoning when req.reasoning


const
  OpenAiWireQuirksDefault* = OpenAiWireQuirks(
    toolResultName: true, imageWithToolCalls: true, includeReasoningField: true)

func defaultOpenAiQuirks*(): OpenAiWireQuirks =
  OpenAiWireQuirksDefault

# ── Internal pure helpers ─────────────────────────────────────────────────────

func roleToOpenAI*(role: string): string =
  ## Maps internal role names to OpenAI wire format.
  ## Identity for OpenAI; overridden in quirks for other providers.
  role

func toolCallToOpenAI*(tc: ToolCallRequest): OpenAIToolCall =
  OpenAIToolCall(
    id:       tc.id,
    typ:      "function",
    function: OpenAIFunction(
      name:      tc.name,
      arguments: tc.inputJson,
    ),
  )



func messageToOpenAIWithQuirks*(msg: ChatMessage;
                                quirks: OpenAiWireQuirks): OpenAIMessage =
  var om = OpenAIMessage(
    role:     msg.role,
    content:  msg.text,
    imageUrl: msg.imageUrl,
  )
  if msg.toolCalls.len > 0:
    for tc in msg.toolCalls:
      om.toolCalls.add toolCallToOpenAI(tc)
  if msg.toolCallId.len > 0:
    om.toolCallId = msg.toolCallId
    if quirks.toolResultName:
      om.name = msg.text  ## tool result content goes in content field
  om

func messageToOpenAI*(msg: ChatMessage): OpenAIMessage =
  messageToOpenAIWithQuirks(msg, defaultOpenAiQuirks())

func openaiMessageToJsonWithQuirks*(om: OpenAIMessage;
                                    quirks: OpenAiWireQuirks): JsonNode =
  result = newJObject()
  result["role"] = % om.role
  let toolCallWins = om.toolCalls.len > 0 and not quirks.imageWithToolCalls
  if not toolCallWins and om.imageUrl.len > 0:
    ## Vision turns carry an array of parts; a data URL is passed through as
    ## `image_url` (the OpenAI-compatible shape). The text part is optional.
    var content = newJArray()
    if om.content.len > 0 or quirks.imageEmptyTextPart:
      content.add(%* {"type": "text", "text": om.content})
    content.add(%* {"type": "image_url", "image_url": {"url": om.imageUrl}})
    result["content"] = content
  elif om.content.len > 0 or quirks.emptyContentKey or
       (om.toolCalls.len > 0 and quirks.toolCallsEmptyContent):
    result["content"] = % om.content
  if om.name.len > 0:
    result["name"] = % om.name
  if om.toolCalls.len > 0:
    result["tool_calls"] = newJArray()
    for tc in om.toolCalls:
      var tcNode = newJObject()
      tcNode["id"] = % tc.id
      tcNode["type"] = % tc.typ
      tcNode["function"] = newJObject()
      tcNode["function"]["name"] = % tc.function.name
      tcNode["function"]["arguments"] = % tc.function.arguments
      result["tool_calls"].add tcNode
  if om.toolCallId.len > 0 and om.role == roleTool:
    result["tool_call_id"] = % om.toolCallId

func openaiMessageToJson*(om: OpenAIMessage): JsonNode =
  openaiMessageToJsonWithQuirks(om, defaultOpenAiQuirks())

# ── Public pure API ───────────────────────────────────────────────────────────

func buildMessagesArrayWithQuirks*(messages: seq[ChatMessage];
                                   quirks: OpenAiWireQuirks): JsonNode =
  result = newJArray()
  for msg in messages:
    let om = messageToOpenAIWithQuirks(msg, quirks)
    result.add openaiMessageToJsonWithQuirks(om, quirks)

func buildMessagesArray*(messages: seq[ChatMessage]): JsonNode =
  ## Converts internal conversation history to OpenAI messages array.
  ##
  ## Usage:  req.messages |> buildMessagesArray
  buildMessagesArrayWithQuirks(messages, defaultOpenAiQuirks())

proc buildToolsArray*(tools: seq[ToolDescription]): JsonNode =
  ## Converts internal tool descriptions to OpenAI tools array.
  ##
  ## Usage:  req.tools |> buildToolsArray
  result = newJArray()
  for td in tools:
    var toolNode = newJObject()
    toolNode["type"] = %"function"
    toolNode["function"] = newJObject()
    toolNode["function"]["name"] = % td.name
    toolNode["function"]["description"] = % td.description
    try:
      toolNode["function"]["parameters"] = parseJson(td.schemaJson)
    except JsonParsingError:
      toolNode["function"]["parameters"] = newJObject()  ## fallback to empty schema
    result.add toolNode

proc buildRequestBodyWithQuirks*(model: string; req: CompletionRequest;
                                 stream = false;
                                 quirks = defaultOpenAiQuirks()): JsonNode =
  ## Full OpenAI-compatible body with the provider's wire quirks. The default
  ## quirks reproduce the OpenAI payload exactly.
  result = newJObject()
  result["model"] = % model
  var msgs = newJArray()
  if req.system.len > 0:
    var sysMsg = newJObject()
    sysMsg["role"] = %"system"
    sysMsg["content"] = % req.system
    msgs.add sysMsg
  for msg in req.messages:
    let om = messageToOpenAIWithQuirks(msg, quirks)
    msgs.add openaiMessageToJsonWithQuirks(om, quirks)
  result["messages"] = msgs
  if req.tools.len > 0:
    result["tools"] = req.tools.buildToolsArray
    if quirks.toolChoiceAuto:
      result["tool_choice"] = %"auto"
  if req.maxTokens > 0:
    result["max_tokens"] = % req.maxTokens
  if req.reasoning and quirks.includeReasoningField:
    result["include_reasoning"] = % true
  if not (quirks.omitStreamKey and not stream):
    result["stream"] = % stream

proc buildRequestBody*(model: string; req: CompletionRequest;
                       stream = false): JsonNode =
  ## OpenAI payload without provider quirks.
  buildRequestBodyWithQuirks(model, req, stream, defaultOpenAiQuirks())

func parseToolCallsFromChoice*(choice: OpenAIChoice): seq[ToolCallRequest] =
  ## Extracts tool calls from an OpenAI choice message if present.
  if choice.message.toolCalls.len > 0:
    for tc in choice.message.toolCalls:
      result.add ToolCallRequest(
        id:        tc.id,
        name:      tc.function.name,
        inputJson: tc.function.arguments,
      )

proc parseResponseFrom*(body: JsonNode): Result[CompletionResponse, string] =
  ## Parses an OpenAI /chat/completions response body into CompletionResponse.
  ##
  ## Usage:  responseJson >>= parseResponseFrom
  try:
    if body.isNil or body.kind != JObject:
      return err("Invalid OpenAI response: not an object")
    let choices = body{"choices"}
    if choices.isNil or choices.kind != JArray or choices.len == 0:
      return err("No choices in OpenAI response")
    let choice = choices[0]
    if choice.isNil or choice.kind != JObject:
      return err("Invalid OpenAI response: choice is not an object")
    let message = choice{"message"}
    if message.isNil or message.kind != JObject:
      return err("Invalid OpenAI response: missing message")

    let content = message{"content"}.getStr("")

    var toolCalls: seq[ToolCallRequest] = @[]
    let callsNode = message{"tool_calls"}
    if not callsNode.isNil and callsNode.kind == JArray:
      for tcNode in callsNode:
        if tcNode.isNil or tcNode.kind != JObject:
          continue
        let fn = tcNode{"function"}
        if fn.isNil or fn.kind != JObject:
          continue
        toolCalls.add ToolCallRequest(
          id:        tcNode{"id"}.getStr(""),
          name:      fn{"name"}.getStr(""),
          inputJson: fn{"arguments"}.getStr("{}"),
        )

    let usage = body{"usage"}
    var promptTokens = 0
    var completionTokens = 0
    if not usage.isNil and usage.kind == JObject:
      promptTokens = usage{"prompt_tokens"}.getInt(0)
      completionTokens = usage{"completion_tokens"}.getInt(0)

    var reasoning = message{"reasoning"}.getStr("")
    if reasoning.len == 0:
      reasoning = message{"reasoning_content"}.getStr("")

    ok CompletionResponse(
      text:         content,
      reasoning:    reasoning,
      inputTokens:  promptTokens,
      outputTokens: completionTokens,
      toolCalls:   toolCalls,
    )
  except JsonKindError, KeyError, ValueError:
    err "Failed to parse OpenAI response: " & getCurrentExceptionMsg()

func toolResultToOpenAIMessage*(id, name, output: string;
                                kind = trkOutput): JsonNode =
  ## Formats a tool result as an OpenAI tool message.
  ##
  ## Usage:  toolResult |> toolResultToOpenAIMessage
  result = newJObject()
  result["role"] = %"tool"
  result["tool_call_id"] = % id
  result["content"] = % output
