## Ferramentas US-004 — the inbound photo joins the first turn as an inline
## image, and the marker tells the model whether it still needs the disk.
##
## Pure/app-level: no network, no provider, a 3-byte "png" fixture only.

import std/[base64, os, strutils, unittest]
import results
import donkey/app/inbound_media
import donkey/app/prompt_building
import donkey/app/session_bootstrap
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

proc countSub(text, sub: string): int =
  var i = 0
  while true:
    let p = text.find(sub, i)
    if p < 0: break
    inc result
    i = p + sub.len

proc textOf(history: ConversationHistory): string =
  for msg in history:
    result.add(msg.text)
    result.add("\n")

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
    ## Saving no longer claims the image travels inline: that is decided when
    ## the turn is assembled and knows the final inline cap.
    check "inspect_image" in msg.text
    check "attachments/photo.png" in msg.text
    check "já acompanha" notin msg.text
    check fileExists(TestRoot / "attachments" / "photo.png")

  test "an unsupported image mime is not inlined and never suggests inspect_image":
    var msg = InboundMessage(mediaUrl: "telegram-file-id")
    let res = applyInboundAttachment(
      msg, downloadOf("file.svg", "image/svg+xml", bytesOf("<svg/>")),
      TestRoot, newAttachmentStore(), "drawing.svg", "image/svg+xml")
    check res.isOk
    check res.get().isImage
    check msg.mediaUrl == ""
    check "attachments/drawing.svg" in msg.text
    check "6 bytes" in msg.text
    check "inspect_image" notin msg.text
    check "fs_read" in msg.text
    check "text_read" in msg.text
    check "já acompanha" notin msg.text

  test "heic is saved as a path but not advertised to inspect_image":
    var msg = InboundMessage(mediaUrl: "telegram-file-id")
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.heic", "image/heic", bytesOf("heic")),
      TestRoot, newAttachmentStore(), "photo.heic", "image/heic")
    check res.isOk
    check res.get().isImage
    check msg.mediaUrl == ""
    check "attachments/photo.heic" in msg.text
    check "4 bytes" in msg.text
    check "inspect_image" notin msg.text
    check "fs_read" in msg.text
    check "text_read" in msg.text
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

  test "six inline images: only four travel inline and two remain paths":
    var urls, paths: seq[string] = @[]
    for i in 0 ..< 6:
      urls.add(imageDataUrl("image/png", bytesOf("png" & $i)).get())
      paths.add("attachments/photo" & $i & ".png")
    let history = addUserTurnWithImages(newHistory(), "veja", urls, paths)
    var inline = 0
    for msg in history:
      if msg.imageUrl.startsWith("data:"):
        inc inline
      check not msg.imageUrl.startsWith("attachments/")
    check inline == 4
    check history.len == 4
    let allText = textOf(history)
    for i in 4 ..< 6:
      check allText.contains("inspect_image")
      check allText.contains(paths[i])
    ## Exactly the four inline images may claim to accompany the turn.
    check countSub(allText, "já acompanha esta mensagem") == 4

  test "an eleventh image keeps its path marker even though it is not sent":
    var urls, paths: seq[string] = @[]
    for i in 0 ..< 11:
      urls.add(imageDataUrl("image/png", bytesOf("png" & $i)).get())
      paths.add("attachments/eleven" & $i & ".png")
    let history = addUserTurnWithImages(newHistory(), "veja", urls, paths)
    let allText = textOf(history)
    ## Ten are sent (four inline, six as paths); the eleventh is not sent but
    ## must not vanish: its marker points at the file.
    for i in 0 ..< 11:
      check allText.contains(paths[i])
    check countSub(allText, "já acompanha esta mensagem") == 4
    check allText.contains("inspect_image")

  test "album of four inline plus twenty paths keeps four inline and six paths":
    var urls, paths: seq[string] = @[]
    for i in 0 ..< 4:
      urls.add(imageDataUrl("image/png", bytesOf("png" & $i)).get())
      paths.add("attachments/inline" & $i & ".png")
    for i in 0 ..< 20:
      let path = "attachments/photo" & $(i + 4) & ".png"
      urls.add(path)
      paths.add(path)
    let history = addUserTurnWithImages(newHistory(), "veja", urls, paths)
    var inline = 0
    var pathEntries = 0
    for msg in history:
      if msg.imageUrl.startsWith("data:"):
        inc inline
      elif msg.imageUrl.startsWith("attachments/"):
        inc pathEntries
    check inline == 4
    check pathEntries == 6
    check inline + pathEntries == 10
    check countSub(textOf(history), "já acompanha esta mensagem") == 4

  test "a single image keeps the inline marker at turn assembly":
    var inbound = InboundMessage(text: "veja")
    let saved = applyInboundAttachment(
      inbound, downloadOf("file_1.png", "image/png", bytesOf("png")),
      TestRoot, newAttachmentStore(), "photo.png", "image/png")
    check saved.isOk
    check "já acompanha" notin inbound.text
    let payload = encodeSessionPayload(inbound)
    let decoded = decodeUserPayload(payload)
    check decoded.mediaPaths == @["attachments/photo.png"]
    let history = addUserTurnWithImages(
      newHistory(), decoded.text, @[decoded.mediaUrl], decoded.mediaPaths)
    check history.len == 1
    check history[0].imageUrl.startsWith("data:image/png;base64,")
    check "já acompanha esta mensagem" in history[0].text
    check "inspect_image" in history[0].text
    check "attachments/photo.png" in history[0].text
    check countSub(history[0].text, "já acompanha esta mensagem") == 1

  test "a non-image attachment keeps the fs_read marker":
    var inbound = InboundMessage(text: "leia")
    let saved = applyInboundAttachment(
      inbound, downloadOf("file_1.md", "text/markdown", bytesOf("# x\n")),
      TestRoot, newAttachmentStore(), "notes.md", "text/markdown")
    check saved.isOk
    check "attachments/notes.md" in inbound.text
    check "fs_read" in inbound.text
    check "text_read" in inbound.text
    let payload = encodeSessionPayload(inbound)
    let decoded = decodeUserPayload(payload)
    check decoded.mediaPaths.len == 0
    let history = addUserTurnWithImages(newHistory(), decoded.text, @[], @[])
    check history.len == 1
    check "fs_read" in history[0].text
    check "attachments/notes.md" in history[0].text

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
