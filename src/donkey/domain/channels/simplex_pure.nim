## simplex_pure — SimpleX as a channel (E13.2), the pure half.
##
## Donkey talks to a `simplex-chat` CLI running as a local WebSocket server
## (`simplex-chat -p 5225`, bots API): a command is `{"corrId","cmd"}`, an
## answer carries the corrId back, an event has none. A person is a direct
## contact of the bot (`chatInfo.contact.contactId`, local to that CLI's
## database); SimpleX has no global user id, so the contact is linked to a
## person by pairing or `/continue`. Groups are not served.

import std/[json, strutils]
import ../../core/pipeops

const
  SimplexMaxMessageBytes* = 15_000
  SimplexDefaultHost = "127.0.0.1"
  SimplexDefaultPort = 5225

type
  SimplexMessage* = object
    contactId*: int64
    name*, text*: string
    itemId*: int64

  SimplexEvent* = object
    messages*: seq[SimplexMessage]
    unread*: seq[tuple[contactId: int64, name, kind: string, itemId: int64]]
      ## direct messages that are not text (an image, a file): answered with a note

proc parseSimplexEvent*(frame: string): SimplexEvent =
  ## The direct text messages a contact sent, from a `newChatItems` event;
  ## the bot's own messages, groups, other events and command answers bring
  ## nothing.
  try:
    let j = parseJson(frame)
    if j.hasKey("corrId"): return
    let resp = j{"resp"}
    if resp.isNil or resp{"type"}.getStr != "newChatItems": return
    for item in resp{"chatItems"}.getElems:
      let info = item{"chatInfo"}
      if info{"type"}.getStr != "direct": continue
      let chatItem = item{"chatItem"}
      if chatItem{"chatDir"}{"type"}.getStr != "directRcv": continue
      let content = chatItem{"content"}
      if content{"type"}.getStr != "rcvMsgContent": continue
      let contact = info{"contact"}
      let msg = content{"msgContent"}
      if msg{"type"}.getStr == "text":
        let text = msg{"text"}.getStr
        if text.strip.len > 0:
          result.messages.add SimplexMessage(contactId: contact{"contactId"}.getBiggestInt,
            name: contact{"localDisplayName"}.getStr, text: text,
            itemId: chatItem{"meta"}{"itemId"}.getBiggestInt)
      else:
        result.unread.add((contactId: contact{"contactId"}.getBiggestInt,
                           name: contact{"localDisplayName"}.getStr, kind: msg{"type"}.getStr,
                           itemId: chatItem{"meta"}{"itemId"}.getBiggestInt))
  except CatchableError:
    discard

proc sendCommand*(corrId: string; contactId: int64; text: string): string =
  ## `APISendMessages` to a direct contact (`@<contactId>`).
  let composed = %* [{"msgContent": {"type": "text", "text": text}, "mentions": newJObject()}]
  $(%* {"corrId": corrId, "cmd": "/_send @" & $contactId & " json " & $composed})

func parseSimplexUrl*(url: string): Result[tuple[host: string, port: int], string] =
  ## `SIMPLEX_URL`: the CLI on this machine (it has no authentication, so it
  ## must not be reached over a network). Default ws://127.0.0.1:5225.
  let raw = url.strip
  if raw.len == 0: return ok((host: SimplexDefaultHost, port: SimplexDefaultPort))
  if not raw.startsWith("ws://"):
    return err("SIMPLEX_URL must be ws://127.0.0.1:<port> (the local simplex-chat)")
  let rest = raw["ws://".len .. ^1].strip(leading = false, chars = {'/'})
  let colon = rest.rfind(':')
  if colon <= 0: return err("SIMPLEX_URL needs a port")
  let host = rest[0 ..< colon]
  if host notin ["127.0.0.1", "localhost", "[::1]"]:
    return err("SIMPLEX_URL must be on this machine: simplex-chat has no authentication")
  var port = 0
  for c in rest[colon + 1 .. ^1]:
    if c notin {'0'..'9'}: return err("SIMPLEX_URL: not a port")
    port = port * 10 + (ord(c) - ord('0'))
    if port > 65535: return err("SIMPLEX_URL: not a port")
  if port == 0: return err("SIMPLEX_URL: not a port")
  ok((host: host, port: port))

func simplexPieces*(text: string): seq[string] =
  var rest = text
  while rest.len > SimplexMaxMessageBytes:
    var cut = rest.rfind('\n', 0, SimplexMaxMessageBytes - 1)
    if cut <= 0: cut = SimplexMaxMessageBytes
    else: inc cut
    let limit = cut
    while cut > 0 and cut < rest.len and (ord(rest[cut]) and 0xC0) == 0x80: dec cut
    if cut == 0: cut = limit
    result.add rest[0 ..< cut]
    rest = rest[cut .. ^1]
  if rest.len > 0: result.add rest
