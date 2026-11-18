## TelegramAdapter — local media upload tests.
##
## The transport is a fake HttpRuntimePort: no network, no real Telegram.
## The audio fixtures are real one-second Ogg/Opus and MP3 files generated
## with ffmpeg; the assertions validate multipart framing and the advertised
## MIME type, not the decoded audio content.

import std/[json, os, strutils, unittest]
import donkey/adapters/channel/telegram
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/telegram_pure
import donkey/domain/message
import donkey/ports/http

const
  OggFixture = "tests/fixtures/media/sample.ogg"
  Mp3Fixture = "tests/fixtures/media/sample.mp3"
  NeutralFallback = "não foi possível enviar o anexo"

type
  Recorded = object
    url:     string
    body:    string
    headers: seq[HttpHeader]

  FakeUpload = ref object
    calls:          seq[Recorded]
    failMethods:    seq[string]
    failThreadOnce: bool
    threadFailed:   bool

proc fake(f: FakeUpload): HttpRuntimePort =
  HttpRuntimePort(
    post: proc (url, body: string; headers: seq[HttpHeader] = @[]):
               Result[HttpResponse, string] {.gcsafe.} =
      f.calls.add Recorded(url: url, body: body, headers: headers)
      if f.failThreadOnce and not f.threadFailed and
         body.contains("name=\"message_thread_id\""):
        f.threadFailed = true
        return ok(HttpResponse(status: 400,
          body: """{"ok":false,"description":"Bad Request: message thread not found"}"""))
      for meth in f.failMethods:
        if url.contains(meth):
          return ok(HttpResponse(status: 400,
            body: """{"ok":false,"description":"Bad Request: chat not found"}"""))
      ok(HttpResponse(status: 200, body: """{"ok":true,"result":{"message_id":1}}"""))
  )

proc headerValue(headers: seq[HttpHeader]; name: string): string =
  for (key, value) in headers:
    if key.toLowerAscii() == name.toLowerAscii():
      return value
  ""

proc multipartField(body, name: string): string =
  let marker = "Content-Disposition: form-data; name=\"" & name & "\"\r\n\r\n"
  let start = body.find(marker)
  if start < 0:
    return ""
  let valueStart = start + marker.len
  let valueEnd = body.find("\r\n", valueStart)
  if valueEnd < 0: "" else: body[valueStart ..< valueEnd]

proc hasField(body, name: string): bool =
  body.contains("Content-Disposition: form-data; name=\"" & name & "\"")

var idsSeq = 0

proc newAdapter(f: FakeUpload): TelegramAdapter =
  inc idsSeq
  let idsPath = getTempDir() / ("donkey_tg_upload_ids_" & $idsSeq & ".tsv")
  removeFile(idsPath)
  newTelegramAdapter("TOK", idsPath, apiBase = "https://tg.test",
                     uploadHttp = fake(f))

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_tg_upload_" & tag & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

