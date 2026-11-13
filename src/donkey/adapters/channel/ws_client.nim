## ws_client — minimal synchronous WebSocket client (RFC 6455).
##
## Uses std/net (OpenSSL, already a project dependency via ssl define).
## Designed for dedicated OS thread use — all operations are blocking.
## Implements text, ping/pong, and close frames.
##
## Timeout model:
##   recvFrame(ws, timeoutMs) raises TimeoutError if the first byte of a new
##   frame does not arrive within timeoutMs. Subsequent bytes of the same
##   frame are read without a timeout (data is already in flight).

import std/[base64, monotimes, net, random, strutils, times]
when defined(posix):
  import std/posix

const
  WsOpcodeText*  = byte(0x1)
  WsOpcodeBin*   = byte(0x2)
  WsOpcodeClose* = byte(0x8)
  WsOpcodePing*  = byte(0x9)
  WsOpcodePong*  = byte(0xA)

type
  WsFrame* = object
    opcode*: byte
    data*:   string

  WsClient* = object
    sock*: Socket

proc frameRemainingMs(deadline: MonoTime): int =
  let remaining = inMilliseconds(deadline - getMonoTime())
  if remaining <= 0:
    raise newException(IOError, "WebSocket: frame deadline exceeded")
  remaining

proc recvExact(sock: Socket; n: int; deadline: MonoTime): string =
  ## Reads exactly n bytes before the frame deadline. Raises IOError on close.
  if n == 0: return ""
  result = newString(n)
  var pos = 0
  while pos < n:
    var tmp = newString(n - pos)
    var got: int
    try:
      got = sock.recv(tmp, n - pos, frameRemainingMs(deadline))
    except TimeoutError:
      raise newException(IOError, "WebSocket: truncated frame")
    if got <= 0:
      raise newException(IOError, "WebSocket: connection closed")
    copyMem(addr result[pos], unsafeAddr tmp[0], got)
    pos += got

proc applySocketTimeout(sock: Socket; timeoutMs: int) =
  ## Bounds TLS and HTTP upgrade I/O as well as frame reads.
  when defined(posix):
    var tv: posix.Timeval
    tv.tv_sec = posix.Time(timeoutMs div 1000)
    tv.tv_usec = posix.Suseconds((timeoutMs mod 1000) * 1000)
    discard posix.setsockopt(sock.getFd, posix.SOL_SOCKET, posix.SO_RCVTIMEO,
                             addr tv, posix.SockLen(sizeof(tv)))
    discard posix.setsockopt(sock.getFd, posix.SOL_SOCKET, posix.SO_SNDTIMEO,
                             addr tv, posix.SockLen(sizeof(tv)))

proc wsConnect*(host: string; port: Port; path: string;
                useTls = true; verifyTls = true;
                timeoutMs = 10_000;
                onSocket: proc(sock: Socket) {.gcsafe.} = nil): WsClient =
  ## Opens a (TLS) WebSocket connection and completes the HTTP upgrade.
  ## `verifyTls` checks the server certificate and sends SNI. The total
  ## establishment time is bounded by `timeoutMs`.
  randomize()
  var sock = newSocket()
  if onSocket != nil:
    onSocket(sock)
  try:
    sock.connect(host, port, timeoutMs)
    applySocketTimeout(sock, timeoutMs)
    if useTls:
      let mode = if verifyTls: CVerifyPeer else: CVerifyNone
      let ctx = newContext(verifyMode = mode)
      ctx.wrapConnectedSocket(sock, handshakeAsClient, host)

    var keyBytes: array[16, byte]
    for i in 0..<16: keyBytes[i] = byte(rand(255))
    let key = encode(keyBytes)

    let req = "GET " & path & " HTTP/1.1\r\n" &
              "Host: " & host & "\r\n" &
              "Upgrade: websocket\r\n" &
              "Connection: Upgrade\r\n" &
              "Sec-WebSocket-Key: " & key & "\r\n" &
              "Sec-WebSocket-Version: 13\r\n" &
              "\r\n"
    sock.send(req)

    let deadline = getMonoTime() + initDuration(milliseconds = max(1, timeoutMs))
    let statusLine = sock.recvLine(frameRemainingMs(deadline))
    if "101" notin statusLine:
      raise newException(IOError, "WebSocket upgrade rejected: " & statusLine)
    var hline = sock.recvLine(frameRemainingMs(deadline))
    while hline.len > 2:
      hline = sock.recvLine(frameRemainingMs(deadline))

    WsClient(sock: sock)
  except CatchableError:
    try: sock.close() except CatchableError: discard
    raise

