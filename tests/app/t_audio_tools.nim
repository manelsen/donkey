## Audio tool tests: transcription upload and speech file, with a fake HTTP.

import std/[json, os, strutils, unittest]
import donkey/app/tools/audio_tools
import donkey/core/pipeops
import donkey/domain/media/audio_pure
import donkey/ports/http

type
  Capture = ref object
    url:     string
    body:    string
    headers: seq[HttpHeader]
    status:  int
    response: string

proc fakeHttp(cap: Capture): HttpRuntimePort =
  HttpRuntimePort(
    post: proc (url, body: string; headers: seq[HttpHeader] = @[]):
              Result[HttpResponse, string] {.gcsafe.} =
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: cap.status, body: cap.response)),
  )

proc headerValue(cap: Capture; name: string): string =
  for (key, value) in cap.headers:
    if key.toLowerAscii() == name.toLowerAscii():
      return value
  ""

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_audio_" & tag & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

suite "transcribe_audio":

  test "uploads the file and returns the transcript":
    let dir = freshDir("stt-ok")
    defer: removeDir(dir)
    let path = dir / "nota.mp3"
    writeFile(path, "AUDIODATA")
    let cap = Capture(status: 200, response: """{"text": "olá mundo"}""")
    let got = performTranscribe(path, fakeHttp(cap),
      apiKey = "secret", endpoint = "https://stt.test/v1/audio/transcriptions",
      model = "whisper-1")
    check got == "olá mundo"
    check cap.url == "https://stt.test/v1/audio/transcriptions"
    check headerValue(cap, "Authorization") == "Bearer secret"
    check headerValue(cap, "Content-Type").startsWith("multipart/form-data; boundary=")
    check cap.body.contains("""name="model"""")
    check cap.body.contains("whisper-1")
    check cap.body.contains("""filename="nota.mp3"""")
    check cap.body.contains("Content-Type: audio/mpeg")
    check cap.body.contains("AUDIODATA")

  test "sends the optional language and prompt fields":
    let dir = freshDir("stt-fields")
    defer: removeDir(dir)
    let path = dir / "nota.ogg"
    writeFile(path, "OGG")
    let cap = Capture(status: 200, response: """{"text": "ok"}""")
    discard performTranscribe(path, fakeHttp(cap), language = "pt",
                              prompt = "nomes próprios", apiKey = "k",
                              endpoint = "https://stt.test")
    check cap.body.contains("""name="language"""")
    check cap.body.contains("\r\n\r\npt\r\n")
    check cap.body.contains("""name="prompt"""")
    check cap.body.contains("nomes próprios")

  test "a missing key fails before any request":
    let dir = freshDir("stt-nokey")
    defer: removeDir(dir)
    let path = dir / "nota.mp3"
    writeFile(path, "X")
    let cap = Capture()
    let got = performTranscribe(path, fakeHttp(cap), apiKey = "")
    check got.startsWith("Error:")
    check cap.url == ""

  test "an unsupported extension fails before any request":
    let dir = freshDir("stt-ext")
    defer: removeDir(dir)
    let path = dir / "nota.txt"
    writeFile(path, "X")
    let cap = Capture()
    let got = performTranscribe(path, fakeHttp(cap), apiKey = "k")
    check got.contains("unsupported audio")
    check cap.url == ""

  test "an oversized file fails before any request":
    let dir = freshDir("stt-size")
    defer: removeDir(dir)
    let path = dir / "nota.mp3"
    writeFile(path, "12345")
    let cap = Capture()
    let got = performTranscribe(path, fakeHttp(cap), apiKey = "k", maxBytes = 4)
    check got.contains("too large")
    check cap.url == ""

  test "an HTTP failure is reported":
    let dir = freshDir("stt-http")
    defer: removeDir(dir)
    let path = dir / "nota.mp3"
    writeFile(path, "X")
    let cap = Capture(status: 500, response: """{"error":{"message":"boom"}}""")
    let got = performTranscribe(path, fakeHttp(cap), apiKey = "k")
    check got.startsWith("Error:")
    check got.contains("500")

suite "text_to_speech":

  test "writes the returned audio under attachments":
    let dir = freshDir("tts-ok")
    defer: removeDir(dir)
    let cap = Capture(status: 200, response: "MP3BYTES")
    let res = performSpeech("olá", dir, fakeHttp(cap), apiKey = "k",
      endpoint = "https://tts.test/v1/audio/speech", model = "tts-1",
      voice = "alloy", format = "mp3")
    check res.isOk
    let rel = res.get()
    check rel.startsWith("attachments/tts-")
    check rel.endsWith(".mp3")
    check readFile(dir / rel) == "MP3BYTES"
    check cap.url == "https://tts.test/v1/audio/speech"
    check headerValue(cap, "Authorization") == "Bearer k"
    let body = parseJson(cap.body)
    check body["input"].getStr() == "olá"
    check body["voice"].getStr() == "alloy"
    check body["model"].getStr() == "tts-1"
    check body["response_format"].getStr() == "mp3"

  test "an empty text is rejected":
    let dir = freshDir("tts-empty")
    defer: removeDir(dir)
    let cap = Capture()
    check performSpeech("   ", dir, fakeHttp(cap), apiKey = "k").isErr
    check cap.url == ""

  test "a missing key is rejected":
    let dir = freshDir("tts-nokey")
    defer: removeDir(dir)
    let cap = Capture()
    check performSpeech("olá", dir, fakeHttp(cap), apiKey = "").isErr
    check cap.url == ""

  test "an unsupported format is rejected":
    let dir = freshDir("tts-format")
    defer: removeDir(dir)
    let cap = Capture()
    check performSpeech("olá", dir, fakeHttp(cap), apiKey = "k",
                        format = "exe").isErr
    check cap.url == ""

  test "an HTTP failure does not leave a file":
    let dir = freshDir("tts-http")
    defer: removeDir(dir)
    let cap = Capture(status: 429, response: "slow down")
    let res = performSpeech("olá", dir, fakeHttp(cap), apiKey = "k")
    check res.isErr
    check res.error.contains("429")
    check not dirExists(dir / "attachments")
