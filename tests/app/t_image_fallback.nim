## Image fallback: degrade to text when the provider rejects the inline image
## (Ferramentas US-003).
##
## The builder is a local fake: an inline `data:` image is rejected, plain text
## succeeds. No network, no real provider.

import std/[strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/provider_executor
import donkey/app/session_bootstrap
import donkey/app/session_state
import donkey/app/tool_loop_runtime
import donkey/core/log
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/memory
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

  test "the builder surfaces the rejection; the turn loop owns the retry":
    ## The retry moved to `runToolLoop` so it happens once per turn, not once
    ## per provider call (see the "turn-scoped image retry" suite below).
    gCalls = @[]
    let fn = buildCompleteFn("provider = \"openai\"", imageRejectingBuilderImpl)
    let res = fn(imageRequest())
    check res.isErr
    check isImageRejection(res.error)
    check gCalls.len == 1
    check gCalls[0].messages[0].imageUrl == DataPng

  test "an album of images only is not retried inside the builder":
    gCalls = @[]
    var h = newHistory()
    h.addUserWithImage("", DataPng)
    h.addUserWithImage("", DataJpeg)
    let fn = buildCompleteFn("provider = \"openai\"", imageRejectingBuilderImpl)
    let res = fn(CompletionRequest(messages: h))
    check res.isErr
    check gCalls.len == 1

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

  test "the async builder also leaves the retry to the turn loop":
    gCalls = @[]
    let fn = buildAsyncCompleteFn("provider = \"openai\"",
                                  imageRejectingBuilderImpl)
    let res = waitFor fn(imageRequest())
    check res.isErr
    check isImageRejection(res.error)
    check gCalls.len == 1

# ── Turn-scoped retry across tool rounds ──────────────────────────────────────
#
# The retry belongs to the turn, not to one completion call: a turn with N tool
# rounds must spend at most one extra provider call on the image, and the note
# must be written once. These fakes reject `data:` images and then answer with
# tool calls until the scripted rounds are over.

var
  gTurnCalls:     seq[CompletionRequest]
  gTurnToolsLeft: int
  gTurnNextCall:  int

proc resetTurn(toolCalls: int) =
  gTurnCalls = @[]
  gTurnToolsLeft = toolCalls
  gTurnNextCall = 0

proc imageRejectingTurnComplete(req: CompletionRequest):
    Result[CompletionResponse, string] {.gcsafe.} =
  {.cast(gcsafe).}:
    gTurnCalls.add(req)
    if hasDataImage(req):
      return err("400 invalid image_url: unsupported image content")
    if gTurnToolsLeft > 0:
      dec gTurnToolsLeft
      inc gTurnNextCall
      return ok(CompletionResponse(
        text: "",
        toolCalls: @[ToolCallRequest(
          id: "call_" & $gTurnNextCall,
          name: "current_time",
          inputJson: "{\"n\":" & $gTurnNextCall & "}",
        )],
      ))
    return ok(CompletionResponse(text: "resposta só texto"))

proc imageRejectingTurnAsync(req: CompletionRequest):
    Future[Result[CompletionResponse, string]] {.async, gcsafe.} =
  result = imageRejectingTurnComplete(req)

proc countNotes(reqs: seq[CompletionRequest]): int =
  for req in reqs:
    for msg in req.messages:
      result += msg.text.count(InlineImageRemovedNote)

proc runImageTurn(completeFn: CompleteFn;
                  asyncCompleteFn: AsyncCompleteFn = nil):
                  Future[ToolLoopRunResult] {.async.} =
  let outbox = newAsyncQueue[OutboundMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let toolOut = newAsyncQueue[AgentMessage]()
  let logger = newLogger("test.image.turn", lvlError)
  var ctx = NativeCtx(
    uid: UserId("u-turn"),
    channel: ckTelegram,
    outbox: outbox,
    completeFn: completeFn,
    log: logger,
  )
  var history = newHistory()
  history.addUserWithImage("veja a foto", DataPng)
  result = await runToolLoop(
    outbox, toolInbox, toolOut, MemoryRuntimePort(), completeFn, nil, nil,
    ctx, newSessionState(), history, UserId("u-turn"), ckTelegram, "",
    "msg-turn", "stream-turn", "system", "", @[], "openai", true, false, false,
    logger, asyncCompleteFn)

suite "turn-scoped image retry":

  test "sync: three tool rounds cost one retry, not one per round":
    resetTurn(toolCalls = 3)
    let loop = waitFor runImageTurn(imageRejectingTurnComplete)

    check loop.done
    check loop.imageRetryUsed
    check loop.finalText == "resposta só texto"
    # 3 tool calls + the final answer + the single image retry.
    check gTurnCalls.len == 5
    check hasDataImage(gTurnCalls[0])
    for i in 1 ..< gTurnCalls.len:
      check not hasDataImage(gTurnCalls[i])
    check countNotes(gTurnCalls) == 1

  test "async: three tool rounds cost one retry, not one per round":
    resetTurn(toolCalls = 3)
    let loop = waitFor runImageTurn(nil, imageRejectingTurnAsync)

    check loop.done
    check loop.imageRetryUsed
    check loop.finalText == "resposta só texto"
    check gTurnCalls.len == 5
    check hasDataImage(gTurnCalls[0])
    for i in 1 ..< gTurnCalls.len:
      check not hasDataImage(gTurnCalls[i])
    check countNotes(gTurnCalls) == 1
