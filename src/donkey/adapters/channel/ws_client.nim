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

import std/[base64, net, random, strutils]

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

proc recvExact(sock: Socket; n: int): string =
  ## Reads exactly n bytes (blocking, no timeout). Raises IOError on close.
  if n == 0: return ""
  result = newString(n)
  var pos = 0
  while pos < n:
    var tmp = newString(n - pos)
    let got = sock.recv(tmp, n - pos)
    if got <= 0:
      raise newException(IOError, "WebSocket: connection closed")
    copyMem(addr result[pos], unsafeAddr tmp[0], got)
    pos += got

proc wsConnect*(host: string; port: Port; path: string; useTls = true): WsClient =
  ## Opens a (TLS) WebSocket connection and completes HTTP upgrade.
  randomize()
  var sock = newSocket()
  if useTls:
    ## CVerifyNone for now. Switch to CVerifyPeer + caFile= for hardening.
    var ctx = newContext(verifyMode = CVerifyNone)
    ctx.wrapSocket(sock)
  sock.connect(host, port)

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

  let statusLine = sock.recvLine()
  if "101" notin statusLine:
    raise newException(IOError, "WebSocket upgrade rejected: " & statusLine)
  var hline = sock.recvLine()
  while hline.len > 2:
    hline = sock.recvLine()

  WsClient(sock: sock)

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

proc recvFrame*(ws: WsClient; timeoutMs = 1000): WsFrame =
  ## Receives one WebSocket frame (server → client, unmasked).
  ## Waits up to timeoutMs for the first byte; raises TimeoutError if none.
  ## Subsequent bytes of the same frame are read without timeout.
  var firstByte = newString(1)
  let n0 = ws.sock.recv(firstByte, 1, timeoutMs)
  if n0 <= 0:
    raise newException(IOError, "WebSocket: connection closed on header byte 0")

  var secondByte = newString(1)
  let n1 = ws.sock.recv(secondByte, 1)
  if n1 <= 0:
    raise newException(IOError, "WebSocket: connection closed on header byte 1")

  let b0 = byte(firstByte[0])
  let b1 = byte(secondByte[0])
  let opcode = b0 and 0x0F
  let masked  = (b1 and 0x80) != 0

  var length = int(b1 and 0x7F)
  if length == 126:
    let ext = ws.sock.recvExact(2)
    length = (int(byte(ext[0])) shl 8) or int(byte(ext[1]))
  elif length == 127:
    let ext = ws.sock.recvExact(8)
    length = 0
    for i in 4..<8:
      length = (length shl 8) or int(byte(ext[i]))

  var maskKey: array[4, byte]
  if masked:
    let mk = ws.sock.recvExact(4)
    for i in 0..<4: maskKey[i] = byte(mk[i])

  var data = ws.sock.recvExact(length)
  if masked:
    for i in 0..<data.len:
      data[i] = char(int(byte(data[i])) xor int(maskKey[i mod 4]))

  WsFrame(opcode: opcode, data: data)

proc wsClose*(ws: WsClient) =
  try: ws.sendFrame("", WsOpcodeClose)
  except: discard
  try: ws.sock.close()
  except: discard
