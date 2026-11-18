## Image fallback: degrade to text when the provider rejects the inline image
## (Ferramentas US-003).
##
## The builder is a local fake: an inline `data:` image is rejected, plain text
## succeeds. No network, no real provider.

import std/[strutils, unittest]
import chronos
import donkey/app/session_bootstrap
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/provider

const
  DataPng = "data:image/png;base64,QUJD"
  DataJpeg = "data:image/jpeg;base64,QQ=="
  Note = "[imagem removida: provider sem visão]"

var gCalls: seq[CompletionRequest]

func hasDataImage(req: CompletionRequest): bool =
  for msg in req.messages:
    if msg.imageUrl.startsWith("data:"):
      return true

proc imageRejectingBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  ## Behaves like a text-only model: any inline image is rejected, text works.
  let fn: CompleteFn = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      gCalls.add(req)
    if hasDataImage(req):
      return err("400 invalid image_url: unsupported image content")
    ok(CompletionResponse(text: "texto ok"))
  ProviderBundle(completeFn: fn)

proc alwaysImageRejectingBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  let fn: CompleteFn = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      gCalls.add(req)
    err("400 invalid content: media type not supported")
  ProviderBundle(completeFn: fn)

proc rateLimitBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  let fn: CompleteFn = proc (req: CompletionRequest):
      Result[CompletionResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}:
      gCalls.add(req)
    err("429 rate limit exceeded")
  ProviderBundle(completeFn: fn)

proc imageRequest(): CompletionRequest =
  var h = newHistory()
  h.addUserWithImage("veja a foto", DataPng)
  CompletionRequest(messages: h)

suite "image rejection detection":

  test "the markers live in one function":
    check isImageRejection("400 invalid image_url")
    check isImageRejection("unsupported image content")
    check isImageRejection("invalid content: media type")
    check isImageRejection("Unsupported Image")
    check not isImageRejection("429 rate limit exceeded")
    check not isImageRejection("401 Unauthorized")

  test "attachment and file_id errors are image rejections too":
    # The refusal text and the one-shot retry must agree on this list; before,
    # `genericProviderErrorText` matched these two outside the pure predicate,
    # so an "attachment" error explained the refusal but never retried.
    check isImageRejection("400 attachment type unsupported")
    check isImageRejection("invalid file_id")
    for marker in @ImageRejectionMarkers & @["attachment", "file_id"]:
      check isImageRejection("400 " & marker & " rejected")

suite "withoutInlineImages":

  test "strips data URLs, keeps text and notes the last user turn with text":
    var h = newHistory()
    h.addUserWithImage("veja", DataPng)
    h.addAssistant("claro")
    h.addUserWithImage("", DataJpeg)
    let stripped = withoutInlineImages(CompletionRequest(messages: h))
    check stripped.messages.len == 2
    check stripped.messages[0].text.contains("veja")
    check stripped.messages[0].text.contains(Note)
    check stripped.messages[0].imageUrl == ""
    check stripped.messages[1].text == "claro"

  test "keeps http images untouched":
    var h = newHistory()
    h.addUserWithImage("veja", "https://example.test/foto.png")
    h.addUserWithImage("e esta", DataPng)
    let stripped = withoutInlineImages(CompletionRequest(messages: h))
    check stripped.messages.len == 2
    check stripped.messages[0].imageUrl == "https://example.test/foto.png"
    check stripped.messages[0].text == "veja"
    check stripped.messages[1].imageUrl == ""
    check stripped.messages[1].text.contains(Note)

  test "a request without inline images is left alone":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleUser, text: "oi",
                  imageUrl: "https://example.test/foto.png")])
    let stripped = withoutInlineImages(req)
    check stripped.messages.len == 1
    check stripped.messages[0].text == "oi"
    check stripped.messages[0].imageUrl == "https://example.test/foto.png"

suite "image rejection fallback":

  test "a rejected inline image retries once without the data URL":
    gCalls = @[]
    let fn = buildCompleteFn("provider = \"openai\"", imageRejectingBuilderImpl)
    let res = fn(imageRequest())
    check res.isOk
    check gCalls.len == 2
    check gCalls[0].messages.len == 1
    check gCalls[0].messages[0].imageUrl == DataPng
    check gCalls[1].messages.len == 1
    check gCalls[1].messages[0].imageUrl == ""
    check gCalls[1].messages[0].text.contains("veja a foto")
    check gCalls[1].messages[0].text.contains(Note)

  test "an album of images only leaves no empty turn":
    gCalls = @[]
    var h = newHistory()
    h.addUserWithImage("", DataPng)
    h.addUserWithImage("", DataJpeg)
    let fn = buildCompleteFn("provider = \"openai\"", imageRejectingBuilderImpl)
    let res = fn(CompletionRequest(messages: h))
    check res.isOk
    check gCalls.len == 2
    for msg in gCalls[1].messages:
      check not (msg.text.len == 0 and msg.imageUrl.len == 0)
    check gCalls[1].messages.len == 1
    check gCalls[1].messages[0].text == Note

  test "a non-image error does not retry":
    gCalls = @[]
    let fn = buildCompleteFn("provider = \"openai\"", rateLimitBuilderImpl)
    let res = fn(imageRequest())
    check res.isErr
    check gCalls.len == 1

  test "a request without inline images does not retry":
    gCalls = @[]
    let fn = buildCompleteFn("provider = \"openai\"",
                             alwaysImageRejectingBuilderImpl)
    let res = fn(CompletionRequest(messages: @[
      ChatMessage(role: roleUser, text: "oi")]))
    check res.isErr
    check gCalls.len == 1

  test "the async path retries once without the data URL":
    gCalls = @[]
    let fn = buildAsyncCompleteFn("provider = \"openai\"",
                                  imageRejectingBuilderImpl)
    let res = waitFor fn(imageRequest())
    check res.isOk
    check gCalls.len == 2
    check gCalls[1].messages.len == 1
    check gCalls[1].messages[0].imageUrl == ""
    check gCalls[1].messages[0].text.contains(Note)
