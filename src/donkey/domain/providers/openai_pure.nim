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



func messageToOpenAI*(msg: ChatMessage): OpenAIMessage =
  var om = OpenAIMessage(
    role:    msg.role,
    content: msg.text,
  )
  if msg.toolCalls.len > 0:
    for tc in msg.toolCalls:
      om.toolCalls.add toolCallToOpenAI(tc)
  if msg.toolCallId.len > 0:
    om.toolCallId = msg.toolCallId
    om.name = msg.text  ## tool result content goes in content field
  om

func openaiMessageToJson*(om: OpenAIMessage): JsonNode =
  result = newJObject()
  result["role"] = % om.role
  if om.content.len > 0:
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
  if om.toolCallId.len > 0:
    result["tool_call_id"] = % om.toolCallId

# ── Public pure API ───────────────────────────────────────────────────────────

func buildMessagesArray*(messages: seq[ChatMessage]): JsonNode =
  ## Converts internal conversation history to OpenAI messages array.
  ##
  ## Usage:  req.messages |> buildMessagesArray
  result = newJArray()
  for msg in messages:
    let om = msg |> messageToOpenAI
    result.add om |> openaiMessageToJson

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

proc buildRequestBody*(model: string; req: CompletionRequest;
                       stream = false): JsonNode =
  ## Builds the full OpenAI /chat/completions request body as JSON.
  ##
  ## Usage:  buildRequestBody("gpt-4", req)
  result = newJObject()
  result["model"] = % model
  var msgs = newJArray()
  if req.system.len > 0:
    var sysMsg = newJObject()
    sysMsg["role"] = %"system"
    sysMsg["content"] = % req.system
    msgs.add sysMsg
  for msg in req.messages:
    msgs.add msg |> messageToOpenAI |> openaiMessageToJson
  result["messages"] = msgs
  if req.tools.len > 0:
    result["tools"] = req.tools.buildToolsArray
  if req.maxTokens > 0:
    result["max_tokens"] = % req.maxTokens
  if req.reasoning:
    result["include_reasoning"] = % true
  result["stream"] = % stream

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
    let choices = body{"choices"}
    if choices.kind != JArray or choices.len == 0:
      return err("No choices in OpenAI response")
    let choice = choices[0]

    let content = choice{"message"}{"content"}.getStr("")

    var toolCalls: seq[ToolCallRequest] = @[]
    if not choice{"message"}{"tool_calls"}.isNil:
      for tcNode in choice{"message"}{"tool_calls"}:
        let args = tcNode{"function"}{"arguments"}.getStr("{}")
        toolCalls.add ToolCallRequest(
          id:        tcNode{"id"}.getStr(""),
          name:      tcNode{"function"}{"name"}.getStr(""),
          inputJson: args,
        )

    let usage = body{"usage"}
    let promptTokens = usage{"prompt_tokens"}.getInt(0)
    let completionTokens = usage{"completion_tokens"}.getInt(0)

    var reasoning = choice{"message"}{"reasoning"}.getStr("")
    if reasoning.len == 0:
      reasoning = choice{"message"}{"reasoning_content"}.getStr("")

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
