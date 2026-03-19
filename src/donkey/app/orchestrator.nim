## OrchestratorAgent — per-session actor: debounce → memory → LLM → reply.
##
## Lifecycle:
##   Daemon spawns runOrchestrator as an asyncSpawn task (fire-and-forget).
##   The orchestrator loops forever, one collectWithDebounce cycle per turn.
##
## Onboarding state machine (new users):
##   opWakeUp → send wakeup + mode keyboard → opModeChoice
##   opModeChoice → Guided: opGuidedEnergy … opGuidedInitiative → name gen → opNameChoice
##               → Free: conversational LLM with IDENTITY_READY: marker → opNameChoice
##   opNameChoice → save identity → opUserName → opUserTimezone → opUserLanguage → opDone
##   opDone → normal LLM conversation with personality-aware system prompt.
##
## Debounce:
##   collectWithDebounce awaits the first task message, then keeps collecting
##   additional messages arriving within `DebounceWindowMs` using Chronos
##   withTimeout. Merged text is dispatched to the LLM as a single turn.
##
## Streaming:
##   When a StreamFn is provided, the LLM call runs in a dedicated OS thread
##   so SSE reading does not block the Chronos event loop. Tokens flow via a
##   Nim Channel[string] polled with sleepAsync(30ms). Every StreamFlushMs the
##   orchestrator flushes accumulated tokens to the global outbox as an
##   OutboundMessage with isPartial=true. The final flush has isPartial=false.

import std/json
import std/os
import std/strutils except strip
import std/strformat
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/log
import ../domain/agent_message
import ../domain/message
import ../domain/personality
import ../domain/reminder
import ../config/types as cfgTypes
import ../adapters/memory/md_file
import ../adapters/tool/mcp_client
import ./sandbox
import ../ports/provider
import ../ports/memory
import ./memory_agent
import ./tool_agent
import ./session_state
import ./native_tools

const
  MaxToolRoundsOrch    = 50   ## hard safety cap; loop ends earlier on repeated calls
  RepeatAbortThreshold = 2    ## abort if same (tool, args) seen ≥ this many times
  DebounceWindowMs*    = 1_200
  StreamFlushMs        = 1_000

type TypingFn* = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].}

func providerLabelFromPrefs*(prefs: string): string =
  ## Extracts "provider/model" label from PREFERENCES.md TOML content.
  ## Returns "zhipu" (default) when not set.
  var prov = "zhipu"
  var mdl  = ""
  for line in strutils.splitLines(prefs):
    let parts = strutils.split(line, '=', 1)
    if parts.len != 2: continue
    let k = strutils.strip(parts[0])
    let v = strutils.strip(parts[1]).strip(chars = {'"'})
    case k
    of "provider": prov = v
    of "model":    mdl  = v
    else: discard
  if mdl.len > 0: prov & "/" & mdl else: prov

# ── Helpers ────────────────────────────────────────────────────────────────────

