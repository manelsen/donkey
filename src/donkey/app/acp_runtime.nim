## acp_runtime — `donkey acp`, the editor's side of Donkey (E10.1–E10.3).
##
## An editor (Zed and others) starts `donkey acp` and speaks the Agent Client
## Protocol on its stdin and stdout. Each prompt becomes one turn on the
## daemon's gateway (`/v1/acp/chat/completions`), as the person the editor
## was paired with; the gateway's stream comes back as `session/update`
## notifications: pieces of the answer and the tools as they run.
##
## The first prompt without a credential pairs the editor (E10.2): the code
## is shown in the chat, the person confirms it with `/editor <code>` on a
## channel where Donkey knows them, and the turn goes on once the credential
## arrives. Every port is injected: the shell (`donkey acp`) wires stdio, the
## credential file and the HTTP client; tests pass fakes.

import std/[json, strutils]
import chronos
import ../core/pipeops
import ../domain/acp/acp_pure

const
  PairingPollMs* = 2000
  MaxPollFailures = 5

type
  LineSink* = proc(line: string) {.gcsafe, raises: [].}

  GatewayPairing* = object
    code*, secret*: string

  GatewayPollState* = enum
    gpPending, gpPaired, gpUnknown

  GatewayPoll* = object
    state*: GatewayPollState
    token*: string

  TurnReply* = object
    status*: int      ## 0 = the gateway was not reached
    body*: string     ## a refusal's body
    error*: string    ## why it was not reached

  AcpPorts* = object
    write*: proc(line: string) {.gcsafe, raises: [].}
      ## One JSON-RPC message to the editor (stdout).
    loadToken*: proc(): string {.gcsafe, raises: [].}
    saveToken*: proc(token: string): Result[void, string] {.gcsafe, raises: [].}
      ## "" forgets it.
    pair*: proc(name: string): Future[Result[GatewayPairing, string]] {.async: (raises: []).}
    poll*: proc(secret: string): Future[Result[GatewayPoll, string]] {.async: (raises: []).}
    turn*: proc(token, text: string; onLine: LineSink): Future[TurnReply] {.
             async: (raises: [CancelledError]).}
      ## Streams the turn's SSE lines to `onLine`; cancelling it closes the
      ## stream, and the daemon drops the turn's late answer.
    nap*: proc(ms: int): Future[void] {.async: (raises: [CancelledError]).}

  AcpRuntime* = ref object
    ports: AcpPorts
    version: string
    editorName: string
    sessions: seq[string]
    current: Future[void].Raising([])
    currentSession: string

  TurnState = ref object
    openTool: string
    finish: string
    tools: int

proc newAcpRuntime*(ports: AcpPorts; version: string): AcpRuntime =
  AcpRuntime(ports: ports, version: version, editorName: "editor")

proc say(rt: AcpRuntime; sessionId, text: string) =
  rt.ports.write(messageChunk(sessionId, text))

proc pairFor(rt: AcpRuntime; sessionId: string): Future[string] {.
    async: (raises: [CancelledError]).} =
  ## Pairs this editor; "" when it did not happen (the person was told why).
  let started = await rt.ports.pair(rt.editorName)
  if started.isErr:
    rt.say(sessionId, "Não consegui pedir o pareamento ao Donkey: " & started.error)
    return ""
  rt.say(sessionId, "Este editor ainda não está conectado a você. Mande `/editor " &
    started.get.code & "` numa conversa com o Donkey onde ele já te conhece " &
    "(Telegram, Slack, Teams…). O código vale 10 minutos; fico esperando aqui.\n\n")
  var failures = 0
  while true:
    await rt.ports.nap(PairingPollMs)
    let polled = await rt.ports.poll(started.get.secret)
    if polled.isErr:
      inc failures
      if failures >= MaxPollFailures:
        rt.say(sessionId, "Perdi o contato com o Donkey durante o pareamento: " & polled.error)
        return ""
      continue
    failures = 0
    case polled.get.state
    of gpPending:
      discard
    of gpUnknown:
      rt.say(sessionId, "O código expirou sem confirmação. Mande outra mensagem para receber um novo.")
      return ""
    of gpPaired:
      let saved = rt.ports.saveToken(polled.get.token)
      if saved.isErr:
        rt.say(sessionId, "Conectado, mas não consegui guardar a credencial (" & saved.error &
                          "); na próxima vez será preciso parear de novo.\n\n")
      else:
        rt.say(sessionId, "Conectado.\n\n")
      return polled.get.token

proc closeTool(rt: AcpRuntime; st: TurnState; sessionId: string; ok = true) =
  if st.openTool.len > 0:
    rt.ports.write(toolCallFinished(sessionId, st.openTool, ok))
    st.openTool = ""

