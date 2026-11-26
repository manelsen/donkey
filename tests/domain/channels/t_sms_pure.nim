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

when isMainModule:
  runTests()
