## bedrock_pure.nim — AWS Bedrock Converse: request body, response, endpoint.
##
## Pure translation between Donkey's `CompletionRequest`/`CompletionResponse`
## and the Converse API. Converse is stricter than the OpenAI dialect:
##   - roles alternate and the conversation starts with a user turn;
##   - a tool result rides in a user message (`toolResult` block), and the
##     results of one round share that message with the next user text;
##   - an empty text block is rejected;
##   - a `toolUse`/`toolResult` block requires `toolConfig`, so a request
##     without tools renders the history's tool blocks as text;
##   - a tool id must match [a-zA-Z0-9_-]{1,64};
##   - an image is bytes with a format (no URL source).
## No I/O; signing and HTTP live in `adapters/provider/bedrock.nim`.

import std/[json, strutils]
import ../../core/pipeops
import ../message

const
  BedrockDefaultRegion* = "us-east-1"
  EmptyToolOutput = "(sem saída)"

func bedrockToolId*(id: string): string =
  ## A valid Converse tool id; the same input always gives the same output, so
  ## a call and its result stay paired.
  for c in id:
    if result.len == 64: break
    result.add(if c in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-'}: c else: '_')
  if result.len == 0:
    result = "tool"

func imageBlock(url: string): JsonNode =
  ## `data:image/<fmt>;base64,<bytes>` → Converse image block; nil otherwise.
  if not url.startsWith("data:image/"): return nil
  let semi = url.find(';')
  let comma = url.find(',')
  if semi < 0 or comma < 0 or comma < semi: return nil
  var format = url["data:image/".len ..< semi].toLowerAscii
  if format == "jpg": format = "jpeg"
  if format notin ["png", "jpeg", "gif", "webp"]: return nil
  %* {"image": {"format": format, "source": {"bytes": url[comma + 1 .. ^1]}}}

proc toolInput(inputJson: string): JsonNode =
  try:
    let parsed = parseJson(if inputJson.strip.len == 0: "{}" else: inputJson)
    if parsed.kind == JObject: parsed else: %* {"value": parsed}
  except CatchableError:
    %* {"raw": inputJson}

proc blocksOf(msg: ChatMessage; withTools: bool): seq[JsonNode] =
  if msg.role == roleTool:
    let output = if msg.text.len > 0: msg.text else: EmptyToolOutput
    if withTools:
      return @[%* {"toolResult": {"toolUseId": bedrockToolId(msg.toolCallId),
                                  "content": [{"text": output}]}}]
    return @[%* {"text": "[resultado da ferramenta]\n" & output}]
  if msg.text.len > 0:
    result.add(%* {"text": msg.text})
  if msg.role == roleUser and msg.imageUrl.len > 0:
    let image = imageBlock(msg.imageUrl)
    if not image.isNil:
      result.add(image)
  for call in msg.toolCalls:
    if withTools:
      result.add(%* {"toolUse": {"toolUseId": bedrockToolId(call.id),
                                 "name": call.name,
                                 "input": toolInput(call.inputJson)}})
    else:
      result.add(%* {"text": "[chamada de ferramenta " & call.name & "] " &
                            call.inputJson})

func converseRole(msg: ChatMessage): string =
  if msg.role == roleAssistant: "assistant" else: "user"

proc converseBody*(req: CompletionRequest): JsonNode =
  ## (A proc only because `parseJson` is not a `func`; no I/O.)
  result = newJObject()
  if req.system.len > 0:
    result["system"] = %* [{"text": req.system}]
  let withTools = req.tools.len > 0
  var messages = newJArray()
  for msg in req.messages:
    let blocks = blocksOf(msg, withTools)
    if blocks.len == 0:
      continue
    let role = converseRole(msg)
    if messages.len == 0 and role != "user":
      ## Converse starts with a user turn.
      messages.add(%* {"role": "user", "content": [{"text": "(continuação)"}]})
    if messages.len > 0 and messages[messages.len - 1]["role"].getStr == role:
      for b in blocks:
        messages[messages.len - 1]["content"].add(b)
    else:
      var content = newJArray()
      for b in blocks: content.add(b)
      messages.add(%* {"role": role, "content": content})
  result["messages"] = messages
  if req.maxTokens > 0:
    result["inferenceConfig"] = %* {"maxTokens": req.maxTokens}
  if withTools:
    var tools = newJArray()
    for tool in req.tools:
      let schema = toolInput(tool.schemaJson)
      tools.add(%* {"toolSpec": {"name": tool.name,
                                 "description": (if tool.description.len > 0:
                                                   tool.description else: tool.name),
                                 "inputSchema": {"json": schema}}})
    result["toolConfig"] = %* {"tools": tools}

func parseConverseResponse*(body: JsonNode): Result[CompletionResponse, string] =
  let content = body{"output"}{"message"}{"content"}
  if content.isNil or content.kind != JArray:
    let detail = body{"message"}.getStr(body{"Message"}.getStr(""))
    return err("Bedrock: " & (if detail.len > 0: detail else: "missing output.message"))
  var resp = CompletionResponse()
  for item in content:
    if item.hasKey("text"):
      resp.text.add(item["text"].getStr)
    elif item.hasKey("toolUse"):
      let use = item["toolUse"]
      resp.toolCalls.add(ToolCallRequest(
        id: use{"toolUseId"}.getStr(""),
        name: use{"name"}.getStr(""),
        inputJson: $(if use.hasKey("input"): use["input"] else: newJObject())))
    elif item.hasKey("reasoningContent"):
      resp.reasoning.add(item["reasoningContent"]{"reasoningText"}{"text"}.getStr(""))
  resp.inputTokens = body{"usage"}{"inputTokens"}.getInt(0)
  resp.outputTokens = body{"usage"}{"outputTokens"}.getInt(0)
  ok(resp)

func bedrockRuntimeUrl*(region: string): string =
  "https://bedrock-runtime." &
    (if region.len > 0: region else: BedrockDefaultRegion) & ".amazonaws.com"

func regionOfRuntimeUrl*(url: string): string =
  ## The region of a `bedrock-runtime.<region>.amazonaws.com` URL; the
  ## default region for anything else (a proxy, a test server).
  const marker = "bedrock-runtime."
  let at = url.find(marker)
  if at < 0: return BedrockDefaultRegion
  let rest = url[at + marker.len .. ^1]
  let dot = rest.find('.')
  if dot <= 0: BedrockDefaultRegion else: rest[0 ..< dot]

func converseUrl*(baseUrl, modelId: string): string =
  ## The model id is one path segment, so its ':' (and anything else outside
  ## the unreserved set) is percent-encoded.
  var encoded = ""
  for c in modelId:
    if c in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_', '.', '~'}:
      encoded.add(c)
    else:
      encoded.add('%' & toHex(ord(c), 2))
  baseUrl.strip(leading = false, chars = {'/'}) & "/model/" & encoded & "/converse"
