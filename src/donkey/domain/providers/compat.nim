## compat.nim — the OpenAI-shaped transport profile.
##
## One request builder for every provider that speaks chat/completions. The
## profile is data: endpoint, extra headers, top-level payload extras, image
## support and the SSE dialect. Provider code stays a constructor, not a copy
## of the serializer.
##
## Pure: no I/O, no network.

import std/json
import ../message
import ./openai_pure

type
  CompatProfile* = object
    id*:             string
    endpoint*:       string
    extraHeaders*:   seq[(string, string)]
    payloadExtras*:  JsonNode   ## merged at the top level; nil = none
    reasoningExtras*: JsonNode  ## merged only when req.reasoning
    reasoningOffExtras*: JsonNode ## merged only when not req.reasoning
    streamExtras*:   JsonNode   ## merged only when stream = true
    supportsImages*: bool
    quirks*:         OpenAiWireQuirks
    apiKeyHeader*:   string     ## "" = Authorization: Bearer <key>; otherwise
                                ## the key goes in this header alone (Azure's
                                ## `api-key`), with no bearer beside it

func defaultOpenAiProfile*(
    endpoint = "https://api.openai.com/v1/chat/completions";
    id = "openai"): CompatProfile =
  CompatProfile(
    id: id,
    endpoint: endpoint,
    supportsImages: true,
    quirks: defaultOpenAiQuirks(),
  )

func suppressImages(req: CompletionRequest): CompletionRequest =
  ## A copy of the request with every image removed. The text is untouched.
  result = req
  result.messages = @[]
  for message in req.messages:
    var copy = message
    copy.imageUrl = ""
    result.messages.add(copy)

proc mergeInto(base: var JsonNode; extras: JsonNode) =
  if not extras.isNil and extras.kind == JObject:
    for key, value in extras:
      base[key] = value

proc buildCompatRequestBody*(profile: CompatProfile; model: string;
                             req: CompletionRequest;
                             stream = false): JsonNode =
  ## OpenAI-compatible request body. `payloadExtras` is merged last, so a
  ## profile can add (or override) fields such as `thinking` or
  ## `reasoning_split` without reimplementing the message shape.
  let effective =
    if profile.supportsImages: req
    else: suppressImages(req)
  result = buildRequestBodyWithQuirks(model, effective, stream, profile.quirks)
  mergeInto(result, profile.payloadExtras)
  if req.reasoning:
    mergeInto(result, profile.reasoningExtras)
  else:
    mergeInto(result, profile.reasoningOffExtras)
  if stream:
    mergeInto(result, profile.streamExtras)
  if profile.quirks.shortToolIds:
    ## On the wire copy only: the stored history keeps the original ids.
    let messages = result.getOrDefault("messages")
    if not messages.isNil and messages.kind == JArray:
      for message in messages:
        let calls = message.getOrDefault("tool_calls")
        if not calls.isNil and calls.kind == JArray:
          for call in calls:
            call["id"] = %mistralToolId(call{"id"}.getStr(""))
        if message.hasKey("tool_call_id"):
          message["tool_call_id"] = %mistralToolId(message["tool_call_id"].getStr(""))