suite "TelegramAdapter — local media upload":

  test "ogg is uploaded as a voice note with thread and reply preserved":
    let f = FakeUpload()
    let a = newAdapter(f)
    let target = telegramReplyTarget("42", "900", "7")
    let res = a.sendMedia(42, OggFixture, "legenda", target)
    check res.isOk
    check f.calls.len == 1
    check f.calls[0].url == "https://tg.test/botTOK/sendVoice"
    let contentType = headerValue(f.calls[0].headers, "Content-Type")
    check contentType.startsWith("multipart/form-data; boundary=")
    let body = f.calls[0].body
    check multipartField(body, "chat_id") == "42"
    check multipartField(body, "caption") == "legenda"
    check multipartField(body, "message_thread_id") == "7"
    check multipartField(body, "reply_to_message_id") == "900"
    check body.contains("name=\"voice\"; filename=\"sample.ogg\"")
    check body.contains("Content-Type: audio/ogg")
    check body.contains(readFile(OggFixture))
    check not hasField(body, "duration")

  test "mp3 is uploaded as audio and mediaDurationSec reaches the body":
    let f = FakeUpload()
    let a = newAdapter(f)
    let uid = a.resolver.resolve(ckTelegram, "42")
    let msg = OutboundMessage(userId: uid, text: "musica", mediaUrl: Mp3Fixture,
                              mediaDurationSec: 4)
    let res = a.send(msg)
    check res.isOk
    check f.calls.len == 1
    check f.calls[0].url == "https://tg.test/botTOK/sendAudio"
    let body = f.calls[0].body
    check multipartField(body, "duration") == "4"
    check body.contains("name=\"audio\"; filename=\"sample.mp3\"")
    check body.contains("Content-Type: audio/mpeg")
    check body.contains(readFile(Mp3Fixture))

  test "duration is omitted when mediaDurationSec is zero":
    let f = FakeUpload()
    let a = newAdapter(f)
    let uid = a.resolver.resolve(ckTelegram, "42")
    let msg = OutboundMessage(userId: uid, text: "musica", mediaUrl: Mp3Fixture)
    check a.send(msg).isOk
    check not hasField(f.calls[0].body, "duration")

  test "a refused photo falls back to sendDocument":
    let dir = freshDir("photo")
    defer: removeDir(dir)
    let path = dir / "foto.png"
    writeFile(path, "\x89PNG\r\n\x1a\nIMAGEM")
    let f = FakeUpload(failMethods: @["sendPhoto"])
    let a = newAdapter(f)
    check a.sendMedia(42, path, "foto", "").isOk
    check f.calls.len == 2
    check f.calls[0].url.endsWith("/sendPhoto")
    check f.calls[1].url.endsWith("/sendDocument")
    check f.calls[1].body.contains("name=\"document\"; filename=\"foto.png\"")
    check not f.calls[1].body.contains("name=\"photo\"")

  test "a missing forum topic retries without message_thread_id":
    let f = FakeUpload(failThreadOnce: true)
    let a = newAdapter(f)
    let target = telegramReplyTarget("42", "900", "7")
    check a.sendMedia(42, OggFixture, "legenda", target).isOk
    check f.calls.len == 2
    check f.calls[0].url.endsWith("/sendVoice")
    check f.calls[1].url.endsWith("/sendVoice")
    check hasField(f.calls[0].body, "message_thread_id")
    check not hasField(f.calls[1].body, "message_thread_id")

  test "everything failing sends neutral text without the file path":
    let dir = freshDir("fallback")
    defer: removeDir(dir)
    let path = dir / "segredo-absoluto-xyz.ogg"
    writeFile(path, "OGG")
    let f = FakeUpload(failMethods: @["sendVoice", "sendAudio",
                                      "sendPhoto", "sendDocument"])
    let a = newAdapter(f)
    let target = telegramReplyTarget("42", "900", "7")
    check a.sendMedia(42, path, "legenda", target).isOk
    let last = f.calls[^1]
    check last.url.endsWith("/sendMessage")
    check last.body.contains(NeutralFallback)
    check not last.body.contains("segredo-absoluto-xyz")
    check not last.body.contains(dir)
    check not last.body.contains(".ogg")
    check not last.body.contains("/")

  test "a refused neutral text reports a path-free error":
    let dir = freshDir("fallback-error")
    defer: removeDir(dir)
    let path = dir / "segredo-absoluto-xyz.mp3"
    writeFile(path, "MP3")
    let f = FakeUpload(failMethods: @["sendVoice", "sendAudio",
                                      "sendPhoto", "sendDocument",
                                      "sendMessage"])
    let a = newAdapter(f)
    let res = a.sendMedia(42, path, "legenda", "")
    check res.isErr
    check res.error == NeutralFallback
    check not res.error.contains("segredo-absoluto-xyz")
    check not res.error.contains(dir)

  test "the constructed adapter owns an upload transport":
    let f = FakeUpload()
    let a = newAdapter(f)
    check not a.uploadHttp.post.isNil
    let defaulted = newTelegramAdapter("TOK", getTempDir() / "donkey_tg_ids_default.tsv")
    check not defaulted.uploadHttp.post.isNil
