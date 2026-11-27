## bluebubbles_pure — BlueBubbles (iMessage) as a channel (E13.3), the pure half.
##
## A BlueBubbles Server on the operator's Mac bridges iMessage over a REST
## API, authenticated by the server password in the query string. Its
## webhooks carry no signature, so Donkey does not take them: it polls the
## message query (`POST /api/v1/message/query`, after the newest message
## seen) and sends with `POST /api/v1/message/text`. A person is an iMessage
## address (phone or e-mail) in a one-to-one chat (`<service>;-;<address>`);
## group chats (`;+;`) are not served.

import std/[json, strutils, uri]
import ../../core/pipeops

type
  BlueMessage* = object
    guid*, address*, chatGuid*, text*: string
    attachments*: int

  BluePage* = object
    messages*: seq[BlueMessage]
    newest*: int64     ## the newest dateCreated in the page (ms), 0 if none

func validServerUrl*(url: string): bool =
  ## The password travels in the URL: https, or http to this machine only.
  if url.startsWith("https://"): return true
  for local in ["http://127.0.0.1", "http://localhost", "http://[::1]"]:
    if url.startsWith(local): return true
  false

func apiUrl*(server, path, password: string): string =
  server.strip(leading = false, chars = {'/'}) & path & "?password=" &
    encodeUrl(password, usePlus = false)

proc queryBody*(after: int64): string =
  $(%* {"with": ["chat", "handle"], "after": after, "sort": "ASC", "limit": 100})

proc sendTextBody*(chatGuid, text, tempGuid: string): string =
  $(%* {"chatGuid": chatGuid, "message": text, "tempGuid": tempGuid, "method": "apple-script"})

func chatFor*(target: string): string =
  ## A chat guid as is; an address becomes its one-to-one chat (`any` lets
  ## the server pick iMessage or SMS).
  if ";-;" in target or ";+;" in target: target else: "any;-;" & target

proc parseMessagePage*(body: string): Result[BluePage, string] =
  ## People's one-to-one messages, oldest first; Donkey's own (`isFromMe`) and
  ## group chats are left out, but count for where the next query starts.
  var page = BluePage()
  try:
    let j = parseJson(body)
    let status = j{"status"}.getInt(0)
    if status != 200:
      return err("BlueBubbles: " & $status & " " & j{"message"}.getStr)
    for m in j{"data"}.getElems:
      let created = m{"dateCreated"}.getBiggestInt
      if created > page.newest: page.newest = created
      if m{"isFromMe"}.getBool(false): continue
      let address = m{"handle"}{"address"}.getStr
      if address.len == 0: continue
      var chat = ""
      let chats = m{"chats"}
      if not chats.isNil and chats.len > 0: chat = chats[0]{"guid"}.getStr
      if ";+;" in chat: continue          ## a group
      if chat.len == 0: chat = chatFor(address)
      let attachments = m{"attachments"}
      page.messages.add BlueMessage(guid: m{"guid"}.getStr, address: address, chatGuid: chat,
        text: m{"text"}.getStr,
        attachments: if attachments.isNil or attachments.kind != JArray: 0 else: attachments.len)
    ok(page)
  except CatchableError as e:
    err("BlueBubbles: an answer that is not JSON: " & e.msg)
