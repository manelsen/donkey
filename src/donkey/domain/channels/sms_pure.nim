## sms_pure — SMS through Twilio, the pure half (second round, front 1).
##
## Twilio delivers an inbound SMS as a form POST to the webhook and signs it:
## `X-Twilio-Signature` is base64(HMAC-SHA1(auth token, URL + every POST
## parameter, sorted by name, as name then value)), the URL being exactly
## the one configured in the console. Replies go through the Messages
## resource, a form POST with basic auth. Formats from Twilio's "Webhooks
## security" and "Messages resource" documentation.

import std/[algorithm, base64, strutils, uri]
import ../../core/pipeops
import ../../core/security/webhook_auth

const
  SmsBodyChars* = 1_600
    ## The Messages resource refuses a longer Body.
  EmptyTwiml* = """<?xml version="1.0" encoding="UTF-8"?><Response></Response>"""
    ## The webhook's answer: nothing now, the reply goes through the API.

type
  FormParams* = seq[(string, string)]

  InboundSms* = object
    sid*, sender*, receiver*, text*: string
    mediaCount*: int

proc parseForm*(body: string): FormParams =
  ## `application/x-www-form-urlencoded`, `+` as space.
  for (k, v) in decodeQuery(body):
    result.add (k, v)

func get*(p: FormParams; name: string): string =
  for (k, v) in p:
    if k == name: return v

func twilioSignature*(authToken, url: string; params: FormParams): string =
  var sorted = params
  sorted.sort(proc(a, b: (string, string)): int =
    let byName = cmp(a[0], b[0])
    if byName != 0: byName else: cmp(a[1], b[1]))
  var data = url
  for (k, v) in sorted:
    data.add k
    data.add v
  hmacSha1Base64(authToken, data)

func signatureValid*(authToken, url: string; params: FormParams;
                     signature: string): bool =
  signature.len > 0 and authToken.len > 0 and
    safeEquals(twilioSignature(authToken, url, params), signature)

func parseInboundSms*(p: FormParams): Result[InboundSms, string] =
  let sender = p.get("From").strip
  if sender.len == 0:
    return err("no From")
  if p.get("MessageSid").strip.len == 0:
    return err("no MessageSid")   ## Twilio always sends it; without it a retry is a new turn
  var media = 0
  try: media = parseInt(p.get("NumMedia").strip)
  except ValueError: media = 0
  ok(InboundSms(sid: p.get("MessageSid"), sender: sender,
                receiver: p.get("To").strip, text: p.get("Body"),
                mediaCount: media))

func messagesUrl*(accountSid: string): string =
  "https://api.twilio.com/2010-04-01/Accounts/" & accountSid & "/Messages.json"

func sendForm*(to, sender, body: string): string =
  encodeQuery({"To": to, "From": sender, "Body": body})

func basicAuth*(accountSid, authToken: string): string =
  "Basic " & encode(accountSid & ":" & authToken)

func splitForSms*(text: string): seq[string] =
  splitChunks(text, SmsBodyChars)
