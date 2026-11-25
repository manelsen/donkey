## gateway_family.nim — the Discord-family gateway protocol.
##
## Discord and QQ official speak the same gateway protocol: a hello with
## the heartbeat interval, IDENTIFY or RESUME, heartbeats that must be
## acknowledged, dispatches with a sequence number, and the opcodes 1
## (beat now), 7 (reconnect), 9 (invalid session) and 11 (ack). This module
## is that protocol once, for persistent_socket's protocol functions to call;
## each platform keeps what is its own: the URL, the identify payload, the
## close-code table and what a dispatch means.

import std/[json, random]
import ../../core/log
import ../../core/pipeops
import ../../domain/channels/discord_pure
import ../channel/ws_client
import ./persistent_socket

export discord_pure.CloseAction, discord_pure.HeartbeatStep

type
  FamilyState* = object
    ## Lives on the connection thread, across reconnections: a session that
    ## survives a drop is resumed from its last sequence.
    heartbeatMs*: int
    lastBeatMs*:  int64
    lastSeq*:     int
    sessionId*:   string
    resumeUrl*:   string
    awaitingAck*: bool

  FamilyEventKind* = enum
    fkNone       ## handled here (ack, beat now, hello)
    fkReady      ## READY: the session is new; `data` is its payload
    fkResumed    ## RESUMED: the gap was replayed
    fkDispatch   ## any other dispatch: `name` and `data`
    fkStep       ## the connection must change course: `step`

  FamilyEvent* = object
    kind*: FamilyEventKind
    name*: string
    data*: JsonNode
    step*: SessionStep

  CloseTable* = proc(code: int): CloseAction {.nimcall, gcsafe, noSideEffect, raises: [].}
    ## A platform's close codes: which stop, which drop the session.

proc resetSession*(state: var FamilyState) =
  state.sessionId = ""
  state.resumeUrl = ""
  state.lastSeq = 0

proc sendHeartbeat*(ws: WsClient; state: var FamilyState; nowMs: int64) =
  let payload = if state.lastSeq > 0: $state.lastSeq else: "null"
  ws.sendFrame("{\"op\":1,\"d\":" & payload & "}")
  state.lastBeatMs = nowMs
  state.awaitingAck = true

proc randomJitter*(intervalMs: int; capMs = 5_000): int =
  ## The first beat's delay: random, at most the interval or `capMs`.
  if capMs <= 0: 0 else: rand(min(intervalMs, capMs))

proc familyHello*(ws: WsClient; state: var FamilyState; nowMs: int64;
                  jitterCapMs: int; defaultIntervalMs = 41_250): Result[void, string] =
  ## Reads the hello and schedules the first heartbeat after a random delay
  ## of at most `jitterCapMs` (0: due at once). The tick sends it: the thread
  ## never sleeps here, so a stop is not held up.
  let hello = ws.recvFrame(timeoutMs = 10_000)
  if hello.isErr:
    return err("hello not received: " & hello.error)
  try:
    let j = parseJson(hello.get.data)
    if j.getOrDefault("op").getInt(-1) != 10:
      return err("expected hello (op 10), got " & hello.get.data)
    state.heartbeatMs = j{"d", "heartbeat_interval"}.getInt(defaultIntervalMs)
  except CatchableError as e:
    return err("hello unreadable: " & e.msg)
  state.awaitingAck = false
  state.lastBeatMs = nowMs - state.heartbeatMs +
                     randomJitter(state.heartbeatMs, jitterCapMs)
  ok()

proc familyIdentify*(ws: WsClient; state: FamilyState; identify: JsonNode;
                     resumeToken: string) =
  ## RESUME a known session from its last sequence; IDENTIFY otherwise.
  if state.sessionId.len > 0:
    ws.sendFrame($ %* {"op": 6, "d": {"token": resumeToken,
                                      "session_id": state.sessionId,
                                      "seq": state.lastSeq}})
  else:
    ws.sendFrame($ %* {"op": 2, "d": identify})

proc familyTick*(ws: WsClient; state: var FamilyState; nowMs: int64;
                 log: Logger; label: string): SessionStep =
  ## A heartbeat not acknowledged by the time the next one is due means a
  ## dead (half-open) link: reconnect and resume.
  case heartbeatStep(nowMs, state.lastBeatMs, state.heartbeatMs, state.awaitingAck)
  of hbWait: ssKeep
  of hbSend:
    sendHeartbeat(ws, state, nowMs)
    ssKeep
  of hbZombie:
    log.warn(label & ": heartbeat not acknowledged; reconnecting to resume")
    ssReconnect

func stepEvent(step: SessionStep): FamilyEvent =
  FamilyEvent(kind: fkStep, step: step)

proc familyFrame*(ws: WsClient; state: var FamilyState; frame: WsFrame;
                  closeTable: CloseTable; log: Logger; label: string): FamilyEvent =
  ## Reads one frame. What only the platform can judge (READY, dispatches)
  ## comes back as an event; the rest is handled here.
  if frame.opcode == WsOpcodeClose:
    let code = closeCodeOf(frame.data)
    case closeTable(code)
    of caStop:
      log.error(label & ": gateway closed with " & $code &
                " (credentials or intents rejected); not reconnecting")
      return stepEvent(ssStop)
    of caNewSession:
      log.warn(label & ": gateway closed with " & $code & "; starting a new session")
      state.resetSession()
      return stepEvent(ssReconnect)
    of caResume:
      log.warn(label & ": gateway closed (" & $code & ")")
      return stepEvent(ssReconnect)
  if frame.opcode != WsOpcodeText:
    return FamilyEvent(kind: fkNone)
  let j =
    try: parseJson(frame.data)
    except CatchableError as e:
      log.warn(label & ": unreadable frame: " & e.msg)
      return FamilyEvent(kind: fkNone)
  case j.getOrDefault("op").getInt(-1)
  of 0:
    let s = j.getOrDefault("s").getInt(0)
    if s > 0: state.lastSeq = s
    let name = j.getOrDefault("t").getStr("")
    let data = j.getOrDefault("d")
    case name
    of "READY":
      state.sessionId = data{"session_id"}.getStr("")
      let resume = data{"resume_gateway_url"}.getStr("")
      if resume.len > 0: state.resumeUrl = resume
      FamilyEvent(kind: fkReady, name: name, data: data)
    of "RESUMED":
      FamilyEvent(kind: fkResumed, name: name, data: data)
    else:
      FamilyEvent(kind: fkDispatch, name: name, data: data)
  of 1:
    sendHeartbeat(ws, state, epochMs())
    FamilyEvent(kind: fkNone)
  of 7:
    log.info(label & ": reconnect requested (op 7)")
    stepEvent(ssReconnect)
  of 9:
    ## The platforms ask for a 1-5 s wait before a new IDENTIFY. The socket
    ## pauses at least `reconnectMinMs` before any reconnection, and both
    ## gateways run on `defaultSocketPolicy` (1 s; pinned by a test).
    log.warn(label & ": invalid session (op 9)")
    if not j.getOrDefault("d").getBool(false):
      state.resetSession()
    stepEvent(ssReconnect)
  of 11:
    state.awaitingAck = false
    FamilyEvent(kind: fkNone)
  else:
    FamilyEvent(kind: fkNone)
