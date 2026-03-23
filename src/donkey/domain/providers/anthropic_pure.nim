## anthropic_pure.nim — pure Anthropic API wire-format helpers.
##
## Formats `CompletionRequest` into an Anthropic Messages API JSON body,
## and parses an Anthropic response into a `CompletionResponse`.
##
## No I/O, no side effects. All functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (req |> buildRequestBody)
##   >>=   — Result chain          (body >>= parseResponseFrom)
##
## Anthropic Messages API reference:
##   https://docs.anthropic.com/en/api/messages

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Anthropic wire types ───────────────────────────────────────────────────────

type
  AnthropicContentBlock* = object
    ## Represents an Anthropic content block (text, tool_use, or tool_result).
    ## Use the constructor functions: textBlock(), toolUseBlock(), toolResultBlock()
    kind*:       string  ## "text", "tool_use", or "tool_result"
    text*:       string  ## for text blocks
    id*:         string  ## for tool_use blocks
    name*:       string  ## for tool_use blocks
    inputJson*:  string  ## for tool_use blocks (JSON string)
    toolUseId*:  string  ## for tool_result blocks
    content*:    string  ## for tool_result blocks

  AnthropicMessage* = object
    role*:       string
    content*:    seq[AnthropicContentBlock]

  AnthropicTool* = object
    name*:        string
    description*: string
    inputSchema*: JsonNode  ## JSON Schema object

  AnthropicUsage* = object
    inputTokens*:  int
    outputTokens*: int

  AnthropicResponse* = object
    id*:         string
    content*:    seq[AnthropicContentBlock]
    stopReason*: string
    model*:      string
    usage*:      AnthropicUsage

# ── Internal pure helpers ──────────────────────────────────────────────────────

func textBlock*(text: string): AnthropicContentBlock =
  AnthropicContentBlock(kind: "text", text: text)

func toolUseBlock*(id, name, inputJson: string): AnthropicContentBlock =
  AnthropicContentBlock(kind: "tool_use", id: id, name: name, inputJson: inputJson)

func toolResultBlock*(toolUseId, content: string): AnthropicContentBlock =
  AnthropicContentBlock(kind: "tool_result", toolUseId: toolUseId, content: content)

proc contentBlockToJson*(cb: AnthropicContentBlock): JsonNode =
  result = newJObject()
  result["type"] = % cb.kind
  if cb.kind == "text":
    result["text"] = % cb.text
  elif cb.kind == "tool_use":
    result["id"] = % cb.id
    result["name"] = % cb.name
    try:
      result["input"] = parseJson(cb.inputJson)
    except JsonParsingError:
      result["input"] = newJObject()  ## fallback
  elif cb.kind == "tool_result":
    result["tool_use_id"] = % cb.toolUseId
    result["content"] = % cb.content

func jsonToContentBlock*(node: JsonNode): AnthropicContentBlock =
  let kind = node{"type"}.getStr("")
  if kind == "text":
    textBlock node{"text"}.getStr("")
  elif kind == "tool_use":
    toolUseBlock(
      node{"id"}.getStr(""),
      node{"name"}.getStr(""),
      $node{"input"}
    )
  elif kind == "tool_result":
    toolResultBlock(
      node{"tool_use_id"}.getStr(""),
      node{"content"}.getStr("")
    )
  else:
    AnthropicContentBlock(kind: kind)

# ── Message conversion ───────────────────────────────────────────────────────────

func messageToAnthropic*(msg: ChatMessage): AnthropicMessage =
  var blocks: seq[AnthropicContentBlock] = @[]
  if msg.text.len > 0 and msg.toolCallId.len > 0:
    ## Tool result message — content is the tool output text
    blocks.add toolResultBlock(msg.toolCallId, msg.text)
  elif msg.text.len > 0:
    blocks.add textBlock(msg.text)
  if msg.toolCalls.len > 0:
    for tc in msg.toolCalls:
      blocks.add toolUseBlock(tc.id, tc.name, tc.inputJson)
  AnthropicMessage(role: msg.role, content: blocks)

