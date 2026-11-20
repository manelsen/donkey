## Tests for the pure multipart upload contract of the Telegram adapter.
##
## Nothing here touches the network or the filesystem: mediaUploadSpec decides
## method/field/mime from the file name and mediaUploadBody frames the
## multipart payload the Bot API expects.

import std/[strutils, unittest]
import donkey/domain/channels/telegram_policy

proc multipartField(body, name: string): string =
  ## Returns the value of the first plain multipart field called `name`.
  let marker = "Content-Disposition: form-data; name=\"" & name & "\"\r\n\r\n"
  let start = body.find(marker)
  if start < 0:
    return ""
  let valueStart = start + marker.len
  let valueEnd = body.find("\r\n", valueStart)
  if valueEnd < 0: "" else: body[valueStart ..< valueEnd]

proc hasField(body, name: string): bool =
  body.contains("Content-Disposition: form-data; name=\"" & name & "\"")

proc runTests*() =
  suite "mediaUploadSpec — method, field and mime per file type":

    test "ogg goes through sendVoice with the voice field and audio/ogg":
      let spec = mediaUploadSpec("/tmp/nota.ogg", 42, "legenda")
      check spec.`method` == "sendVoice"
      check spec.field == "voice"
      check spec.mime == "audio/ogg"
      check spec.chatId == 42
      check spec.caption == "legenda"

    test "opus is a voice note too":
      let spec = mediaUploadSpec("/tmp/nota.opus", 1, "")
      check spec.`method` == "sendVoice"
      check spec.field == "voice"
      check spec.mime == "audio/ogg"

    test "mp3 goes through sendAudio with the audio field and audio/mpeg":
      let spec = mediaUploadSpec("/tmp/musica.mp3", 7, "")
      check spec.`method` == "sendAudio"
      check spec.field == "audio"
      check spec.mime == "audio/mpeg"

    test "m4a still goes through sendAudio":
      let spec = mediaUploadSpec("/tmp/musica.m4a", 7, "")
      check spec.`method` == "sendAudio"
      check spec.field == "audio"
      check spec.mime == "audio/mp4"

    test "png goes through sendPhoto":
      let spec = mediaUploadSpec("/tmp/foto.png", 1, "")
      check spec.`method` == "sendPhoto"
      check spec.field == "photo"
      check spec.mime == "image/png"

    test "jpeg goes through sendPhoto":
      let spec = mediaUploadSpec("/tmp/foto.JPEG", 1, "")
      check spec.`method` == "sendPhoto"
      check spec.field == "photo"
      check spec.mime == "image/jpeg"

    test "pdf is a document":
      let spec = mediaUploadSpec("/tmp/relatorio.pdf", 1, "")
      check spec.`method` == "sendDocument"
      check spec.field == "document"
      check spec.mime == "application/pdf"

    test "anything else is a document":
      let spec = mediaUploadSpec("/tmp/arquivo.zip", 1, "")
      check spec.`method` == "sendDocument"
      check spec.field == "document"
      check spec.mime == "application/octet-stream"

    test "the file name keeps only the base name":
      let spec = mediaUploadSpec("/tmp/pasta/nota.ogg", 1, "")
      check spec.fileName == "nota.ogg"

    test "thread, reply and duration travel in the spec":
      let spec = mediaUploadSpec("/tmp/nota.ogg", 1, "", threadId = "9",
                                 replyTo = "11", durationSec = 4)
      check spec.threadId == "9"
      check spec.replyTo == "11"
      check spec.durationSec == 4

    test "a negative duration is clamped to zero":
      let spec = mediaUploadSpec("/tmp/nota.ogg", 1, "", durationSec = -3)
      check spec.durationSec == 0


  suite "mediaUploadBody — multipart framing":

    test "frames chat_id, caption, thread, reply, file name and bytes":
      let spec = mediaUploadSpec("/tmp/pasta/sample.ogg", 42, "olá",
                                 threadId = "9", replyTo = "11")
      let body = mediaUploadBody(spec, "OGGDATA", "BOUNDARY")
      check body.startsWith("--BOUNDARY\r\n")
      check body.endsWith("\r\n--BOUNDARY--\r\n")
      check multipartField(body, "chat_id") == "42"
      check multipartField(body, "caption") == "olá"
      check multipartField(body, "message_thread_id") == "9"
      check multipartField(body, "reply_to_message_id") == "11"
      check body.contains("name=\"voice\"; filename=\"sample.ogg\"")
      check body.contains("Content-Type: audio/ogg")
      check body.contains("OGGDATA")

    test "empty caption and reply fields are omitted":
      let spec = mediaUploadSpec("/tmp/sample.mp3", 7, "")
      let body = mediaUploadBody(spec, "MP3DATA", "B")
      check not hasField(body, "caption")
      check not hasField(body, "message_thread_id")
      check not hasField(body, "reply_to_message_id")

    test "sendVoice carries duration when it is known":
      let spec = mediaUploadSpec("/tmp/sample.ogg", 1, "", durationSec = 3)
      let body = mediaUploadBody(spec, "X", "B")
      check multipartField(body, "duration") == "3"

    test "sendAudio carries duration when it is known":
      let spec = mediaUploadSpec("/tmp/sample.mp3", 1, "", durationSec = 5)
      let body = mediaUploadBody(spec, "X", "B")
      check multipartField(body, "duration") == "5"

    test "duration is omitted when it is zero":
      let voice = mediaUploadBody(mediaUploadSpec("/tmp/sample.ogg", 1, ""), "X", "B")
      let audio = mediaUploadBody(mediaUploadSpec("/tmp/sample.mp3", 1, ""), "X", "B")
      check not hasField(voice, "duration")
      check not hasField(audio, "duration")

    test "a photo never carries duration":
      let spec = mediaUploadSpec("/tmp/foto.png", 1, "", durationSec = 3)
      let body = mediaUploadBody(spec, "X", "B")
      check not hasField(body, "duration")

    test "a document never carries duration":
      let spec = mediaUploadSpec("/tmp/doc.pdf", 1, "", durationSec = 3)
      let body = mediaUploadBody(spec, "X", "B")
      check not hasField(body, "duration")

    test "quotes in the file name cannot break the header":
      let spec = mediaUploadSpec("/tmp/nota\"x.ogg", 1, "")
      let body = mediaUploadBody(spec, "X", "B")
      check body.contains("filename=\"nota'x.ogg\"")


  suite "mediaUploadBody — hostile field values":

    test "a caption carrying CRLF and a boundary cannot inject a part":
      let injection = "legenda\r\n--BOUNDARY\r\n" &
                      "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n999"
      let spec = mediaUploadSpec("/tmp/x.ogg", 42, injection)
      check '\r' notin spec.caption
      check '\n' notin spec.caption
      let body = mediaUploadBody(spec, "DATA", "BOUNDARY")
      check multipartField(body, "chat_id") == "42"
      ## chat_id and caption parts open normally: the caption did not add a part.
      check body.count("\r\n--BOUNDARY\r\n") == 2
      check multipartField(body, "caption").contains("999")

    test "a filename with quotes and CRLF cannot break the header":
      let spec = mediaUploadSpec("/tmp/e\"vil\r\nX-Injected: yes.ogg", 1, "")
      check '\r' notin spec.fileName
      check '\n' notin spec.fileName
      check '"' notin spec.fileName
      let body = mediaUploadBody(spec, "DATA", "B")
      check body.count("filename=\"") == 1
      check not body.contains("\r\nX-Injected")

    test "non-numeric thread and reply ids are dropped":
      let spec = mediaUploadSpec("/tmp/x.ogg", 1, "",
                                 threadId = "7\r\nX-Injected: yes",
                                 replyTo = "11 or 1=1")
      check spec.threadId == ""
      check spec.replyTo == ""
      let body = mediaUploadBody(spec, "DATA", "B")
      check not hasField(body, "message_thread_id")
      check not hasField(body, "reply_to_message_id")

    test "numeric thread and reply ids survive validation":
      let spec = mediaUploadSpec("/tmp/x.ogg", 1, "", threadId = "-7",
                                 replyTo = "11")
      check spec.threadId == "-7"
      check spec.replyTo == "11"


  suite "multipart boundary selection":

    test "a boundary absent from the payload is kept":
      let payload = "caption and DATA"
      check pickMultipartBoundary("a1b2", payload) ==
        TelegramMultipartBoundaryPrefix & "a1b2"

    test "a boundary found in the payload is replaced":
      let candidate = "deadbeef"
      let colliding = TelegramMultipartBoundaryPrefix & candidate
      let payload = "prefix " & colliding & " suffix"
      let picked = pickMultipartBoundary(candidate, payload)
      check picked != colliding
      check not payload.contains(picked)


  suite "apiBase policy":

    test "the host is derived from the Base URL":
      check telegramApiHost("https://worker.example") == "worker.example"
      check telegramApiHost("https://worker.example:8443/bot") == "worker.example:8443"
      check telegramApiHost("http://127.0.0.1:8080/") == "127.0.0.1:8080"
      check telegramApiHost("") == ""

    test "the allowlist carries the derived host":
      check telegramApiAllowlist("") == @["api.telegram.org"]
      check telegramApiAllowlist("https://worker.example") == @["worker.example"]
      check telegramApiAllowlist("https://worker.example:8443") ==
        @["worker.example:8443"]

    test "https is required outside loopback":
      check telegramApiBaseError("") == ""
      check telegramApiBaseError("https://worker.example") == ""
      check telegramApiBaseError("http://127.0.0.1:8080") == ""
      check telegramApiBaseError("http://localhost:8080") == ""
      check telegramApiBaseError("http://[::1]:8080") == ""
      check telegramApiBaseError("http://worker.example").len > 0
      check telegramApiBaseError("ftp://worker.example").len > 0
      check telegramApiBaseError("worker.example").len > 0


  suite "photo rejection":

    test "the Bot API photo-specific errors are recognised":
      check isPhotoRejectedError("Bad Request: IMAGE_PROCESS_FAILED")
      check isPhotoRejectedError("Bad Request: PHOTO_INVALID_DIMENSIONS")
      check isPhotoRejectedError("Bad Request: PHOTO_SAVE_FILE_INVALID")
      check isPhotoRejectedError("image_process_failed")

    test "a timeout or an unrelated refusal is not photo-specific":
      check not isPhotoRejectedError("HTTP POST failed after 1 attempts. Last error: timed out")
      check not isPhotoRejectedError("Bad Request: chat not found")
      check not isPhotoRejectedError("Too Many Requests: retry after 30")
      check not isPhotoRejectedError("")

when isMainModule:
  runTests()
