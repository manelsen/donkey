## Ferramentas US-004 — the inbound photo joins the first turn as an inline
## image, and the marker tells the model whether it still needs the disk.
##
## Pure/app-level: no network, no provider, a 3-byte "png" fixture only.

import std/[base64, os, strutils, unittest]
import results
import donkey/app/inbound_media
import donkey/app/prompt_building
import donkey/adapters/filesystem/attachment_store
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/channel

const TestRoot = "/tmp/donkey_inline_image_turn_tests"

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

suite "inline image turn":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "a supported png becomes a data URL that decodes back":
    var msg = InboundMessage(text: "veja", mediaUrl: "telegram-file-id")
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.png", "image/png", bytesOf("png")),
      TestRoot, newAttachmentStore(), "photo.png", "image/png")
    check res.isOk
    check res.get().isImage
    check msg.mediaUrl == "data:image/png;base64," & encode("png")
    let decoded = parseDataUrl(msg.mediaUrl)
    check decoded.isOk
    check decoded.get().mimeType == "image/png"
    check decode(decoded.get().data) == "png"
    ## The channel file_id must never leak into the provider-visible text.
    check "file_id" notin msg.text
    check "telegram-file-id" notin msg.text
    ## The marker still points at the disk copy for recorte/zoom.
    check "inspect_image" in msg.text
    check "attachments/photo.png" in msg.text
    check "já acompanha" in msg.text
    check fileExists(TestRoot / "attachments" / "photo.png")

  test "an unsupported mime is not inlined and keeps the disk marker":
    var msg = InboundMessage(mediaUrl: "telegram-file-id")
    let res = applyInboundAttachment(
      msg, downloadOf("file.svg", "image/svg+xml", bytesOf("<svg/>")),
      TestRoot, newAttachmentStore(), "drawing.svg", "image/svg+xml")
    check res.isOk
    check res.get().isImage
    check msg.mediaUrl == ""
    check "attachments/drawing.svg" in msg.text
    check "inspect_image" in msg.text
    check "já acompanha" notin msg.text

  test "an image above the encoded limit is not inlined":
    ## 4 MiB of raw bytes encode to ~5.6 MB, above MaxInlineImageEncodedBytes.
    let data = newSeq[byte](4 * 1024 * 1024)
    check imageDataUrl("image/png", data).isErr
    var msg = InboundMessage()
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.png", "image/png", data),
      TestRoot, newAttachmentStore(), "big.png", "image/png")
    check res.isOk
    check res.get().isImage
    check msg.mediaUrl == ""
    check "attachments/big.png" in msg.text
    check "inspect_image" in msg.text

  test "six data URLs become four history entries":
    var urls: seq[string] = @[]
    for i in 0 ..< 6:
      urls.add(imageDataUrl("image/png", bytesOf("png" & $i)).get())
    let history = addUserTurnWithImages(newHistory(), "veja", urls)
    check history.len == 4
    check history[0].text == "veja"
    var inline = 0
    for msg in history:
      if msg.imageUrl.startsWith("data:"):
        inc inline
    check inline == 4

  test "the existing ten-attachment cap still holds for paths":
    var urls: seq[string] = @[]
    for i in 0 ..< 25:
      urls.add("img" & $i & ".jpg")
    let history = addUserTurnWithImages(newHistory(), "veja", urls)
    check history.len == 10
    check history[0].imageUrl == "img0.jpg"

  test "demoteInlineImages clears data URLs only":
    var history = newHistory()
    history.addUserWithImage("inline", "data:image/png;base64,cG5n")
    history.addUserWithImage("http", "https://example.test/a.png")
    history.addUserWithImage("path", "attachments/a.png")
    let demoted = demoteInlineImages(history)
    check demoted.len == 3
    check demoted[0].imageUrl == ""
    check demoted[0].text == "inline"
    check demoted[1].imageUrl == "https://example.test/a.png"
    check demoted[2].imageUrl == "attachments/a.png"
    ## The source history is not mutated through seq aliasing.
    check history[0].imageUrl == "data:image/png;base64,cG5n"