proc anthropicMessageToJson*(am: AnthropicMessage): JsonNode =
  result = newJObject()
  result["role"] = % am.role
  result["content"] = newJArray()
  for cb in am.content:
    result["content"].add cb.contentBlockToJson

# ── Public pure API ─────────────────────────────────────────────────────────────

proc buildMessagesArray*(messages: seq[ChatMessage]): JsonNode =
  ## Converts internal conversation history to Anthropic content blocks.
  ##
  ## Usage:  req.messages |> buildMessagesArray
  result = newJArray()
  for msg in messages:
    let am = msg |> messageToAnthropic
    result.add am |> anthropicMessageToJson

proc buildToolsArray*(tools: seq[ToolDescription]): JsonNode =
  ## Converts internal tool descriptions to Anthropic tools array.
  ##
  ## Usage:  req.tools |> buildToolsArray
  result = newJArray()
  for td in tools:
    var toolNode = newJObject()
    toolNode["name"] = % td.name
    toolNode["description"] = % td.description
    try:
      toolNode["input_schema"] = parseJson(td.schemaJson)
    except JsonParsingError:
      toolNode["input_schema"] = newJObject()  ## fallback to empty schema
    result.add toolNode

proc buildRequestBody*(model: string; req: CompletionRequest;
                       stream = false): JsonNode =
  ## Builds the full Anthropic Messages API request body as JSON.
  ##
  ## Usage:  buildRequestBody("claude-3-5-sonnet", req)
  result = newJObject()
  result["model"] = % model
  if req.system.len > 0:
    result["system"] = % req.system
  result["messages"] = req.messages |> buildMessagesArray
  if req.maxTokens > 0:
    result["max_tokens"] = % req.maxTokens
  else:
    result["max_tokens"] = % 4096  ## Anthropic requires max_tokens
  if req.tools.len > 0:
    result["tools"] = req.tools.buildToolsArray
  result["stream"] = % stream

func parseToolCallsFromContent*(theBlocks: seq[AnthropicContentBlock]): seq[ToolCallRequest] =
  for cb in theBlocks:
    if cb.kind == "tool_use":
      result.add ToolCallRequest(
        id:        cb.id,
        name:      cb.name,
        inputJson: cb.inputJson,
      )

func parseTextFromContent*(theBlocks: seq[AnthropicContentBlock]): string =
  for cb in theBlocks:
    if cb.kind == "text":
      result = cb.text
      break

proc parseResponseFrom*(body: JsonNode): Result[CompletionResponse, string] =
  ## Parses an Anthropic Messages API response body into CompletionResponse.
  ##
  ## Usage:  responseJson >>= parseResponseFrom
  try:
    let content = body{"content"}
    if content.isNil or content.kind != JArray:
      return err("No content array in Anthropic response")
    if content.len == 0:
      return err("Empty content array in Anthropic response")

    var blocks: seq[AnthropicContentBlock] = @[]
    for node in content:
      blocks.add node.jsonToContentBlock

    let text = blocks.parseTextFromContent
    let toolCalls = blocks.parseToolCallsFromContent

    let usage = body{"usage"}
    let inputTokens = usage{"input_tokens"}.getInt(0)
    let outputTokens = usage{"output_tokens"}.getInt(0)

    ok CompletionResponse(
      text:         text,
      inputTokens:  inputTokens,
      outputTokens: outputTokens,
      toolCalls:   toolCalls,
    )
  except JsonKindError, KeyError, ValueError:
    err "Failed to parse Anthropic response: " & getCurrentExceptionMsg()

func toolResultToAnthropicBlock*(toolUseId, output: string): JsonNode =
  ## Formats a tool result as an Anthropic tool_result content block.
  ##
  ## Usage:  toolResult |> toolResultToAnthropicBlock
  result = newJObject()
  result["type"] = %"tool_result"
  result["tool_use_id"] = % toolUseId
  result["content"] = % output
