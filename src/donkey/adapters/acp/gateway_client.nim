## gateway_client — `donkey acp`'s HTTP to the daemon's gateway (E10.1).
##
## Pairing (`/v1/acp/pair`, `/v1/acp/pair/poll`) and one streamed turn
## (`/v1/acp/chat/completions`), on the Chronos HTTP client (bearssl for
## https). The turn's body is read line by line as it arrives, so the editor
## sees the answer grow; cancelling the turn closes the connection, and the
## daemon drops its late answer.

import std/[json, strutils]
import chronos
import chronos/apps/http/httpclient
import ../../core/pipeops
import ../../app/acp_runtime

const
  ConnectTimeout = chronos.seconds(15)
  HeadersTimeout = chronos.seconds(120)
  MaxReplyBytes = 64 * 1024
  MaxLineBytes = 1024 * 1024

type GatewayClient* = object
  base: string

proc newGatewayClient*(base: string): GatewayClient =
  GatewayClient(base: base.strip(leading = false, chars = {'/'}))

proc exchange(c: GatewayClient; path, body, token: string;
              onLine: LineSink): Future[TurnReply] {.async: (raises: [CancelledError]).} =
  ## One POST. With `onLine`, a 200 body is streamed to it line by line;
  ## anything else is read whole (capped) into `body`.
  let session = HttpSessionRef.new(flags = {HttpClientFlag.NoAutomaticRedirect},
                                   connectTimeout = ConnectTimeout,
                                   headersTimeout = HeadersTimeout)
  var request: HttpClientRequestRef = nil
  var response: HttpClientResponseRef = nil
  try:
    let address = session.getAddress(c.base & path).valueOr:
      return TurnReply(status: 0, error: "invalid gateway URL: " & c.base & path)
    var headers: seq[(string, string)] = @[("Content-Type", "application/json")]
    if token.len > 0: headers.add(("Authorization", "Bearer " & token))
    request = HttpClientRequestRef.new(session, address, MethodPost, headers = headers,
                                       body = body.toOpenArrayByte(0, body.high))
    response = await request.send()
    if response.status == 200 and onLine != nil:
      ## Once the stream began, a failure cuts it: still a 200, with why, so
      ## the editor is not told the daemon was unreachable.
      let reader = response.getBodyReader()
      var cut = ""
      try:
        while not reader.atEof():
          let line = await reader.readLine(limit = MaxLineBytes, sep = "\n")
          if line.len >= MaxLineBytes:
            ## readLine hands over the first `limit` bytes of a longer line
            ## and goes on: the event would arrive broken, so stop and say so.
            cut = "a line of the stream is longer than " & $(MaxLineBytes div 1024) & " KiB"
            break
          onLine(line.strip(leading = false, chars = {'\r'}))
      except CancelledError as e:
        raise e
      except CatchableError as e:
        cut = e.msg
      finally:
        await reader.closeWait()
      return TurnReply(status: 200, error: cut)
    let bytes = await response.getBodyBytes(MaxReplyBytes)
    var text = newString(bytes.len)
    for i, b in bytes: text[i] = char(b)
    return TurnReply(status: response.status, body: text)
  except CancelledError as e:
    raise e
  except CatchableError as e:
    return TurnReply(status: 0, error: e.msg)
  finally:
    if response != nil: await response.closeWait()
    if request != nil: await request.closeWait()
    await session.closeWait()

func failure(reply: TurnReply): string =
  if reply.status == 0: reply.error
  else: "HTTP " & $reply.status & (if reply.body.len > 0: ": " & reply.body.strip else: "")

proc pair*(c: GatewayClient; name: string): Future[Result[GatewayPairing, string]] {.
    async: (raises: []).} =
  let reply = await noCancel c.exchange("/v1/acp/pair", $(%* {"name": name}), "", nil)
  if reply.status != 200: return err(reply.failure)
  try:
    let j = parseJson(reply.body)
    let pairing = GatewayPairing(code: j{"code"}.getStr, secret: j{"pairing"}.getStr)
    if pairing.code.len == 0 or pairing.secret.len == 0:
      return err("the gateway's pairing answer has no code")
    return ok(pairing)
  except CatchableError as e:
    return err("the gateway's pairing answer is unreadable: " & e.msg)

proc poll*(c: GatewayClient; secret: string): Future[Result[GatewayPoll, string]] {.
    async: (raises: []).} =
  let reply = await noCancel c.exchange("/v1/acp/pair/poll", $(%* {"pairing": secret}), "", nil)
  case reply.status
  of 202: return ok(GatewayPoll(state: gpPending))
  of 404: return ok(GatewayPoll(state: gpUnknown))
  of 200:
    try:
      let token = parseJson(reply.body){"token"}.getStr
      if token.len == 0: return err("the gateway's answer has no credential")
      return ok(GatewayPoll(state: gpPaired, token: token))
    except CatchableError as e:
      return err("the gateway's answer is unreadable: " & e.msg)
  else:
    return err(reply.failure)

proc turn*(c: GatewayClient; token, text: string; onLine: LineSink): Future[TurnReply] {.
    async: (raises: [CancelledError]).} =
  ## The body of /v1/chat/completions; the gateway ignores `user` here (the
  ## credential says who the person is).
  let body = $(%* {"user": "editor", "stream": true,
                   "messages": [{"role": "user", "content": text}]})
  return await c.exchange("/v1/acp/chat/completions", body, token, onLine)

proc approve*(c: GatewayClient; token, callback: string): Future[Result[string, string]] {.
    async: (raises: []).} =
  ## The person's answer to an approval asked in the editor (E10.4).
  let reply = await noCancel c.exchange("/v1/acp/approve", $(%* {"callback": callback}),
                                        token, nil)
  if reply.status != 200: return err(reply.failure)
  try:
    return ok(parseJson(reply.body){"result"}.getStr)
  except CatchableError:
    return ok("")
