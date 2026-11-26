## `/webhook/sms` on the shared receiver (second round, front 1): only a form
## Twilio signed for the configured URL reaches the queue; the answer is an
## empty TwiML, since the reply goes through the Messages API.

import std/[strutils, tables, unittest]
import donkey/adapters/channel/sms
import donkey/adapters/webhook/webhook_ingress
import donkey/adapters/webhook/webhook_receiver

const
  Url = "https://donkey.example.com/webhook/sms"
  Form = "MessageSid=SM123&From=%2B5511999990000&To=%2B5511888880000" &
         "&Body=oi%2C+tudo+bem%3F&NumMedia=0"
  Signature = "3E1lPcihlqDU0C4kFeaW0MPFyd0="   ## computed with Python's hmac

proc request(signature: string; body = Form; httpMethod = "POST"): WebhookRequest =
  var headers = initTable[string, string]()
  if signature.len > 0:
    headers["x-twilio-signature"] = signature
  WebhookRequest(httpMethod: httpMethod, path: SmsPath, headers: headers, body: body)

proc drain(): int =
  while tryRecvSms()[0]: inc result

let cfg = WebhookConfig(twilioAuthToken: "tok-twilio", twilioWebhookUrl: Url)

proc runTests*() =
  suite "webhook sms":
    setup:
      discard drain()

    test "a signed message is queued and answered with an empty TwiML":
      let r = handleWebhookRequest(cfg, request(Signature))
      check r.status == 200
      check r.contentType == "text/xml" and "<Response" in r.body
      check drain() == 1

    test "a missing or wrong signature is refused and nothing is queued":
      check handleWebhookRequest(cfg, request("")).status == 403
      check handleWebhookRequest(cfg, request("AAAA" & Signature[4 .. ^1])).status == 403
      check handleWebhookRequest(cfg, request(Signature, Form & "&Body2=x")).status == 403
      check drain() == 0

    test "the route is closed without the token or the public URL":
      check handleWebhookRequest(WebhookConfig(twilioAuthToken: "tok-twilio"),
                                 request(Signature)).status == 404
      check handleWebhookRequest(WebhookConfig(twilioWebhookUrl: Url),
                                 request(Signature)).status == 404
      check anyRouteConfigured(cfg)

    test "only POST":
      check handleWebhookRequest(cfg, request(Signature, httpMethod = "GET")).status == 405

when isMainModule:
  runTests()
