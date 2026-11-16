## Regression: a Telegram document must be saved inside the paddock and the
## channel file_id must never become an imageUrl/provider payload.

import std/[json, os, strutils, unittest]
import results
import donkey/app/inbound_media
import donkey/app/tools/attachment_store
import donkey/app/session_bootstrap
import donkey/app/prompt_building
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/telegram_pure
import donkey/domain/message
import donkey/ports/channel

const TestRoot = "/tmp/donkey_ingestion_regression_tests"

proc bytesOf(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ch)

suite "telegram document ingestion regression":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "document is saved in attachments and never leaks a file_id":
    let content = "# MEMORY EXPORT\n\nnome: Manel\n"
    let update = %* {
      "update_id": 1,
      "message": {
        "message_id": 10,
        "from": {"id": 1001, "first_name": "Manel"},
        "chat": {"id": 1001, "type": "private"},
        "caption": "ingere isso",
        "document": {
          "file_id": "telegram-doc-id",
          "file_name": "Memory Export.md",
          "mime_type": "text/markdown",
        },
      },
    }

    let parsed = update |> parseUpdate
    check parsed.hasMedia
    check parsed.mediaFileId == "telegram-doc-id"
    check parsed.mediaFileName == "Memory Export.md"
    check parsed.mediaMimeType == "text/markdown"

    var msg = parsed.toInbound(UserId("ingest-user"))
    msg.mediaUrl = parsed.mediaFileId
    let download = FileDownload(
      fileName: "file_1.md",
      fileSize: content.len.int64,
      mimeType: "text/markdown",
      data: bytesOf(content),
    )
    let saved = applyInboundAttachment(
      msg, download, TestRoot, newAttachmentStore(),
      msg.mediaFileName, msg.mediaMimeType)
    check saved.isOk
    check saved.get().relPath == "attachments/Memory Export.md"
    check fileExists(TestRoot / saved.get().relPath)
    check readFile(TestRoot / saved.get().relPath) == content
    check msg.mediaUrl == ""

    let payload = encodeSessionPayload(msg)
    let decoded = decodeUserPayload(payload)
    check decoded.text.contains("ingere isso")
    check decoded.text.contains("attachments/Memory Export.md")
    check decoded.mediaUrl == ""
    check "telegram-doc-id" notin payload

    # The old daemon default wrote to {appDir}/downloads; it must stay unused.
    check not dirExists(getAppDir() / "downloads")
