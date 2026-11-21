## TelegramAdapter — local media upload tests.
##
## The transport is a fake HttpRuntimePort: no network, no real Telegram.
## The audio fixtures are real one-second Ogg/Opus and MP3 files generated
## with ffmpeg; the assertions validate multipart framing and the advertised
## MIME type, not the decoded audio content.

import std/[json, os, posix, strutils, tables, unittest]
import donkey/adapters/channel/telegram
import donkey/core/channels/flood_gate
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
    calls:               seq[Recorded]
    failMethods:         seq[string]
    failDescription:     string
    floodMethods:        seq[string]
    failThreadOnce:      bool
    threadFailed:        bool
    replyFailureMethod:  string
    replyFailed:         bool
    preferNoRedirect:    bool
    noRedirectCalls:     int

proc handleCall(f: FakeUpload; url, body: string;
                headers: seq[HttpHeader]): Result[HttpResponse, string] {.gcsafe.} =
  f.calls.add Recorded(url: url, body: body, headers: headers)
  if f.replyFailureMethod.len > 0 and not f.replyFailed and
     url.contains(f.replyFailureMethod) and
     body.contains("name=\"reply_to_message_id\""):
    f.replyFailed = true
    return ok(HttpResponse(status: 400,
      body: """{"ok":false,"description":"Bad Request: message to be replied not found"}"""))
  if f.failThreadOnce and not f.threadFailed and
     body.contains("name=\"message_thread_id\""):
    f.threadFailed = true
    return ok(HttpResponse(status: 400,
      body: """{"ok":false,"description":"Bad Request: message thread not found"}"""))
  for meth in f.floodMethods:
    if url.contains(meth):
      return ok(HttpResponse(status: 429,
        body: """{"ok":false,"description":"Too Many Requests: retry after 30","parameters":{"retry_after":30}}"""))
  for meth in f.failMethods:
    if url.contains(meth):
      let description =
        if f.failDescription.len > 0: f.failDescription
        else: "Bad Request: chat not found"
      return ok(HttpResponse(status: 400,
        body: $ %*{"ok": false, "description": description}))
  ok(HttpResponse(status: 200, body: """{"ok":true,"result":{"message_id":1}}"""))

proc fake(f: FakeUpload): HttpRuntimePort =
  result = HttpRuntimePort(
    post: proc (url, body: string; headers: seq[HttpHeader] = @[]):
               Result[HttpResponse, string] {.gcsafe.} =
      handleCall(f, url, body, headers)
  )
  if f.preferNoRedirect:
    result.postNoRedirect = proc (url, body: string;
                                  headers: seq[HttpHeader] = @[]):
                                 Result[HttpResponse, string] {.gcsafe.} =
      inc f.noRedirectCalls
      handleCall(f, url, body, headers)

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

var raceSwapTarget {.threadvar.}: string
  ## Outside path used by the descriptor-race tests (a gcsafe callback cannot
  ## capture a GC'd local).
var raceSwapRoot {.threadvar.}: string
var raceSwapOutside {.threadvar.}: string

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