proc safeComplete(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

func orchToolsSuffix(tools: seq[ToolDescription]): string =
  if tools.len == 0: return ""
  result = "\n\n## Available tools\n"
  for td in tools:
    result.add &"- **{td.name}**: {td.description}\n"

# ── Debounce collector ─────────────────────────────────────────────────────────

proc collectWithDebounce(inbox: AsyncQueue[AgentMessage];
                         windowMs: int): Future[AgentMessage] {.async.} =
  ## Waits for the first amkTask, then accumulates more within windowMs.
  ## Returns a single AgentMessage with all payloads joined by "\n\n".
  ## Returns amkCancel immediately if cancel arrives at any point.
  let first = await inbox.get()
  if first.kind != amkTask: return first   ## cancel / stray — pass through

  var texts   = @[first.payload]
  var latest  = first

  while true:
    let nextFut = inbox.get()
    if not (await withTimeout(nextFut, milliseconds(windowMs))):
      break   ## timeout — debounce window closed
    let next = nextFut.read()
    case next.kind
    of amkCancel: return next          ## cancel wins
    of amkTask:
      texts.add(next.payload)
      latest = next
    else: discard

  result         = latest
  result.payload = strutils.join(texts, "\n\n")

# ── Thinking tag filter ────────────────────────────────────────────────────────

func filterThinking*(text: string): string =
  ## Removes completed <thinking>...</thinking> blocks.
  ## If a <thinking> block has no closing tag yet, strips from <thinking> to end.
  const open  = "<thinking>"
  const close = "</thinking>"
  result = ""
  var i = 0
  while i < text.len:
    let s = text.find(open, i)
    if s < 0:
      result.add(text[i .. ^1])
      break
    result.add(text[i ..< s])
    let e = text.find(close, s)
    if e < 0: break
    i = e + close.len

# ── Thread-based streaming ─────────────────────────────────────────────────────

const doneSentinel = "\x00DONE"

type StreamJob* = object
  fn*:  StreamFn
  req*: CompletionRequest
  ch*:  ptr Channel[string]

proc doStreamJob*(job: StreamJob) {.thread.} =
  {.cast(gcsafe).}:
    discard job.fn(job.req,
                   proc(tok: string) = job.ch[].send(tok))
    job.ch[].send(doneSentinel)

proc streamToOutbox(fn:        StreamFn;
                    req:       CompletionRequest;
                    outbox:    AsyncQueue[OutboundMessage];
                    userId:    UserId;
                    ch:        ChannelKind;
                    replyTo:   string;
                    streamId:  string): Future[string] {.async.} =
  var tokenChan: Channel[string]
  tokenChan.open(512)

  var t: Thread[StreamJob]
  createThread(t, doStreamJob,
               StreamJob(fn: fn, req: req, ch: addr tokenChan))

  var accumulated = ""
  var lastFlush   = nowMs()

  while true:
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        let visible = filterThinking(accumulated)
        if visible.len > 0:
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      visible,
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        tokenChan.close()
        joinThread(t)
        return accumulated
      accumulated.add(tok)
      (has, tok) = tokenChan.tryRecv()

    let visible = filterThinking(accumulated)
    if visible.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
      lastFlush = nowMs()
      await outbox.put(OutboundMessage(
        userId:    userId,
        channel:   ch,
        text:      visible,
        replyTo:   replyTo,
        streamId:  streamId,
        isPartial: true,
      ))

    await sleepAsync(milliseconds(30))

  tokenChan.close()
  joinThread(t)
  return accumulated

# ── Name generation helper ─────────────────────────────────────────────────────

proc generateNames(completeFn: CompleteFn;
                   traits: PersonalityTraits): seq[string] {.gcsafe, raises: [].} =
  ## Asks LLM to suggest 5 names matching the given traits.
  ## Returns whatever names are parsed; empty seq on failure.
  var h = newHistory()
  h.addUser(buildNameGenPrompt(traits))
  let req  = buildPrompt(
    "You are a creative naming assistant. Output exactly 5 names, one per line, no numbering, no explanation.",
    h, "")
  let resp = safeComplete(completeFn, req)
  if resp.isErr: return @[]
  parseNameOptions(resp.value.text)

# ── Main orchestrator ──────────────────────────────────────────────────────────

proc runOrchestrator*(inbox:          AsyncQueue[AgentMessage];
                      globalOutbox:   AsyncQueue[OutboundMessage];
                      memory:         MdFileAdapter;
                      completeFn:     CompleteFn;
                      streamFn:       StreamFn;
                      clients:        seq[McpClientAdapter];
                      tools:          seq[ToolDescription];
                      typingFn:       TypingFn    = nil;
                      searchFn:       SearchFn    = nil;
                      log:            Logger      = newLogger("orch");
                      providerLabel:  string      = "?";
                      sandboxMode:    SandboxMode = smNone;
                      sandboxImage:   string      = "alpine"): Future[void] {.async.} =
  ## Persistent actor. Loops: debounce → memory → LLM → reply → repeat.
  let memInbox  = newAsyncQueue[AgentMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let workerOut = newAsyncQueue[AgentMessage]()

  asyncSpawn(runMemoryAgent(memInbox, workerOut, memory, searchFn))
  asyncSpawn(runToolAgent(toolInbox, workerOut, clients))
  sandboxLogLevel(sandboxMode, sandboxImage, log)

  var history:    ConversationHistory = newHistory()
  var debugMode:  bool = false
  var lastUserId: UserId
  let state = newSessionState()
  let sessionId   = $nowMs()
  let toolsSuffix = tools |> orchToolsSuffix

  ## Onboarding state.
  var obPhase:    OnboardingPhase = opWakeUp
  var obTraits:   PersonalityTraits
  var obNames:    seq[string]
  var obUserName: string
  var obTz:       string
  var obLang:     string

  ## Resolved agent identity (loaded from PREFERENCES.md once per session).
  var agentName:   string = ""
  var agentTraits: PersonalityTraits
  var identityLoaded = false

  var turnSeq = 0

  while true:
    let msg = await collectWithDebounce(inbox, DebounceWindowMs)

    case msg.kind

    of amkCancel:
      if $lastUserId != "":
        {.cast(gcsafe).}: memory.saveSession(lastUserId, sessionId, history)
      await memInbox.put(newCancelMsg())
      await toolInbox.put(newCancelMsg())
      break

    of amkTask:
      let uid    = UserId(msg.userId)
      lastUserId = uid
      let paddockDir = getHomeDir() / ".donkey" / "paddocks" / $uid
      {.cast(gcsafe).}: createDir(paddockDir)
      let nativeCtx = NativeCtx(
        uid:          uid,
        channel:      msg.channel,
        outbox:       globalOutbox,
        inbox:        inbox,
        completeFn:   completeFn,
        braveApiKey:  getEnv("BRAVE_API_KEY", ""),
        tools:        tools,
        log:          log,
        paddockDir:   paddockDir,
        sandboxMode:  sandboxMode,
        sandboxImage: sandboxImage,
      )

      ## ── inline keyboard helpers ───────────────────────────────────────────
      template replyText(txt: string) {.dirty.} =
        await globalOutbox.put(OutboundMessage(
          userId:  uid,
          channel: msg.channel,
          text:    txt,
          replyTo: msg.replyTo,
        ))

      template replyKeyboard(txt: string; kb: seq[seq[(string, string)]]) {.dirty.} =
        await globalOutbox.put(OutboundMessage(
          userId:   uid,
          channel:  msg.channel,
          text:     txt,
          replyTo:  msg.replyTo,
          keyboard: kb,
        ))

      ## ── session-level control tasks ───────────────────────────────────────
      if msg.taskKind == tkReset:
        let rstUid = UserId(msg.userId)
        {.cast(gcsafe).}: memory.saveSession(rstUid, sessionId, history)
        history = newHistory()
        replyText("Conversa reiniciada.")
        continue

      if msg.taskKind == tkDebugToggle:
        debugMode = not debugMode
        replyText(if debugMode: "🔍 Debug mode ON — tokens e tool calls serão exibidos."
                  else: "🔕 Debug mode OFF.")
        continue

      ## ── personality dimension choice (inline keyboard callback) ──────────
      if msg.taskKind == tkPersonalityChoice:
        ## payload = "personality:<dim>:<valor>"
        let parts = msg.payload.split(':', 2)
        if parts.len != 3:
          continue
        let (dim, valor) = (parts[1], parts[2])

        case obPhase
        of opModeChoice:
          if dim == "mode":
            if valor == "guided":
              obPhase = opGuidedEnergy
              let (txt, kb) = guidedDimensionMsg(dkEnergy)
              replyKeyboard(txt, kb)
            elif valor == "free":
              obPhase = opFreeConvo
              replyText("Ótimo! Descreva como imagina que eu devo ser — " &
                "meu jeito, meu tom, minha forma de responder. " &
                "Pode ser em poucas palavras ou um parágrafo.")

        of opGuidedEnergy:
          obTraits.energy = valor
          obPhase = opGuidedTone
          let (txt, kb) = guidedDimensionMsg(dkTone)
          replyKeyboard(txt, kb)

        of opGuidedTone:
          obTraits.tone = valor
          obPhase = opGuidedLength
          let (txt, kb) = guidedDimensionMsg(dkLength)
          replyKeyboard(txt, kb)

        of opGuidedLength:
          obTraits.length = valor
          obPhase = opGuidedInitiative
          let (txt, kb) = guidedDimensionMsg(dkInitiative)
          replyKeyboard(txt, kb)

        of opGuidedInitiative:
          obTraits.initiative = valor
          ## All dimensions set → generate names.
          var names: seq[string]
          {.cast(gcsafe).}: names = generateNames(completeFn, obTraits)
          obNames = names
          obPhase = opNameChoice
          if names.len > 0:
            var nameRow: seq[(string, string)]
            for n in names: nameRow.add((n, "name:" & n))
            replyKeyboard(
              "Aqui estão alguns nomes que combinam com essa personalidade. Qual prefere?",
              @[nameRow])
          else:
            replyText("Que nome você quer me dar?")

        else:
          discard  ## ignore in wrong phase
        continue

      ## ── name choice (inline keyboard or free-text fallback) ──────────────
      if msg.taskKind == tkNameChoice:
        ## payload = "name:<chosen-name>"
        let raw  = msg.payload
        let name = if raw.startsWith("name:"): raw[5 .. ^1] else: raw
        if name.len == 0: continue
        agentName   = name
        agentTraits = obTraits
        identityLoaded = true
        {.cast(gcsafe).}: memory.saveIdentity(uid, agentTraits, agentName)
        obPhase = opUserName
        replyText("Perfeito. Serei " & name & ".\n\nAgora me conta sobre você — qual é o seu nome?")
        continue

      ## ── unknown task kinds (worker tasks, etc.) ──────────────────────────
      if msg.taskKind notin {tkUserMsg}:
        continue

      ## ── tkUserMsg ─────────────────────────────────────────────────────────

      inc turnSeq
      let streamId = msg.userId & "-" & $turnSeq

      ## Check if onboarding is still in progress.
      let isNewUser = not memory.hasProfile(uid)

      if isNewUser:
        ## ── Onboarding state machine ────────────────────────────────────────
        let userText = (msg.payload |> strutils.strip)

        case obPhase

        of opWakeUp:
          ## First message from new user — send wakeup + mode choice keyboard.
          obPhase = opModeChoice
          replyKeyboard(
            "Olá. Acabei de ligar.\n\nComo quer definir minha personalidade?",
            @[@[("Guiado 🎛️", "personality:mode:guided"),
               ("Livre 💬",   "personality:mode:free")]])

        of opModeChoice, opGuidedEnergy, opGuidedTone, opGuidedLength, opGuidedInitiative:
          replyText("Use os botões acima para escolher.")

        of opFreeConvo:
          ## Conversational identity discovery — LLM checks for IDENTITY_READY:.
          const freeSystem = """You are discovering your own identity through conversation.
Your user will describe your personality, tone, and style.
Listen actively. Ask clarifying questions if needed.
When you have a clear picture of who you should be, output this exact block (no extra formatting):

IDENTITY_READY:
energy: <reservado|neutro|entusiasmado>
tone: <formal|neutro|casual>
length: <conciso|moderado|detalhado>
initiative: <reativo|moderado|proativo>

Then continue the conversation naturally. Only output the block when you are confident about all four dimensions."""

          history.addUser(userText)
          history.trimTo(20)
          let req  = buildPrompt(freeSystem, history, "")
          let resp = safeComplete(completeFn, req)
          if resp.isErr:
            replyText("Desculpe, erro: " & resp.error)
          else:
            let rawText = resp.value.text
            let parsed  = parseIdentityReady(rawText)
            let visible = stripIdentityReady(rawText)
            history.addAssistant(rawText)
            if visible.len > 0:
              replyText(visible)

            if parsed.isSome:
              obTraits = parsed.get()
              var names: seq[string]
              {.cast(gcsafe).}: names = generateNames(completeFn, obTraits)
              obNames = names
              obPhase = opNameChoice
              if names.len > 0:
                var nameRow: seq[(string, string)]
                for n in names: nameRow.add((n, "name:" & n))
                replyKeyboard(
                  "Com base em quem você quer que eu seja, aqui estão alguns nomes:",
                  @[nameRow])
              else:
                replyText("Que nome você quer me dar?")

        of opNameChoice:
          ## User typed a name instead of clicking a button.
          if userText.len > 0:
            agentName   = userText
            agentTraits = obTraits
            identityLoaded = true
            {.cast(gcsafe).}: memory.saveIdentity(uid, agentTraits, agentName)
            obPhase = opUserName
            replyText("Perfeito. Serei " & agentName & ".\n\nAgora me conta sobre você — qual é o seu nome?")

        of opUserName:
          obUserName = userText
          obPhase    = opUserTimezone
          replyText("Ótimo, " & obUserName & "! Em que fuso horário você está? " &
                    "(ex: America/Sao_Paulo, UTC-3, Europa/Lisboa)")

        of opUserTimezone:
          obTz    = userText
          obPhase = opUserLanguage
          replyText("Entendido. Qual idioma prefere que eu use? " &
                    "(ex: Português, English, Español)")

        of opUserLanguage:
          obLang  = userText
          obPhase = opDone
          let userMd = bootstrapUserMd(obUserName, obUserName, obTz, obLang)
          {.cast(gcsafe).}: memory.saveUserMd(uid, userMd)
          replyText("Tudo certo! Serei " & agentName & " e você é " & obUserName &
                    ".\n\nPronto para conversar. Como posso ajudar?")

        of opDone:
          discard  ## shouldn't reach here while isNewUser, fall through

        continue  ## onboarding turn done — skip normal LLM path

      ## ── Normal conversation turn ──────────────────────────────────────────

      ## Load agent identity from PREFERENCES.md once per session.
      if not identityLoaded:
        var loadedName: string
        var loadedTraits: PersonalityTraits
        {.cast(gcsafe).}: (loadedName, loadedTraits) = memory.loadIdentity(uid)
        agentName      = loadedName
        agentTraits    = loadedTraits
        identityLoaded = true
        obPhase        = opDone

      let personalityPrompt = buildPersonalityPrompt(agentTraits, agentName)
      let systemBase = (if personalityPrompt.len > 0:
                          personalityPrompt & "\n\n"
                        else:
                          "You are a personal AI assistant.\n\n") &
                       "Be helpful and remember what the user tells you. " &
                       "Respond in the user's preferred language." &
                       toolsSuffix

      ## 2. Load memory context.
      await memInbox.put(newTaskMsg(msg.id, tkLoadCtx, msg.userId, msg.payload))
      let ctxReply = await workerOut.get()
      let context  = if ctxReply.kind == amkResult: ctxReply.text else: ""

      ## 3. Build history turn.
      var userText     = msg.payload
      var userImageUrl = ""
      if msg.payload.len > 0 and msg.payload[0] == '{':
        try:
          let j = parseJson(msg.payload)
          userText     = j.getOrDefault("text").getStr(msg.payload)
          userImageUrl = j.getOrDefault("mediaUrl").getStr("")
        except: discard

      if userImageUrl.len > 0:
        history.addUserWithImage(userText, userImageUrl)
      else:
        history.addUser(userText)
      history.trimTo(20)

      log.info($uid & " (" & $msg.channel & ") -> [" & providerLabel & "] |" &
               $userText.len & "|")

      ## Start typing loop.
      var typingActive = true
      proc typingLoopProc() {.async.} =
        while typingActive:
          if typingFn != nil:
            {.cast(gcsafe).}: typingFn(uid, msg.channel)
          await sleepAsync(milliseconds(4_000))
      asyncSpawn typingLoopProc()

      var round        = 0
      var finalText    = ""
      var done         = false
      var recentCalls: seq[(string, string)] = @[]   ## (tool, inputJson) history
      var toolCallCount = 0
      let toolStatusId  = streamId & "-st"           ## stream id for the progress embed

      while not done and round < MaxToolRoundsOrch:
        inc round

        let req = buildPrompt(systemBase, history, context, tools)

        ## 4a. Streaming path.
        if streamFn != nil and round == 1:
          finalText = await streamToOutbox(
            streamFn, req, globalOutbox, uid, msg.channel, msg.replyTo, streamId)
          log.info($uid & " (" & $msg.channel & ") <- [" & providerLabel &
                   "] |" & $finalText.len & "| stream")
          history.addAssistant(finalText)
          done = true
          continue

        ## 4b. Blocking completion path.
        let resp = safeComplete(completeFn, req)

        if resp.isErr:
          replyText("Desculpe, ocorreu um erro: " & resp.error)
          done = true
          continue

        let r = resp.value

        if r.toolCalls.len == 0:
          if r.text.len > 0:
            log.info($uid & " (" & $msg.channel & ") <- [" & providerLabel &
                     "] |" & $r.text.len & "|")
            history.addAssistant(r.text)
            finalText = r.text
            done = true
            if debugMode:
              let dbgText = "🔍 <b>[debug]</b> tokens in=" & $r.inputTokens &
                            " out=" & $r.outputTokens &
                            " chars=" & $r.text.len
              await globalOutbox.put(OutboundMessage(
                userId: uid, channel: msg.channel, text: dbgText))
          else:
            history.addUser("(Your response was empty. Please provide your answer.)")
          continue

        ## 5. Tool calls.
        ## Record the assistant turn that issued the tool calls before results.
        history.addAssistantWithToolCalls(r.text, r.toolCalls)

        var toolLoopAborted = false

        for i, tc in r.toolCalls:
          ## Repetition guard — abort before executing the call.
          let callKey = (tc.name, tc.inputJson)
          var repeatCount = 0
          for rc in recentCalls:
            if rc == callKey: inc repeatCount
          if repeatCount >= RepeatAbortThreshold:
            replyText("⚠️ Loop detectado: '" & tc.name &
                      "' chamado " & $(repeatCount + 1) & " vezes com os mesmos argumentos. Interrompendo.")
            toolLoopAborted = true
            break
          recentCalls.add(callKey)
          if recentCalls.len > 30:
            recentCalls = recentCalls[recentCalls.len - 30 .. ^1]

          if debugMode:
            let dbgTool = "🔧 <b>[debug tool]</b> " & tc.name & "\n<code>" &
                          tc.inputJson & "</code>"
            await globalOutbox.put(OutboundMessage(
              userId: uid, channel: msg.channel, text: dbgTool))

          log.info("[tool] (" & tc.name & ") <- [" & providerLabel & "] |" &
                   $tc.inputJson.len & "|")

          var toolResult = ""

          ## schedule_reminder — needs memory access, handled here directly.
          if tc.name == ReminderToolName:
            toolResult = block:
              try:
                let j       = parseJson(tc.inputJson)
                let whenStr = j.getOrDefault("when").getStr("")
                let remMsg  = j.getOrDefault("message").getStr("")
                if whenStr.len == 0 or remMsg.len == 0:
                  "Error: both 'when' and 'message' are required."
                else:
                  let ts    = parseWhen(whenStr)
                  let chStr = $msg.channel
                  {.cast(gcsafe).}: discard memory.scheduleReminder(uid, chStr, ts, remMsg)
                  "Reminder scheduled."
              except CatchableError as e:
                "Error scheduling reminder: " & e.msg
          else:
            ## All other native tools dispatched via native_tools.nim.
            let nr = await executeNativeTool(tc, nativeCtx, state, history)
            if nr.handled:
              if nr.checkpointNow:
                state.checkpoints.add(history)
              if nr.newHistory.isSome:
                history = nr.newHistory.get()
              toolResult = nr.text
            else:
              let payload = $ %* {
                "name": tc.name, "id": tc.id, "inputJson": tc.inputJson
              }
              let taskId = msg.id & "-" & $round & "-" & $i
              await toolInbox.put(newTaskMsg(taskId, tkInvokeTool, "", payload))
              let toolReply = await workerOut.get()
              log.info("[tool] (" & tc.name & ") -> [" & providerLabel & "] |" &
                       $toolReply.text.len & "|")
              if debugMode:
                let dbgResult = "📤 <b>[debug result]</b> " & tc.name & "\n<code>" &
                                toolReply.text[0 ..< min(200, toolReply.text.len)] & "</code>"
                await globalOutbox.put(OutboundMessage(
                  userId: uid, channel: msg.channel, text: dbgResult))
              toolResult = toolReply.text

          history.addToolResult(tc.id, tc.name, toolResult)

          ## Progress embed — last 5 lines of result, edited in place.
          inc toolCallCount
          let resultLines = toolResult.splitLines()
          let tail = resultLines[max(0, resultLines.len - 5) .. ^1].join("\n")
          let tailTrunc = if tail.len > 400: tail[0 ..< 400] & "…" else: tail
          await globalOutbox.put(OutboundMessage(
            userId:    uid,
            channel:   msg.channel,
            text:      "🔧 <code>" & tc.name & "</code> [" & $toolCallCount & "]\n<code>" &
                       tailTrunc & "</code>",
            streamId:  toolStatusId,
            isPartial: true,
          ))

        if toolLoopAborted:
          done = true

      ## Stop typing loop.
      typingActive = false

      ## Close tool progress embed (if any tool calls happened).
      if toolCallCount > 0:
        await globalOutbox.put(OutboundMessage(
          userId:    uid,
          channel:   msg.channel,
          text:      "✅ " & $toolCallCount & " tool call(s)",
          streamId:  toolStatusId,
          isPartial: false,
        ))

      ## 6. Send final reply (non-streaming path only).
      if not done:
        replyText("Tool call loop exceeded " & $MaxToolRoundsOrch & " rounds")
      elif streamFn == nil:
        replyText(finalText)

    else:
      discard
