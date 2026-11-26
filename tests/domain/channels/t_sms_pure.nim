## SMS through Twilio, the pure half (second round, front 1): the form a
## webhook delivers, its X-Twilio-Signature, and the message to send.
## Formats from Twilio's "Webhooks security" and "Messages resource" docs; the
## expected signature was computed with Python's hmac, independently.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/sms_pure

const
  Url = "https://donkey.example.com/webhook/sms"
  Form = "MessageSid=SM123&From=%2B5511999990000&To=%2B5511888880000" &
         "&Body=oi%2C+tudo+bem%3F&NumMedia=0"

proc runTests*() =
  suite "sms — reading a webhook":

    test "the form is decoded, + as space":
      let p = parseForm(Form)
      check p.get("Body") == "oi, tudo bem?"
      check p.get("From") == "+5511999990000"
      check p.get("Missing") == ""

    test "the signature is the URL plus the sorted parameters, HMAC-SHA1 in base64":
      check twilioSignature("tok-twilio", Url, parseForm(Form)) == "3E1lPcihlqDU0C4kFeaW0MPFyd0="

    test "a valid signature passes; a wrong token, URL or body does not":
      let p = parseForm(Form)
      check signatureValid("tok-twilio", Url, p, "3E1lPcihlqDU0C4kFeaW0MPFyd0=")
      check not signatureValid("other", Url, p, "3E1lPcihlqDU0C4kFeaW0MPFyd0=")
      check not signatureValid("tok-twilio", Url & "x", p, "3E1lPcihlqDU0C4kFeaW0MPFyd0=")
      check not signatureValid("tok-twilio", Url, parseForm(Form & "&Extra=1"),
                               "3E1lPcihlqDU0C4kFeaW0MPFyd0=")
      check not signatureValid("tok-twilio", Url, p, "")

    test "an inbound message: who sent it, to which number, the text":
      let m = parseInboundSms(parseForm(Form)).get
      check m.sid == "SM123" and m.sender == "+5511999990000"
      check m.receiver == "+5511888880000" and m.text == "oi, tudo bem?"
      check m.mediaCount == 0
      check parseInboundSms(parseForm("Body=oi")).isErr   ## no sender
      check parseInboundSms(parseForm("From=%2B1&Body=oi")).isErr   ## no id: a retry could not be told apart

    test "media without text is kept, with its count (answered as unsupported)":
      let m = parseInboundSms(parseForm("MessageSid=SM9&From=%2B1&To=%2B2&Body=&NumMedia=2")).get
      check m.text == "" and m.mediaCount == 2

  suite "sms — sending":

    test "the Messages URL is the account's":
      check messagesUrl("AC1") == "https://api.twilio.com/2010-04-01/Accounts/AC1/Messages.json"

    test "the send form carries to, from and body, URL-encoded":
      let f = parseForm(sendForm("+5511999990000", "+5511888880000", "olá & tchau"))
      check f.get("To") == "+5511999990000" and f.get("From") == "+5511888880000"
      check f.get("Body") == "olá & tchau"

    test "basic auth is the account and its token":
      check basicAuth("AC1", "tok") == "Basic QUMxOnRvaw=="

    test "a long reply is split under Twilio's body limit":
      let parts = splitForSms("a".repeat(SmsBodyChars + 1))
      check parts.len == 2 and parts[0].len <= SmsBodyChars

    test "the empty answer Twilio expects":
      check "<Response" in EmptyTwiml

const MediaBase = "https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/"

proc runMediaTests*() =
  suite "sms — MMS in (E9.3)":
    test "each media item comes with its URL and type":
      let p = parseForm("MessageSid=MM1&From=%2B5511999990000&Body=&NumMedia=2" &
        "&MediaUrl0=" & MediaBase & "ME1&MediaContentType0=image%2Fjpeg" &
        "&MediaUrl1=" & MediaBase & "ME2&MediaContentType1=audio%2Fogg")
      let m = parseInboundSms(p).get
      check m.media == @[(MediaBase & "ME1", "image/jpeg"), (MediaBase & "ME2", "audio/ogg")]

    test "only the account's own media URLs are fetched":
      check twilioMediaUrl(MediaBase & "ME1", "AC1")
      check not twilioMediaUrl(MediaBase & "ME1", "AC2")             ## another account
      check not twilioMediaUrl("https://evil.example/2010-04-01/Accounts/AC1/Messages/M/Media/X", "AC1")
      check not twilioMediaUrl("http://api.twilio.com/2010-04-01/Accounts/AC1/Messages/M/Media/X", "AC1")
      ## the exact shape: no query, fragment, encoding or extra segment
      check not twilioMediaUrl(MediaBase & "ME1?x=/Media/", "AC1")
      check not twilioMediaUrl(MediaBase & "ME1#frag", "AC1")
      check not twilioMediaUrl("https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/%2e%2e/Media/X", "AC1")
      check not twilioMediaUrl("https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/x/Media/ME1", "AC1")

    test "a redirect is followed only to Twilio's media storage":
      check twilioMediaRedirect("https://media.twiliocdn.com/AC1/abc")
      check twilioMediaRedirect("https://s3-external-1.amazonaws.com/media.twiliocdn.com/AC1/abc")
      check not twilioMediaRedirect("https://evil.example/abc")
      check not twilioMediaRedirect("http://media.twiliocdn.com/AC1/abc")

when isMainModule:
  runTests()
  runMediaTests()
