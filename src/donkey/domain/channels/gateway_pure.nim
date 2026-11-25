## gateway_pure.nim — what the Discord-family gateways (Discord, QQ
## official) share, as pure functions: heartbeat liveness and the shape of a
## close-code decision. Each platform keeps its own close-code table.


type
  HeartbeatStep* = enum
    hbWait    ## not due yet
    hbSend    ## due, and the previous heartbeat was acknowledged
    hbZombie  ## due, and the previous one never was: the link is dead

  CloseAction* = enum
    caResume      ## reconnect and RESUME the same session
    caNewSession  ## reconnect with a fresh IDENTIFY (the session is gone)
    caStop        ## reconnecting cannot help (bad token, disallowed intents)

func heartbeatStep*(nowMs, lastBeatMs: int64; intervalMs: int;
                    awaitingAck: bool): HeartbeatStep =
  ## Discord: a heartbeat not ACKed by the time the next one is due means a
  ## zombie connection, to be closed and resumed. Without this a half-open
  ## socket only ever times out its reads and the bot goes silent.
  if nowMs - lastBeatMs < intervalMs: hbWait
  elif awaitingAck: hbZombie
  else: hbSend

func closeCodeOf*(payload: string): int =
  ## A WebSocket close frame starts with a big-endian status code.
  if payload.len < 2: return 0
  (ord(payload[0]) shl 8) or ord(payload[1])

