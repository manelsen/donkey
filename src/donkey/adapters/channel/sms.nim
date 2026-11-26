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

proc newSmsAdapter*(accountSid, authToken, fromNumber, identityPath: string;
                    http: HttpRuntimePort = HttpRuntimePort()): SmsAdapter =
  ## `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and `TWILIO_FROM_NUMBER` from the
  ## environment snapshot. Missing settings do not stop the daemon: the
  ## adapter records why and every send fails with it.
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = SmsTimeoutSec,
      allowlist = @["api.twilio.com"], retryNonIdempotent = false,
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
