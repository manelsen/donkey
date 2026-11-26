## sms — SMS through Twilio (second round, front 1).
##
## The webhook route (`/webhook/sms`) queues a message only after its
## X-Twilio-Signature checks out; the daemon loop drains the queue
## (sms_runtime). A person is their phone number, so a reply goes to the
## number it answers, or to the person's own number, from the configured
## Twilio number, through the Messages resource.

import std/strutils
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/sms_pure
import ../../infra/event_queue
import ../../ports/channel
import ../../ports/http
import ../../ports/link_codes
import ../http/std_http
import ../identity/identity_resolver

export sms_pure

const
  SmsQueueCapacity* = 256
  SmsTimeoutSec = 30
  SmsSeenCapacity* = 512
    ## Twilio retries a webhook it saw time out; older ids are not expected.

var gSmsEvents* = initEventQueue[InboundSms]("sms", capacity = SmsQueueCapacity)

proc pushSms*(m: InboundSms): bool {.discardable.} =
  ## False when the queue is full: the route answers 503 and Twilio retries.
  gSmsEvents.push(m)

proc tryRecvSms*(): (bool, InboundSms) =
  gSmsEvents.tryTake()

type
  SmsState = ref object
    seen: seq[string]   ## message ids, oldest first

  SmsAdapter* = object
    accountSid*:  string
    authToken:    string
    fromNumber*:  string
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    http:         HttpRuntimePort
    state:        SmsState
    configError*: string

proc markSeen*(a: SmsAdapter; sid: string): bool =
  ## True the first time a message id comes; false for a redelivery.
  if sid.len == 0: return true
  if sid in a.state.seen: return false
  a.state.seen.add sid
  if a.state.seen.len > SmsSeenCapacity:
    a.state.seen.delete(0)
  true

proc send*(a: SmsAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text only (channel_capability): media is refused, not dropped.
  if a.configError.len > 0:
    return err("SMS: " & a.configError)
  if msg.mediaUrl.len > 0 or msg.keyboard.len > 0:
    return err("SMS: only text is supported")
  if msg.text.strip.len == 0:
    return ok()
  let to =
    if msg.replyTo.strip.len > 0: msg.replyTo.strip
    else: a.resolver.reverseChannel(msg.userId, ckSms)
  if to.len == 0:
    return err("SMS: no number known for user " & $msg.userId)
  for piece in splitForSms(msg.text):
    let resp = ? a.http.post(messagesUrl(a.accountSid), sendForm(to, a.fromNumber, piece),
      @[("Content-Type", "application/x-www-form-urlencoded"),
        ("Authorization", basicAuth(a.accountSid, a.authToken))])
    if resp.status notin 200 .. 299:
      return err("SMS: send status " & $resp.status)
  ok()

const SmsMaxDownloadBytes* = 25 * 1024 * 1024

func headerValue(headers: seq[HttpHeader]; name: string): string =
  for (k, v) in headers:
    if k.toLowerAscii == name.toLowerAscii: return v
  ""

proc downloadFile*(a: SmsAdapter; url: string): Result[FileDownload, string] =
  ## An MMS media item (E9.3): only this account's media URL is fetched with
  ## the account's credentials, without following redirects; a redirect to
  ## Twilio's media storage is then followed without them.
  if a.configError.len > 0:
    return err("SMS: " & a.configError)
  if not twilioMediaUrl(url, a.accountSid):
    return err("SMS: not this account's media")
  var resp = ? a.http.getNoRedirect(url, @[("Authorization", basicAuth(a.accountSid, a.authToken))])
  if resp.status in 300 .. 399:
    let location = headerValue(resp.headers, "Location")
    if not twilioMediaRedirect(location):
      return err("SMS: media redirected outside Twilio's storage")
    resp = ? a.http.get(location, @[])
  if resp.status != 200:
    return err("SMS: media download status " & $resp.status)
  if resp.body.len > SmsMaxDownloadBytes:
    return err("SMS: media larger than " & $(SmsMaxDownloadBytes div (1024 * 1024)) & " MB")
  var data = newSeq[byte](resp.body.len)
  for i in 0 ..< resp.body.len: data[i] = byte(resp.body[i])
  ok(FileDownload(fileName: "mms", fileSize: data.len.int64, data: data))

proc newSmsAdapter*(accountSid, authToken, fromNumber, identityPath: string;
                    http: HttpRuntimePort = HttpRuntimePort()): SmsAdapter =
  ## `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and `TWILIO_FROM_NUMBER` from the
  ## environment snapshot. Missing settings do not stop the daemon: the
  ## adapter records why and every send fails with it.
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = SmsTimeoutSec,
      allowlist = @["api.twilio.com", "media.twiliocdn.com", "mms.twiliocdn.com",
                    "s3-external-1.amazonaws.com"],   ## MMS media (E9.3)
      retryNonIdempotent = false,
      retryConflict = false).toRuntimePort()
  result = SmsAdapter(
    accountSid: accountSid.strip, authToken: authToken.strip,
    fromNumber: fromNumber.strip, resolver: newIdentityResolver(identityPath),
    http: transport, state: SmsState(),
    configError:
      if accountSid.strip.len == 0 or authToken.strip.len == 0 or fromNumber.strip.len == 0:
        "TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM_NUMBER are required"
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
