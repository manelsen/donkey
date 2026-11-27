## ntfy_pure — ntfy as a channel (E13.1), the pure half.
##
## ntfy (ntfy.sh or a server of one's own) publishes and serves messages on a
## topic over plain HTTP. Donkey polls the topic (`/json?poll=1&since=…`)
## and publishes its answers there, tagged `donkey` so it never reads its own
## messages back. A topic has no notion of who wrote: the topic is the
## secret, and the person it belongs to links it like any channel.

import std/[json, strutils]

const
  NtfyMaxMessageBytes* = 4096   ## ntfy's default message limit
  NtfyOwnTag* = "donkey"

type NtfyMessage* = object
  id*, text*: string

func validNtfyTopic*(topic: string): bool =
  topic.len in 1 .. 64 and topic.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-'})

func base(url: string): string = url.strip(leading = false, chars = {'/'})

func publishUrl*(url, topic: string): string = base(url) & "/" & topic

func pollUrl*(url, topic, since: string): string =
  ## `since`: the last message id seen; at start, the last ten seconds.
  base(url) & "/" & topic & "/json?poll=1&since=" & (if since.len > 0: since else: "10s")

func publishHeaders*(token: string): seq[(string, string)] =
  result = @[("Title", "Donkey"), ("Tags", NtfyOwnTag), ("Markdown", "yes")]
  if token.len > 0: result.add(("Authorization", "Bearer " & token))

proc parseNtfyLines*(body: string): seq[NtfyMessage] =
  ## The messages a person wrote; Donkey's own (tagged) and the stream's
  ## other events (open, keepalive) are left out, and so is what is not JSON.
  for line in body.splitLines:
    if line.strip.len == 0: continue
    try:
      let j = parseJson(line)
      if j{"event"}.getStr != "message": continue
      var own = false
      for t in j{"tags"}.getElems:
        if t.getStr == NtfyOwnTag: own = true
      if own: continue
      let text = j{"message"}.getStr
      if text.strip.len == 0: continue
      result.add NtfyMessage(id: j{"id"}.getStr, text: text)
    except CatchableError:
      discard

proc lastNtfyId*(body: string): string =
  ## The id of the last line with one, whatever its event: the next poll
  ## starts after everything already seen.
  for line in body.splitLines:
    if line.strip.len == 0: continue
    try:
      let id = parseJson(line){"id"}.getStr
      if id.len > 0: result = id
    except CatchableError:
      discard

func ntfyPieces*(text: string): seq[string] =
  ## In pieces ntfy accepts, cut at a line break when there is one.
  var rest = text
  while rest.len > 0:
    if rest.len <= NtfyMaxMessageBytes:
      result.add rest
      break
    var cut = rest.rfind('\n', 0, NtfyMaxMessageBytes - 1)
    if cut <= 0: cut = NtfyMaxMessageBytes
    else: inc cut
    ## never split a UTF-8 sequence; bytes that are not UTF-8 are cut anyway
    let limit = cut
    while cut > 0 and cut < rest.len and (ord(rest[cut]) and 0xC0) == 0x80: dec cut
    if cut == 0: cut = limit
    result.add rest[0 ..< cut]
    rest = rest[cut .. ^1]
