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
