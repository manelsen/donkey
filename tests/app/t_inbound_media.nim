import std/[os, strutils, unittest]
import results
import donkey/app/inbound_media
import donkey/adapters/filesystem/attachment_store
import donkey/adapters/filesystem/fs_adapter
import donkey/domain/message
import donkey/ports/channel

const TestRoot = "/tmp/donkey_inbound_media_tests"

proc bytesOf(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ch)

proc downloadOf(name, mime, text: string): FileDownload =
  FileDownload(
    fileName: name,
    fileSize: text.len.int64,
    mimeType: mime,
    data: bytesOf(text),
  )

suite "inbound media":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "saves document inside attachments and annotates the turn":
    var msg = InboundMessage(text: "leia isso", mediaUrl: "telegram-file-id")
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.md", "text/markdown", "# export\n"),
      TestRoot, newAttachmentStore(), "Memory Export.md", "text/markdown")
    check res.isOk
    let att = res.get()
    check att.relPath == "attachments/Memory Export.md"
    check att.isImage == false
    check fileExists(TestRoot / att.relPath)
    check readFile(TestRoot / att.relPath) == "# export\n"
    check msg.mediaUrl == ""
    check "attachments/Memory Export.md" in msg.text
    check "fs_read" in msg.text
    check "telegram-file-id" notin msg.text

  test "sanitizes path traversal names":
    var msg = InboundMessage()
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.md", "text/markdown", "x"),
      TestRoot, newAttachmentStore(), "../../etc/passwd", "text/markdown")
    check res.isOk
    let att = res.get()
    check att.relPath == "attachments/passwd"
    check fileExists(TestRoot / "attachments" / "passwd")
    check not fileExists("/etc/passwd_donkey_probe")

  test "image marker points at inspect_image":
    var msg = InboundMessage()
    let res = applyInboundAttachment(
      msg, downloadOf("file_1.png", "image/png", "png"),
      TestRoot, newAttachmentStore(), "photo.png", "image/png")
    check res.isOk
    check res.get().isImage
    check "inspect_image" in msg.text
    check "attachments/photo.png" in msg.text

  test "empty preferred name falls back to attachment":
    var msg = InboundMessage()
    let res = applyInboundAttachment(
      msg, downloadOf("", "application/octet-stream", "x"),
      TestRoot, newAttachmentStore(), "", "")
    check res.isOk
    check res.get().relPath.startsWith("attachments/")

  when defined(posix):
    test "attachments directory and files are private":
      var msg = InboundMessage()
      let res = applyInboundAttachment(
        msg, downloadOf("file.md", "text/markdown", "secret"),
        TestRoot, newAttachmentStore(), "notes.md", "text/markdown")
      check res.isOk
      check getFilePermissions(TestRoot / "attachments") ==
        {fpUserRead, fpUserWrite, fpUserExec}
      check getFilePermissions(res.get().absPath) ==
        {fpUserRead, fpUserWrite}

  when defined(posix):
    test "rejects a symlinked attachments directory":
      let outside = TestRoot / "outside"
      createDir(outside)
      createSymlink(outside, TestRoot / "attachments")
      var msg = InboundMessage()
      let res = applyInboundAttachment(
        msg, downloadOf("file.md", "text/markdown", "secret"),
        TestRoot, newAttachmentStore(), "notes.md", "text/markdown")
      check res.isErr
      check not fileExists(outside / "notes.md")

  when defined(posix):
    test "does not write through a dangling attachment filename":
      let attachments = TestRoot / "attachments"
      createDir(attachments)
      let outside = TestRoot / "outside-target.md"
      removeFile(outside)
      createSymlink(outside, attachments / "notes.md")
      var msg = InboundMessage()
      let res = applyInboundAttachment(
        msg, downloadOf("file.md", "text/markdown", "data"),
        TestRoot, newAttachmentStore(), "notes.md", "text/markdown")
      check res.isOk
      check res.get().relPath == "attachments/notes_1.md"
      check fileExists(attachments / "notes_1.md")
      check not fileExists(outside)
