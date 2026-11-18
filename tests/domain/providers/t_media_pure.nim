## Tests for domain/providers/media_pure — inline image data URLs.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/media_pure

suite "parseDataUrl":

  test "accepts a png data URL":
    let res = parseDataUrl("data:image/png;base64,QUJD")
    check res.isOk
    check res.get().mimeType == "image/png"
    check res.get().data == "QUJD"

  test "lowercases the media type":
    let res = parseDataUrl("data:IMAGE/PNG;base64,QUJD")
    check res.isOk
    check res.get().mimeType == "image/png"

  test "accepts base64 padding":
    check parseDataUrl("data:image/jpeg;base64,QUJD=").isOk

  test "rejects a plain URL":
    let res = parseDataUrl("https://example.test/a.png")
    check res.isErr
    check res.error.contains("data URL")

  test "rejects a data URL without the base64 marker":
    check parseDataUrl("data:image/png,QUJD").isErr

  test "rejects an empty payload":
    check parseDataUrl("data:image/png;base64,").isErr

  test "rejects a non-image type":
    check parseDataUrl("data:text/plain;base64,QUJD").isErr

  test "rejects an unsupported image type":
    check parseDataUrl("data:image/svg+xml;base64,PHN2Zz4=").isErr

  test "rejects characters outside base64":
    check parseDataUrl("data:image/png;base64,@@@").isErr

  test "recognises http and https URLs":
    check isHttpUrl("http://example.test/a.png")
    check isHttpUrl("https://example.test/a.png")
    check not isHttpUrl("data:image/png;base64,QUJD")
    check not isHttpUrl("")

const
  DataPng = "data:image/png;base64,QUJD"
  InlineMarker =
    "[Imagem anexada: attachments/a.png (image/png, 3 bytes). " &
    "A imagem já acompanha esta mensagem; use inspect_image com path=\"" &
    "attachments/a.png\" apenas para ver detalhe (recorte/zoom).]"

suite "demoteInlineImageText":

  test "drops the inline promise and keeps the inspect_image path":
    let demoted = demoteInlineImageText(InlineMarker)
    check "acompanha esta mensagem" notin demoted
    check "attachments/a.png" in demoted
    check "inspect_image" in demoted

  test "is idempotent and never accumulates removal notes":
    let once = demoteInlineImageText(InlineMarker) & "\n\n" & InlineImageRemovedNote
    let twice = demoteInlineImageText(once)
    check twice.count(InlineImageRemovedNote) == 0
    check "acompanha esta mensagem" notin twice

suite "withoutInlineImages text demotion":

  test "no longer claims the image travels with the message":
    var h = newHistory()
    h.addUserWithImage(InlineMarker, DataPng)
    let stripped = withoutInlineImages(CompletionRequest(messages: h))
    check stripped.messages.len == 1
    check stripped.messages[0].imageUrl == ""
    check "acompanha esta mensagem" notin stripped.messages[0].text
    check "inspect_image" in stripped.messages[0].text
    check stripped.messages[0].text.count(InlineImageRemovedNote) == 1

  test "the removal note is the only added statement":
    var h = newHistory()
    h.addUserWithImage("veja", DataPng)
    let stripped = withoutInlineImages(CompletionRequest(messages: h))
    check stripped.messages[0].text == "veja\n\n" & InlineImageRemovedNote

suite "demoteInlineImagesForTurn":

  test "keeps the persistent history text-only and note-free":
    var h = newHistory()
    h.addUserWithImage(InlineMarker, DataPng)
    h.addAssistant("claro")
    let demoted = demoteInlineImagesForTurn(h)
    check demoted.len == 2
    check demoted[0].imageUrl == ""
    check "acompanha esta mensagem" notin demoted[0].text
    check "attachments/a.png" in demoted[0].text
    check InlineImageRemovedNote notin demoted[0].text

  test "an image-only album keeps one note instead of an empty turn":
    var h = newHistory()
    h.addUserWithImage("", DataPng)
    h.addUserWithImage("", "data:image/jpeg;base64,QQ==")
    let demoted = demoteInlineImagesForTurn(h)
    check demoted.len == 1
    check demoted[0].role == roleUser
    check demoted[0].text == InlineImageRemovedNote
