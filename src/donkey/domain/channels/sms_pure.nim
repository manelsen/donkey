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
    media*: seq[(string, string)]   ## MMS (E9.3): each item's URL and content type

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
  var items: seq[(string, string)]
  for i in 0 ..< min(media, 10):   ## Twilio sends at most 10
    let url = p.get("MediaUrl" & $i).strip
    if url.len > 0: items.add (url, p.get("MediaContentType" & $i).strip)
  ok(InboundSms(sid: p.get("MessageSid"), sender: sender,
                receiver: p.get("To").strip, text: p.get("Body"),
                mediaCount: media, media: items))

func sidSegment(s: string): bool =
  if s.len == 0 or s.len > 64: return false
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9'}: return false
  true

func twilioMediaUrl*(url, accountSid: string): bool =
  ## A media item of this account's messages, and nothing else, is fetched
  ## with the account's credentials: exactly
  ## `https://api.twilio.com/2010-04-01/Accounts/<account>/Messages/<sid>/Media/<sid>`,
  ## with no query, fragment, encoding or other segment.
  if not sidSegment(accountSid): return false
  let prefix = "https://api.twilio.com/2010-04-01/Accounts/" & accountSid & "/Messages/"
  if not url.startsWith(prefix): return false
  let parts = url[prefix.len .. ^1].split('/')
  parts.len == 3 and sidSegment(parts[0]) and parts[1] == "Media" and sidSegment(parts[2])

func twilioMediaRedirect*(location: string): bool =
  ## Where Twilio's media URL may redirect: its own media storage, over
  ## HTTPS. Followed without the credentials.
  location.startsWith("https://media.twiliocdn.com/") or
    location.startsWith("https://mms.twiliocdn.com/") or
    location.startsWith("https://s3-external-1.amazonaws.com/media.twiliocdn.com/")

func messagesUrl*(accountSid: string): string =
  "https://api.twilio.com/2010-04-01/Accounts/" & accountSid & "/Messages.json"

func sendForm*(to, sender, body: string): string =
  encodeQuery({"To": to, "From": sender, "Body": body})

func basicAuth*(accountSid, authToken: string): string =
  "Basic " & encode(accountSid & ":" & authToken)

func splitForSms*(text: string): seq[string] =
  splitChunks(text, SmsBodyChars)
