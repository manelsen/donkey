## US-002: the session transcript keeps an inline image as a short reference,
## never as the base64 payload, so a photo does not inflate the `.jsonl`.

import std/[os, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/core/types
import donkey/domain/memory/transcript_pure
import donkey/domain/message

const TestRoot = "/tmp/donkey_transcript_image_ref_tests"

suite "transcriptImageRef":

  test "data URL becomes the inline reference":
    check InlineImageRef == "inline"
    check transcriptImageRef("data:image/png;base64,iVBORw0KGgo=") == InlineImageRef
    check transcriptImageRef("data:image/jpeg;base64,/9j/4AAQ") == InlineImageRef

  test "http and https URLs stay unchanged":
    check transcriptImageRef("https://example.com/photo.png") ==
      "https://example.com/photo.png"
    check transcriptImageRef("http://example.com/photo.jpg") ==
      "http://example.com/photo.jpg"

  test "local paths and empty values stay unchanged":
    check transcriptImageRef("/tmp/donkey/photo.jpg") == "/tmp/donkey/photo.jpg"
    check transcriptImageRef("") == ""

  test "only the data: scheme counts, not a word inside the URL":
    check transcriptImageRef("https://example.com/data:image.png") ==
      "https://example.com/data:image.png"

suite "MdFileAdapter saveSession image reference":

  setup:
    removeDir(TestRoot)
    createDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "a data URL image is stored as inline, without base64":
    let adapter = MdFileAdapter(paddocksDir: TestRoot)
    let uid = UserId("image-ref-user")
    var history: ConversationHistory
    history.add ChatMessage(role: roleUser, text: "o que tem na foto?",
                            imageUrl: "data:image/png;base64,iVBORw0KGgo=")
    history.add ChatMessage(role: roleAssistant, text: "um gato")

    adapter.saveSession(uid, "session-1", history)

    let path = TestRoot / "image-ref-user" / "sessions" / "session-1.jsonl"
    check fileExists(path)
    let content = readFile(path)
    check "data:image" notin content
    check "base64" notin content
    check "\"imageUrl\":\"inline\"" in content

  test "an http image URL is stored unchanged":
    let adapter = MdFileAdapter(paddocksDir: TestRoot)
    let uid = UserId("image-ref-user-http")
    var history: ConversationHistory
    history.add ChatMessage(role: roleUser, text: "veja",
                            imageUrl: "https://example.com/photo.png")
    history.add ChatMessage(role: roleAssistant, text: "vi")

    adapter.saveSession(uid, "session-2", history)

    let path = TestRoot / "image-ref-user-http" / "sessions" / "session-2.jsonl"
    check fileExists(path)
    let content = readFile(path)
    check "\"imageUrl\":\"https://example.com/photo.png\"" in content
