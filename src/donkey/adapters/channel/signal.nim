## SignalAdapter — ChannelPort for signal-cli via JSON-RPC over Unix socket.
##
## signal-cli daemon mode:
##   signal-cli --socket /run/signal-cli/socket daemon
##
## JSON-RPC transport: one short-lived Unix socket connection per request.
## Each rpcCall opens the socket, sends one JSON line, reads one JSON line,
## then closes — matching the signal-cli "socket" mode wire protocol.
##
## Receiving: receive() polls the daemon with a JSON-RPC "receive" call.
##   The daemon returns all queued messages as a result array.
##
## Sending: send() calls JSON-RPC "send" with recipient and message.

import std/[json, net, os]
import std/posix
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/signal_pure
import ../identity/identity_resolver

export identity_resolver

const
  SignalDefaultSock* = "/run/signal-cli/socket"
  SignalMaxChars*    = 2000  ## practical per-message length limit

# ── JSON-RPC transport ─────────────────────────────────────────────────────────

proc applySocketTimeouts(sock: Socket; seconds: int = 10) =
  var tv: Timeval
  tv.tv_sec = Time(seconds)
  tv.tv_usec = Suseconds(0)
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO, addr tv, SockLen(sizeof(tv)))
  discard setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO, addr tv, SockLen(sizeof(tv)))

proc rpcCall(sockPath, meth: string;
             params: JsonNode): Result[JsonNode, string] =
  ## Opens a connection to the signal-cli Unix socket, sends a JSON-RPC request
  ## (one JSON line), reads the response (one JSON line), then closes.
  ## Returns the `result` field of the response on success.
  if not fileExists(sockPath):
    return err("SignalAdapter: socket not found: " & sockPath)
  let req = %* {"jsonrpc": "2.0", "method": meth, "id": 1, "params": params}
  try:
    let sock = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
    defer: sock.close()
    sock.connectUnix(sockPath)
    applySocketTimeouts(sock)
    sock.send($req & "\n")
    let line = sock.recvLine(timeout = 10_000)
    if line.len == 0:
      return err("SignalAdapter: empty response from daemon")
    let resp = parseJson(line)
    let errNode = resp.getOrDefault("error")
    if errNode != nil and errNode.kind != JNull:
      return err("signal-cli error: " & errNode.getOrDefault("message").getStr($errNode))
    ok(resp.getOrDefault("result"))
  except CatchableError as e:
    err(e.msg)

# ── SignalAdapter ──────────────────────────────────────────────────────────────

type
  SignalAdapter* = object
    sockPath*:  string          ## path to signal-cli Unix socket
    account*:   string          ## sender's phone number (E.164), e.g. "+1234567890"
    resolver*:  IdentityResolver

# ── ChannelPort implementation ─────────────────────────────────────────────────

proc receive*(a: var SignalAdapter): Result[seq[InboundMessage], string] =
  ## Polls signal-cli for pending messages via JSON-RPC "receive".
  ## Returns all queued InboundMessages; ignores non-data-message envelopes.
  let items = ? rpcCall(a.sockPath, "receive", newJObject())
  let results = items |> parseEnvelopes
  var msgs: seq[InboundMessage]
  for r in results:
    let userId = a.resolver.resolve(ckSignal, r.rawId)
    msgs.add(r.toInbound(userId))
  ok(msgs)

proc send*(a: SignalAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's Signal phone number.
  ## Splits messages longer than SignalMaxChars into multiple sends.
  let phone = a.resolver.reverseChannel(msg.userId, ckSignal)
  if phone.len == 0:
    return err("SignalAdapter.send: no Signal ID for user " & $msg.userId)
  for chunk in splitChunks(msg.text, SignalMaxChars):
    discard ? rpcCall(a.sockPath, "send", %* {
      "recipient": [phone],
      "message":   chunk,
    })
  ok()

proc sendReturnId*(a: SignalAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends the first chunk and returns the response timestamp as message id.
  let phone = a.resolver.reverseChannel(msg.userId, ckSignal)
  if phone.len == 0:
    return err("SignalAdapter.sendReturnId: no Signal ID for " & $msg.userId)
  let chunk = splitChunks(msg.text, SignalMaxChars)[0]
  let resp = ? rpcCall(a.sockPath, "send", %* {
    "recipient": [phone],
    "message":   chunk,
  })
  try:
    ok($resp.getOrDefault("timestamp").getBiggestInt(0))
  except CatchableError as e:
    err(e.msg)

proc editMessage*(a: SignalAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Signal does not support message editing. Returns ok silently.
  discard userId
  discard msgId
  discard text
  ok()

proc ack*(a: SignalAdapter; channelId: string) =
  ## No explicit ack needed for Signal; daemon manages delivery receipts.
  discard

# ── Constructor ────────────────────────────────────────────────────────────────

proc newSignalAdapter*(account:      string;
                       identityPath: string;
                       sockPath      = SignalDefaultSock): SignalAdapter =
  SignalAdapter(
    sockPath:  sockPath,
    account:   account,
    resolver:  newIdentityResolver(identityPath),
  )
