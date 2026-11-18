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
  CompatSseKind* = enum
    cssOpenAi       ## plain OpenAI `data:` chunks ending in `[DONE]`
    cssOpenRouter   ## OpenAI chunks with OpenRouter reasoning/tool deltas

  CompatProfile* = object
    id*:             string
    endpoint*:       string
    extraHeaders*:   seq[(string, string)]
    payloadExtras*:  JsonNode   ## merged at the top level; nil = none
    supportsImages*: bool
    sseKind*:        CompatSseKind

func defaultOpenAiProfile*(
    endpoint = "https://api.openai.com/v1/chat/completions";
    id = "openai"): CompatProfile =
  CompatProfile(
    id: id,
    endpoint: endpoint,
    supportsImages: true,
    sseKind: cssOpenAi,
  )

func suppressImages(req: CompletionRequest): CompletionRequest =
  ## A copy of the request with every image removed. The text is untouched.
  result = req
  result.messages = @[]
  for message in req.messages:
    var copy = message
    copy.imageUrl = ""
    result.messages.add(copy)

proc buildCompatRequestBody*(profile: CompatProfile; model: string;
                             req: CompletionRequest;
                             stream = false): JsonNode =
  ## OpenAI-compatible request body. `payloadExtras` is merged last, so a
  ## profile can add (or override) fields such as `thinking` or
  ## `reasoning_split` without reimplementing the message shape.
  let effective =
    if profile.supportsImages: req
    else: suppressImages(req)
  result = buildRequestBody(model, effective, stream)
  if not profile.payloadExtras.isNil and
     profile.payloadExtras.kind == JObject:
    for key, value in profile.payloadExtras:
      result[key] = value