proc sinkFor(rt: AcpRuntime; st: TurnState; sessionId: string): LineSink =
  result = proc(line: string) {.gcsafe, raises: [].} =
    let event = parseStreamLine(line)
    case event.kind
    of sekText:
      rt.closeTool(st, sessionId)
      rt.ports.write(messageChunk(sessionId, event.text))
    of sekTool:
      ## The stream says when a tool starts; the next text, tool or the end
      ## says it finished. A chunk naming nothing, or the tool already open,
      ## starts nothing.
      if event.toolName.len == 0 and event.toolId.len == 0: return
      if event.toolId.len > 0 and event.toolId == st.openTool: return
      rt.closeTool(st, sessionId)
      inc st.tools
      st.openTool = if event.toolId.len > 0: event.toolId else: "tool-" & $st.tools
      rt.ports.write(toolCallStarted(sessionId, st.openTool, event.toolName))
    of sekFinish:
      st.finish = event.finishReason
    of sekError:
      rt.closeTool(st, sessionId, ok = false)
      rt.ports.write(messageChunk(sessionId, "\n\n⚠️ " & event.text))
    of sekDone, sekNone:
      discard

proc refusalText(reply: TurnReply): string =
  var message = ""
  try:
    message = parseJson(reply.body){"error"}{"message"}.getStr
  except CatchableError:
    discard
  if message.len == 0 and reply.body.len > 0 and reply.body.len < 300: message = reply.body.strip
  case reply.status
  of 429: "O Donkey ainda está respondendo a outra mensagem sua (429). Tente de novo em instantes."
  of 403: "O Donkey recusou: este acesso está bloqueado para você (403)."
  else: "O Donkey recusou o turno (" & $reply.status & ")" &
        (if message.len > 0: ": " & message else: ".")

proc streamTurn(rt: AcpRuntime; token: string; prompt: AcpPrompt): Future[string] {.
    async: (raises: [CancelledError]).} =
  let st = TurnState()
  var reply: TurnReply
  try:
    reply = await rt.ports.turn(token, prompt.text, rt.sinkFor(st, prompt.sessionId))
  finally:
    rt.closeTool(st, prompt.sessionId)
  case reply.status
  of 200:
    if reply.error.len > 0:
      rt.say(prompt.sessionId, "\n\n⚠️ A resposta foi interrompida: " & reply.error)
      return "end_turn"
    return stopReasonFor(st.finish)
  of 401:
    discard rt.ports.saveToken("")
    rt.say(prompt.sessionId, "Este editor não está mais conectado ao Donkey (a credencial " &
      "foi revogada). Mande outra mensagem para parear de novo.")
  of 0:
    rt.say(prompt.sessionId, "Não consegui falar com o Donkey: " & reply.error)
  else:
    rt.say(prompt.sessionId, refusalText(reply))
  return "end_turn"

proc runPrompt(rt: AcpRuntime; id: JsonNode; prompt: AcpPrompt) {.async: (raises: []).} =
  var stop = "end_turn"
  try:
    var token = rt.ports.loadToken()
    if token.len == 0:
      token = await rt.pairFor(prompt.sessionId)
    if token.len > 0:
      stop = await rt.streamTurn(token, prompt)
  except CancelledError:
    stop = "cancelled"
  rt.ports.write(promptResult(id, stop))

proc running(rt: AcpRuntime): bool =
  not rt.current.isNil and not rt.current.finished

proc handleRequest(rt: AcpRuntime; msg: AcpMessage) =
  case msg.methodName
  of "initialize":
    let info = msg.params{"clientInfo"}
    let name = if info.isNil: "" else: info{"title"}.getStr(info{"name"}.getStr)
    if name.len > 0: rt.editorName = name
    rt.ports.write(rpcResult(msg.id, initializeResult(msg.params, rt.version)))
  of "authenticate":
    rt.ports.write(rpcResult(msg.id, newJObject()))
  of "session/new":
    let sessionId = "donkey-" & $(rt.sessions.len + 1)
    rt.sessions.add sessionId
    rt.ports.write(rpcResult(msg.id, %* {"sessionId": sessionId}))
  of "session/prompt":
    let prompt = parsePrompt(msg.params)
    if prompt.isErr:
      rt.ports.write(rpcError(msg.id, RpcInvalidParams, prompt.error))
    elif prompt.get.sessionId notin rt.sessions:
      rt.ports.write(rpcError(msg.id, RpcInvalidParams, "unknown session " & prompt.get.sessionId))
    elif rt.running:
      rt.ports.write(rpcError(msg.id, RpcInvalidRequest, "a prompt is already running"))
    else:
      rt.currentSession = prompt.get.sessionId
      rt.current = rt.runPrompt(msg.id, prompt.get)
  else:
    rt.ports.write(rpcError(msg.id, RpcMethodNotFound, "Method not found: " & msg.methodName))

proc handleLine*(rt: AcpRuntime; line: string): Future[void] {.async: (raises: []).} =
  ## One line from the editor. A prompt runs in the background, so the
  ## editor's `session/cancel` can reach it.
  if line.strip.len == 0: return
  let parsed = parseAcpLine(line)
  if parsed.isErr:
    rt.ports.write(rpcError(newJNull(), RpcParseError, "Parse error"))
    return
  let msg = parsed.get
  case msg.kind
  of amRequest:
    rt.handleRequest(msg)
  of amNotification:
    if msg.methodName == "session/cancel" and rt.running and
       msg.params{"sessionId"}.getStr == rt.currentSession:
      rt.current.cancelSoon()
  of amResponse:
    discard   ## answers to requests Donkey sends (permissions, E10.4)

proc idle*(rt: AcpRuntime): Future[void] {.async: (raises: []).} =
  ## Waits for the running prompt, if any (tests, and a clean exit).
  if rt.running:
    await noCancel rt.current
