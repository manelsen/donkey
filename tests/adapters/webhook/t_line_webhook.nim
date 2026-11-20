## LINE webhook route — US-005.
##
## No sockets: the pure request→response handler is exercised directly with a
## real `X-Line-Signature` (base64 HMAC-SHA256 over the raw body) and the
## dispatched event is observed through the adapter's module-level queue.
##
## Contract:
##   - a route with an empty secret is indistinguishable from an absent one;
##   - a valid signature enqueues exactly the parsed events and answers 200;
##   - the console "Verify" (`{"events":[]}`) answers 200 without enqueuing;
##   - wrong signature 403, method ≠ POST 405, oversized 413, bad JSON 400.

import std/[json, os, strutils, tables, unittest]
import donkey/adapters/channel/line
import donkey/adapters/webhook/webhook_receiver
import donkey/domain/channels/line_policy

const
  TestSecret = "test-line-channel-secret"
  Fixtures   = "tests/fixtures/line"
  LineTmp    = "/tmp/donkey_line_webhook_tests"

proc mkReq(httpMethod, path: string;
           body = "";
           headers: openArray[(string, string)] = []): WebhookRequest =
  var h = initTable[string, string]()
  for (k, v) in headers:
    h[k.toLowerAscii()] = v
  WebhookRequest(httpMethod: httpMethod, path: path, headers: h, body: body)

func sign(body: string; secret = TestSecret): string =
  hmacSha256Base64(secret, body)

proc newAdapter(): LineAdapter =
  createDir(LineTmp)
  newLineAdapter("test-channel-access-token", LineTmp / "ids.tsv",
                 apiBase = "https://line.test")

proc drainQueue(a: var LineAdapter) =
  while a.tryRecvEvent()[0]:
    discard

# The route can only enqueue into an open queue (startup opens it before the
# receiver starts accepting payloads).
openQueue()

proc runTests*() =
  suite "LINE webhook route — acceptance":

    test "a valid signature returns 200 and enqueues the event":
      var ln = newAdapter()
      drainQueue(ln)

      let body = readFile(Fixtures / "webhook_text.json")
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))

      check resp.status == 200
      check resp.body == "ok"
      let (hasEvent, event) = ln.tryRecvEvent()
      check hasEvent
      check event.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T1"
      check event.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check event.text == "Hello from LINE"
      check not ln.tryRecvEvent()[0]  ## exactly one event

    test "the console Verify payload is 200 and enqueues nothing":
      var ln = newAdapter()
      drainQueue(ln)

      let body = readFile(Fixtures / "webhook_empty_events.json")
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))

      check resp.status == 200
      check resp.body == "ok"
      check not ln.tryRecvEvent()[0]

    test "DingTalk and LINE share the same ingress path constants":
      check LinePath == "/webhook/line"
      check LineSignatureHeader == "X-Line-Signature"

  suite "LINE webhook route — rejections":

    test "a wrong signature is 403 and enqueues nothing":
      var ln = newAdapter()
      drainQueue(ln)

      let body = readFile(Fixtures / "webhook_text.json")
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body, "another-secret"))]))

      check resp.status == 403
      check not ln.tryRecvEvent()[0]

    test "a missing signature is 403":
      let body = readFile(Fixtures / "webhook_text.json")
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body))
      check resp.status == 403

    test "an empty secret makes the route look absent":
      let body = readFile(Fixtures / "webhook_text.json")
      let resp = handleWebhookRequest(
        WebhookConfig(),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))
      check resp.status == 404

    test "a non-POST method is 405":
      let body = readFile(Fixtures / "webhook_text.json")
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("GET", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))
      check resp.status == 405

    test "a body over 1 MiB is 413":
      let body = repeat('a', 1024 * 1024 + 1)
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))
      check resp.status == 413

    test "malformed JSON with a valid signature is 400":
      let body = """{"events": ["""
      let resp = handleWebhookRequest(
        WebhookConfig(lineChannelSecret: TestSecret),
        mkReq("POST", LinePath, body,
              headers = [(LineSignatureHeader, sign(body))]))
      check resp.status == 400

when isMainModule:
  runTests()