proc sendFrame*(ws: WsClient; data: string; opcode = WsOpcodeText) =
  ## Sends one masked WebSocket frame (client → server MUST be masked per RFC 6455).
  var mask: array[4, byte]
  for i in 0..<4: mask[i] = byte(rand(255))

  var frame = ""
  frame.add(char(0x80 or int(opcode)))

  let n = data.len
  if n < 126:
    frame.add(char(0x80 or n))
  elif n < 65536:
    frame.add(char(0xFE))
    frame.add(char(n shr 8))
    frame.add(char(n and 0xFF))
  else:
    frame.add(char(0xFF))
    for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
      frame.add(char((n shr shift) and 0xFF))

  for b in mask: frame.add(char(b))
  for i, c in data:
    frame.add(char(int(c) xor int(mask[i mod 4])))

  ws.sock.send(frame)

proc recvFrame*(ws: WsClient; timeoutMs = 1000;
                frameTimeoutMs = 10_000;
                maxPayloadBytes = 0): WsFrame =
  ## Receives one WebSocket frame (server → client, unmasked).
  ## Waits up to timeoutMs for the first byte; raises TimeoutError if none.
  ## Once a frame starts, it must finish within frameTimeoutMs.
  ## `maxPayloadBytes > 0` rejects the frame before allocating its payload.
  var firstByte = newString(1)
  let n0 = ws.sock.recv(firstByte, 1, timeoutMs)
  if n0 <= 0:
    raise newException(IOError, "WebSocket: connection closed on header byte 0")
  let deadline = getMonoTime() +
    initDuration(milliseconds = max(1, frameTimeoutMs))

  var secondByte = newString(1)
  var n1: int
  try:
    n1 = ws.sock.recv(secondByte, 1, frameRemainingMs(deadline))
  except TimeoutError:
    raise newException(IOError, "WebSocket: truncated frame")
  if n1 <= 0:
    raise newException(IOError, "WebSocket: connection closed on header byte 1")

  let b0 = byte(firstByte[0])
  let b1 = byte(secondByte[0])
  let opcode = b0 and 0x0F
  let masked  = (b1 and 0x80) != 0

  var length = int(b1 and 0x7F)
  if length == 126:
    let ext = ws.sock.recvExact(2, deadline)
    length = (int(byte(ext[0])) shl 8) or int(byte(ext[1]))
  elif length == 127:
    let ext = ws.sock.recvExact(8, deadline)
    for i in 0..<4:
      if byte(ext[i]) != 0:
        raise newException(IOError, "WebSocket: frame payload exceeds 4 GiB")
    length = 0
    for i in 4..<8:
      length = (length shl 8) or int(byte(ext[i]))

  if length < 0 or (maxPayloadBytes > 0 and length > maxPayloadBytes):
    raise newException(IOError,
      "WebSocket: frame payload exceeds " & $maxPayloadBytes & " bytes")

  var maskKey: array[4, byte]
  if masked:
    let mk = ws.sock.recvExact(4, deadline)
    for i in 0..<4: maskKey[i] = byte(mk[i])

  var data = ws.sock.recvExact(length, deadline)
  if masked:
    for i in 0..<data.len:
      data[i] = char(int(byte(data[i])) xor int(maskKey[i mod 4]))

  WsFrame(opcode: opcode, data: data)

proc wsClose*(ws: WsClient) =
  try: ws.sendFrame("", WsOpcodeClose)
  except CatchableError: discard
  try: ws.sock.close()
  except IOError: discard
