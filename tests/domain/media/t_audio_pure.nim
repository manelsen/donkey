## Audio helpers for the STT/TTS tools: MIME mapping, multipart upload,
## transcript parsing and the speech request body.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/media/audio_pure

proc runTests*() =
  suite "audio mime types":

    test "maps the formats the transcription endpoints accept":
      check audioMimeType("a.mp3") == "audio/mpeg"
      check audioMimeType("a.OGG") == "audio/ogg"
      check audioMimeType("a.opus") == "audio/ogg"
      check audioMimeType("a.wav") == "audio/wav"
      check audioMimeType("a.m4a") == "audio/mp4"
      check audioMimeType("a.webm") == "audio/webm"
      check audioMimeType("a.flac") == "audio/flac"

    test "an unknown extension has no mime":
      check audioMimeType("a.txt") == ""
      check audioMimeType("noext") == ""

  suite "speech format":

    test "accepts and normalises the supported formats":
      check speechExtension("mp3").get() == "mp3"
      check speechExtension(" OPUS ").get() == "opus"
      check speechExtension("wav").get() == "wav"

    test "rejects an unknown format":
      check speechExtension("exe").isErr

  suite "multipart body":

    test "frames fields and the file with CRLF":
      let body = buildMultipartBody("BOUND", "file", "a.mp3", "audio/mpeg",
                                    "BYTES",
                                    @[("model", "whisper-1"), ("language", "pt")])
      check body.startsWith("--BOUND\r\n")
      check body.endsWith("\r\n--BOUND--\r\n")
      check body.contains("""Content-Disposition: form-data; name="model"""")
      check body.contains("whisper-1")
      check body.contains("""Content-Disposition: form-data; name="language"""")
      check body.contains("""Content-Disposition: form-data; name="file"; filename="a.mp3"""")
      check body.contains("Content-Type: audio/mpeg")
      check body.contains("\r\n\r\nBYTES\r\n")

    test "binary payloads survive byte for byte":
      let payload = "\x00\x01\xff audio"
      check buildMultipartBody("B", "file", "a.ogg", "audio/ogg", payload).contains(payload)

  suite "transcript parsing":

    test "returns the trimmed text":
      check parseTranscript("""{"text": "  olá mundo  "}""").get() == "olá mundo"

    test "an empty transcript is an error":
      check parseTranscript("""{"text": "   "}""").isErr

    test "an error object surfaces its message":
      let res = parseTranscript("""{"error": {"message": "invalid file"}}""")
      check res.isErr
      check res.error.contains("invalid file")

    test "invalid JSON is an error":
      check parseTranscript("not json").isErr

  suite "speech payload":

    test "carries model, input, voice and format":
      let node = parseJson(buildSpeechPayload("tts-1", "olá", "alloy", "mp3"))
      check node["model"].getStr() == "tts-1"
      check node["input"].getStr() == "olá"
      check node["voice"].getStr() == "alloy"
      check node["response_format"].getStr() == "mp3"

when isMainModule:
  runTests()
