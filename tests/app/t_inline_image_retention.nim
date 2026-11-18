## Ferramentas US-004 — retention, wired through the orchestrator.
##
## Two real turns through `runOrchestrator` with a recording `completeFn`:
## the photo is inline in the first request and gone from the second, while
## the text marker survives. Deleting the `demoteInlineImages` call in
## `orchestrator.nim` makes this test fail; calling the function by hand in
## the test would not count.

import std/[json, os, strutils, unittest]
import chronos
import results
import donkey/adapters/filesystem/attachment_store
import donkey/adapters/http/std_http
import donkey/adapters/memory/md_file
import donkey/app/inbound_media
import donkey/app/orchestrator
import donkey/app/prompt_building
import donkey/app/session_manager
import donkey/app/session_state
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/channel

const TestRoot = "/tmp/donkey_inline_image_retention_tests"

var gRequests: seq[CompletionRequest]

proc recordingComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  {.cast(gcsafe).}:
    gRequests.add(req)
  ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))

proc bytesOf(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ch)

proc downloadOf(name, mime: string; data: seq[byte]): FileDownload =
  FileDownload(
    fileName: name,
    fileSize: data.len.int64,
    mimeType: mime,
    data: data,
  )

proc hasDataImage(req: CompletionRequest): bool =
  for msg in req.messages:
    if msg.imageUrl.startsWith("data:"):
      return true

proc requestContaining(requests: seq[CompletionRequest]; needle: string): int =
  ## Index of the first request whose user turn carries `needle`, or -1.
  for i, req in requests:
    for msg in req.messages:
      if msg.role == roleUser and msg.text.contains(needle):
        return i
  -1

proc makeSessionEntry(): SessionEntry =
  SessionEntry(
    inbox: newAsyncQueue[AgentMessage](),
    askInbox: newAsyncQueue[string](),
    awaitingAsk: false,
    channels: @[],
    toolCatalogSignature: "",
  )

proc firstTurnPayload(paddockDir: string): string =
  ## Goes through the real inbound path so the marker and the data URL are
  ## exactly what the channel would produce.
  var inbound = InboundMessage(text: "veja a foto")
  let saved = applyInboundAttachment(
    inbound, downloadOf("file_1.png", "image/png", bytesOf("png")),
    paddockDir, newAttachmentStore(), "photo.png", "image/png")
  doAssert saved.isOk, saved.error
  doAssert inbound.mediaUrl.startsWith("data:image/png;base64,")
  $(%*{
    "text": inbound.text,
    "mediaUrl": inbound.mediaUrl,
    "mediaUrls": [inbound.mediaUrl],
    "recentContext": "",
  })

suite "inline image retention":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)
    gRequests = @[]

  teardown:
    removeDir(TestRoot)

  test "the second turn does not resend the inline photo":
    proc doTest(dir: string): Future[seq[CompletionRequest]] {.async.} =
      let userDir = dir / "u-ret"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      let payload = firstTurnPayload(userDir)
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(
        inbox, addr session, outbox, mem.toRuntimePort(), recordingComplete,
        newStdHttpAdapter().toRuntimePort(), nil, @[], @[], userDir, state)
      await inbox.put(newTaskMsg("req-inline-1", tkUserMsg, "u-ret", payload))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-inline-2", tkUserMsg, "u-ret", "segunda mensagem"))
      discard await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      var recorded: seq[CompletionRequest]
      {.cast(gcsafe).}:
        recorded = gRequests
      return recorded

    let requests = waitFor doTest(TestRoot)
    check requests.len >= 2

    ## The first request carried the photo inline.
    let firstIdx = requestContaining(requests, "veja a foto")
    check firstIdx >= 0
    check hasDataImage(requests[firstIdx])

    ## The second turn sees the marker but no `data:` image.
    let secondIdx = requestContaining(requests, "segunda mensagem")
    check secondIdx >= 0
    check not hasDataImage(requests[secondIdx])
    var markerSurvived = false
    for msg in requests[secondIdx].messages:
      if msg.role == roleUser and msg.text.contains("attachments/photo.png") and
         msg.text.contains("inspect_image"):
        markerSurvived = true
    check markerSurvived