proc runTests*() =
  suite "TelegramAdapter — local media upload":

    test "ogg is uploaded as a voice note with thread and reply preserved":
      let f = FakeUpload()
      let a = newAdapter(f)
      let target = telegramReplyTarget("42", "900", "7")
      let res = a.sendMedia(42, OggFixture, "legenda", target,
                            mediaRoot = getCurrentDir())
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
                                mediaRoot: getCurrentDir(),
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
      let msg = OutboundMessage(userId: uid, text: "musica", mediaUrl: Mp3Fixture,
                                mediaRoot: getCurrentDir())
      check a.send(msg).isOk
      check not hasField(f.calls[0].body, "duration")

    test "a photo refused for its dimensions falls back to sendDocument":
      let dir = freshDir("photo")
      defer: removeDir(dir)
      let path = dir / "foto.png"
      writeFile(path, "\x89PNG\r\n\x1a\nIMAGEM")
      let f = FakeUpload(failMethods: @["sendPhoto"],
                         failDescription: "Bad Request: PHOTO_INVALID_DIMENSIONS")
      let a = newAdapter(f)
      check a.sendMedia(42, path, "foto", "", mediaRoot = dir).isOk
      check f.calls.len == 2
      check f.calls[0].url.endsWith("/sendPhoto")
      check f.calls[1].url.endsWith("/sendDocument")
      check f.calls[1].body.contains("name=\"document\"; filename=\"foto.png\"")
      check not f.calls[1].body.contains("name=\"photo\"")

    test "a timeout does not duplicate the photo as a document":
      let dir = freshDir("photo-timeout")
      defer: removeDir(dir)
      let path = dir / "foto.png"
      writeFile(path, "\x89PNG\r\n\x1a\nIMAGEM")
      let f = FakeUpload(failMethods: @["sendPhoto"],
                         failDescription: "HTTP POST failed after 1 attempts. Last error: timed out")
      let a = newAdapter(f)
      check a.sendMedia(42, path, "foto", "", mediaRoot = dir).isOk
      ## The upload is not repeated as a document; only the neutral text follows.
      check f.calls.len == 2
      check f.calls[0].url.endsWith("/sendPhoto")
      check f.calls[1].url.endsWith("/sendMessage")
      check not f.calls[1].url.endsWith("/sendDocument")

    test "a missing forum topic retries without message_thread_id":
      let f = FakeUpload(failThreadOnce: true)
      let a = newAdapter(f)
      let target = telegramReplyTarget("42", "900", "7")
      check a.sendMedia(42, OggFixture, "legenda", target,
                        mediaRoot = getCurrentDir()).isOk
      check f.calls.len == 2
      check f.calls[0].url.endsWith("/sendVoice")
      check f.calls[1].url.endsWith("/sendVoice")
      check hasField(f.calls[0].body, "message_thread_id")
      check not hasField(f.calls[1].body, "message_thread_id")

    test "a missing reply anchor retries the upload without reply_to_message_id":
      let f = FakeUpload(replyFailureMethod: "sendVoice")
      let a = newAdapter(f)
      let target = telegramReplyTarget("42", "900", "7")
      check a.sendMedia(42, OggFixture, "legenda", target,
                        mediaRoot = getCurrentDir()).isOk
      check f.calls.len == 2
      check f.calls[0].url.endsWith("/sendVoice")
      check hasField(f.calls[0].body, "reply_to_message_id")
      check not hasField(f.calls[1].body, "reply_to_message_id")
      check hasField(f.calls[1].body, "message_thread_id")

    test "the neutral fallback drops a dead reply anchor":
      let dir = freshDir("fallback-anchor")
      defer: removeDir(dir)
      let path = dir / "nota.ogg"
      writeFile(path, "OGG")
      let f = FakeUpload(failMethods: @["sendVoice", "sendAudio",
                                        "sendPhoto", "sendDocument"],
                         replyFailureMethod: "sendMessage")
      let a = newAdapter(f)
      let target = telegramReplyTarget("42", "900", "")
      check a.sendMedia(42, path, "legenda", target, mediaRoot = dir).isOk
      let last = f.calls[^1]
      check last.url.endsWith("/sendMessage")
      check last.body.contains(NeutralFallback)
      check not hasField(last.body, "reply_to_message_id")

    test "a missing local file becomes neutral text, never the path":
      let dir = freshDir("missing")
      defer: removeDir(dir)
      let path = dir / "nao-existe-absoluto-xyz.ogg"
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, path, "legenda", "", mediaRoot = dir).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check not f.calls[0].body.contains("nao-existe-absoluto-xyz")
      check not f.calls[0].body.contains(dir)

    test "a directory becomes neutral text, never the path":
      let dir = freshDir("directory")
      defer: removeDir(dir)
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, dir, "legenda", "", mediaRoot = dir).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check not f.calls[0].body.contains(dir)

    test "a file above the cap is never read or uploaded":
      let dir = freshDir("oversize")
      defer: removeDir(dir)
      let path = dir / "grande.ogg"
      writeFile(path, "")
      check truncate(path.cstring, Off(TelegramMaxUploadBytes + 1)) == 0
      check getFileSize(path) > TelegramMaxUploadBytes
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, path, "legenda", "", mediaRoot = dir).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check f.calls[0].body.len < 10_000
      check not f.calls[0].body.contains("grande.ogg")

    test "the upload follows the chat in replyTo, not the remembered DM":
      let f = FakeUpload()
      var a = newAdapter(f)
      let uid = a.resolver.resolve(ckTelegram, "42")
      a.chatIds[$uid] = "42"
      let groupTarget = telegramReplyTarget("-100999", "900", "")
      let msg = OutboundMessage(userId: uid, text: "legenda",
                                mediaUrl: OggFixture, replyTo: groupTarget,
                                mediaRoot: getCurrentDir())
      check a.send(msg).isOk
      check f.calls.len == 1
      check multipartField(f.calls[0].body, "chat_id") == "-100999"

    test "the upload follows a DM replyTo even when a group is remembered":
      let f = FakeUpload()
      var a = newAdapter(f)
      let uid = a.resolver.resolve(ckTelegram, "42")
      a.chatIds[$uid] = "-100999"
      let dmTarget = telegramReplyTarget("42", "900", "")
      let msg = OutboundMessage(userId: uid, text: "legenda",
                                mediaUrl: OggFixture, replyTo: dmTarget,
                                mediaRoot: getCurrentDir())
      check a.send(msg).isOk
      check f.calls.len == 1
      check multipartField(f.calls[0].body, "chat_id") == "42"

    test "a 429 upload is recorded and is not amplified":
      let f = FakeUpload(floodMethods: @["sendVoice"])
      let a = newAdapter(f)
      check a.sendMedia(42, OggFixture, "legenda", "",
                        mediaRoot = getCurrentDir()).isOk
      ## One refused upload and the neutral text: no document/audio retry.
      check f.calls.len == 2
      check f.calls[0].url.endsWith("/sendVoice")
      check f.calls[1].url.endsWith("/sendMessage")
      check a.flood.remainingMs(42, epochMs()) > 0

    test "uploads prefer postNoRedirect when the port exposes it":
      let f = FakeUpload(preferNoRedirect: true)
      let a = newAdapter(f)
      check a.sendMedia(42, OggFixture, "legenda", "",
                        mediaRoot = getCurrentDir()).isOk
      check f.noRedirectCalls == 1
      check f.calls.len == 1

    test "each upload uses a fresh random boundary":
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, OggFixture, "um", "",
                        mediaRoot = getCurrentDir()).isOk
      check a.sendMedia(42, OggFixture, "dois", "",
                        mediaRoot = getCurrentDir()).isOk
      let first = headerValue(f.calls[0].headers, "Content-Type")
      let second = headerValue(f.calls[1].headers, "Content-Type")
      check first.startsWith("multipart/form-data; boundary=----donkey-tg-")
      check first != second
      let boundary = first.split("boundary=")[^1]
      check boundary.len > "----donkey-tg-".len + 20
      check f.calls[0].body.count("--" & boundary) == 4

    test "a custom https apiBase allowlists exactly its host":
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.http.allowlist == @["tg.test"]

    test "an http apiBase outside loopback fails closed instead of raising":
      ## Raising aborted daemon startup and every other channel with it. The
      ## adapter records the reason and refuses to send.
      let bad = newTelegramAdapter("TOK", getTempDir() / "donkey_tg_ids_http.tsv",
                                   apiBase = "http://tg.test")
      check bad.configError.len > 0
      var msg = OutboundMessage(userId: UserId("42"), channel: ckTelegram,
                                text: "oi")
      check bad.send(msg).isErr
      let loopback = newTelegramAdapter("TOK",
                                        getTempDir() / "donkey_tg_ids_loopback.tsv",
                                        apiBase = "http://127.0.0.1:8080")
      check loopback.apiBase == "http://127.0.0.1:8080"
      check loopback.http.allowlist == @["127.0.0.1:8080"]

    test "everything failing sends neutral text without the file path":
      let dir = freshDir("fallback")
      defer: removeDir(dir)
      let path = dir / "segredo-absoluto-xyz.ogg"
      writeFile(path, "OGG")
      let f = FakeUpload(failMethods: @["sendVoice", "sendAudio",
                                        "sendPhoto", "sendDocument"])
      let a = newAdapter(f)
      let target = telegramReplyTarget("42", "900", "7")
      check a.sendMedia(42, path, "legenda", target, mediaRoot = dir).isOk
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
      let res = a.sendMedia(42, path, "legenda", "", mediaRoot = dir)
      check res.isErr
      check res.error == NeutralFallback
      check not res.error.contains("segredo-absoluto-xyz")
      check not res.error.contains(dir)

    test "a local file outside the paddock becomes neutral text and survives":
      let base = freshDir("confine-outside")
      defer: removeDir(base)
      let root = base / "paddock"
      createDir(root)
      let outside = base / "segredo-absoluto.ogg"
      writeFile(outside, "OGG")
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, outside, "legenda", "", mediaRoot = root).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check not f.calls[0].body.contains("segredo-absoluto")
      check not f.calls[0].body.contains(base)
      check fileExists(outside)
      check readFile(outside) == "OGG"

    test "a sibling directory sharing the paddock prefix is rejected":
      let base = freshDir("confine-sibling")
      defer: removeDir(base)
      let root = base / "paddock"
      let sibling = base / "paddock2"
      createDir(root)
      createDir(sibling)
      let file = sibling / "foto.png"
      writeFile(file, "PNG")
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, file, "legenda", "", mediaRoot = root).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check not f.calls[0].body.contains("foto.png")
      check fileExists(file)

    test "sendReturnId uploads local media that lives inside the paddock":
      let f = FakeUpload()
      let a = newAdapter(f)
      let uid = a.resolver.resolve(ckTelegram, "42")
      let msg = OutboundMessage(userId: uid, text: "legenda",
                                mediaUrl: OggFixture,
                                mediaRoot: getCurrentDir())
      check a.sendReturnId(msg).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendVoice")

    test "an empty paddock root fails closed":
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, OggFixture, "legenda", "").isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendMessage")
      check f.calls[0].body.contains(NeutralFallback)
      check not f.calls[0].body.contains("sample.ogg")

    test "the canonical path is read and uploaded":
      let root = freshDir("confine-canonical")
      defer: removeDir(root)
      writeFile(root / "real.ogg", "OGGDATA")
      when defined(posix):
        createSymlink(root / "real.ogg", root / "link.ogg")
        let f = FakeUpload()
        let a = newAdapter(f)
        check a.sendMedia(42, root / "link.ogg", "legenda", "",
                          mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendVoice")
        check f.calls[0].body.contains("OGGDATA")
        check f.calls[0].body.contains("filename=\"real.ogg\"")
        check not f.calls[0].body.contains("link.ogg")
      else:
        discard

    test "a symlink out of the paddock is neutral and the target survives":
      let base = freshDir("confine-symlink")
      defer: removeDir(base)
      let root = base / "paddock"
      createDir(root)
      let outside = base / "fora.ogg"
      writeFile(outside, "FORA")
      when defined(posix):
        createSymlink(outside, root / "link.ogg")
        let f = FakeUpload()
        let a = newAdapter(f)
        check a.sendMedia(42, root / "link.ogg", "legenda", "",
                          mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains("fora.ogg")
        check not f.calls[0].body.contains(".ogg")
        check fileExists(outside)
        check readFile(outside) == "FORA"
      else:
        discard

    test "the neutral notice carries no path, name or extension":
      let base = freshDir("confine-notice")
      defer: removeDir(base)
      let root = base / "paddock"
      createDir(root)
      let outside = base / "pasta" / "segredo.opus"
      createDir(base / "pasta")
      writeFile(outside, "X")
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, outside, "legenda", "", mediaRoot = root).isOk
      let notice = f.calls[^1].body
      check notice.contains(NeutralFallback)
      check not notice.contains("/")
      check not notice.contains("segredo")
      check not notice.contains(".opus")

    test "the constructed adapter owns an upload transport":
      let f = FakeUpload()
      let a = newAdapter(f)
      check not a.uploadHttp.post.isNil
      let defaulted = newTelegramAdapter("TOK", getTempDir() / "donkey_tg_ids_default.tsv")
      check not defaulted.uploadHttp.post.isNil

  suite "TelegramAdapter — local media read through the validated descriptor":

    test "a regular file inside the paddock is uploaded with the same bytes":
      let root = freshDir("fd-bytes")
      defer: removeDir(root)
      let path = root / "nota.ogg"
      let payload = "OGGDATA-0123456789-abcdef"
      writeFile(path, payload)
      let f = FakeUpload()
      let a = newAdapter(f)
      check a.sendMedia(42, path, "legenda", "", mediaRoot = root).isOk
      check f.calls.len == 1
      check f.calls[0].url.endsWith("/sendVoice")
      check f.calls[0].body.contains(payload)

    test "a symlink swapped in after validation becomes neutral text":
      when defined(posix):
        let base = freshDir("fd-swap")
        defer: removeDir(base)
        let root = base / "paddock"
        createDir(root)
        let outside = base / "fora" / "segredo.ogg"
        createDir(base / "fora")
        writeFile(outside, "SEGREDO")
        let path = root / "nota.ogg"
        writeFile(path, "DENTRO")
        let f = FakeUpload()
        var a = newAdapter(f)
        ## A gcsafe callback cannot capture a GC'd local; the target travels in a
        ## threadvar, like the adapter's own mutable state.
        raceSwapTarget = outside
        a.mediaValidatedHook = proc (canonical: string) {.gcsafe, raises: [].} =
          ## The race: the name validated a moment ago now points outside.
          try:
            removeFile(canonical)
            createSymlink(raceSwapTarget, canonical)
          except CatchableError:
            discard
        check a.sendMedia(42, path, "legenda", "", mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains("segredo")
        check not f.calls[0].body.contains(".ogg")
        check not f.calls[0].body.contains(root)
        check not f.calls[0].body.contains(base)
        check fileExists(outside)
        check readFile(outside) == "SEGREDO"

    test "a file swapped for a FIFO after validation becomes neutral text":
      when defined(posix):
        let root = freshDir("fd-swap-fifo")
        defer: removeDir(root)
        let path = root / "nota.ogg"
        writeFile(path, "DENTRO")
        let f = FakeUpload()
        var a = newAdapter(f)
        a.mediaValidatedHook = proc (canonical: string) {.gcsafe, raises: [].} =
          try:
            removeFile(canonical)
            discard mkfifo(canonical.cstring, Mode(0o600))
          except CatchableError:
            discard
        check a.sendMedia(42, path, "legenda", "", mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains("nota.ogg")
        check not f.calls[0].body.contains(root)

    test "a path swapped for a directory after validation becomes neutral text":
      when defined(posix):
        let base = freshDir("fd-swap-dir")
        defer: removeDir(base)
        let root = base / "paddock"
        createDir(root)
        let outsideDir = base / "outside"
        createDir(outsideDir)
        writeFile(outsideDir / "nota.ogg", "FORA")
        let path = root / "nota.ogg"
        writeFile(path, "DENTRO")
        let f = FakeUpload()
        var a = newAdapter(f)
        a.mediaValidatedHook = proc (canonical: string) {.gcsafe, raises: [].} =
          try:
            removeFile(canonical)
            createDir(canonical)
          except CatchableError:
            discard
        check a.sendMedia(42, path, "legenda", "", mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains(root)
        check fileExists(outsideDir / "nota.ogg")
        check readFile(outsideDir / "nota.ogg") == "FORA"

    test "a symlinked parent swapped in after validation is never followed":
      ## F4: the file is validated, then read by name again. Swapping a
      ## *directory* on the way to it is the same race one level up, and
      ## O_NOFOLLOW on the last component alone does not stop it.
      when defined(posix):
        let base = freshDir("fd-swap-parent")
        defer: removeDir(base)
        let root = base / "paddock"
        let outside = base / "fora"
        createDir(root)
        createDir(outside)
        writeFile(outside / "nota.ogg", "FORA-SECRETO")
        let path = root / "nota.ogg"
        writeFile(path, "DENTRO")
        let f = FakeUpload()
        var a = newAdapter(f)
        raceSwapRoot = root
        raceSwapOutside = outside
        a.mediaValidatedHook = proc (canonical: string) {.gcsafe, raises: [].} =
          ## The validated name is now reached through a link instead.
          try:
            moveDir(raceSwapRoot, raceSwapRoot & "-saved")
            createSymlink(raceSwapOutside, raceSwapRoot)
          except CatchableError:
            discard
        check a.sendMedia(42, path, "legenda", "", mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains("FORA-SECRETO")
        check readFile(outside / "nota.ogg") == "FORA-SECRETO"

    test "a link on an intermediate directory is never followed":
      ## F4: the file sits under a directory that is a link. Validation resolves
      ## the link, but anything that re-opens the name afterwards would follow it
      ## into the target, so the read must go through a descriptor opened
      ## component by component.
      when defined(posix):
        let base = freshDir("fd-link-mid")
        defer: removeDir(base)
        let root = base / "paddock"
        let outside = base / "fora"
        createDir(root)
        createDir(outside)
        writeFile(outside / "nota.ogg", "FORA-SECRETO")
        createSymlink(outside, root / "grupo")
        let f = FakeUpload()
        let a = newAdapter(f)
        check a.sendMedia(42, root / "grupo" / "nota.ogg", "legenda", "",
                          mediaRoot = root).isOk
        check f.calls.len == 1
        check f.calls[0].url.endsWith("/sendMessage")
        check f.calls[0].body.contains(NeutralFallback)
        check not f.calls[0].body.contains("FORA-SECRETO")
        check readFile(outside / "nota.ogg") == "FORA-SECRETO"

when isMainModule:
  runTests()
