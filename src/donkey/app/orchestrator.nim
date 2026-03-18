## OrchestratorAgent — per-session actor: debounce → memory → LLM → reply.
##
## Lifecycle:
##   Daemon spawns runOrchestrator as an asyncSpawn task (fire-and-forget).
##   The orchestrator loops forever, one collectWithDebounce cycle per turn.
##
## Debounce:
##   collectWithDebounce awaits the first task message, then keeps collecting
##   additional messages arriving within `DebounceWindowMs` using Chronos
##   withTimeout. Merged text is dispatched to the LLM as a single turn.
##   Timer precision: exact (withTimeout), not poll-quantised.
##
## Streaming:
##   When a StreamFn is provided, the LLM call runs in a dedicated OS thread
##   so SSE reading does not block the Chronos event loop. Tokens flow via a
##   Nim Channel[string] polled with sleepAsync(30ms). Every StreamFlushMs the
##   orchestrator flushes accumulated tokens to the global outbox as an
##   OutboundMessage with isPartial=true. The final flush has isPartial=false.
##
##   Each streaming turn has a unique streamId = userId & "-" & msgId so the
##   daemon can route partial/final edits to the correct channel message.
##
## Reply routing:
##   All replies go to globalOutbox: AsyncQueue[OutboundMessage].
##   The daemon drains globalOutbox and dispatches to channel adapters.
##   The channel + replyTo are carried from the incoming AgentMessage.

import std/json
import std/strutils except strip
import std/strformat
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../domain/agent_message
import ../domain/message
import ../adapters/memory/md_file
import ../adapters/tool/mcp_client
import ../ports/provider
import ./memory_agent
import ./tool_agent

const
  MaxToolRoundsOrch = 5
  DebounceWindowMs* = 1_200   ## ms — exact timer via withTimeout
  StreamFlushMs     = 1_000   ## ms between streaming partial edits

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

# ── Thread-based streaming ─────────────────────────────────────────────────────

const doneSentinel = "\x00DONE"

type StreamJob* = object   ## must hold only non-ref primitive data + closure
  fn*:  StreamFn
  req*: CompletionRequest
  ch*:  ptr Channel[string]

proc doStreamJob*(job: StreamJob) {.thread.} =
  ## Entry point for the streaming OS thread.
  ## Sends tokens to job.ch, then the sentinel.
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
  ## Runs SSE in a thread, polls tokens, flushes partials to outbox every
  ## StreamFlushMs. Returns the complete accumulated text.
  var tokenChan: Channel[string]
  tokenChan.open(512)

  var t: Thread[StreamJob]
  createThread(t, doStreamJob,
               StreamJob(fn: fn, req: req, ch: addr tokenChan))

  var accumulated = ""
  var lastFlush   = nowMs()

  while true:
    ## Drain whatever tokens arrived since last poll.
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        ## Final flush — send isPartial=false.
        if accumulated.len > 0:
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      accumulated,
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        tokenChan.close()
        joinThread(t)
        return accumulated
      accumulated.add(tok)
      (has, tok) = tokenChan.tryRecv()

    ## Periodic partial flush.
    if accumulated.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
      lastFlush = nowMs()
      await outbox.put(OutboundMessage(
        userId:    userId,
        channel:   ch,
        text:      accumulated,
        replyTo:   replyTo,
        streamId:  streamId,
        isPartial: true,
      ))

    await sleepAsync(milliseconds(30))

  ## Unreachable — loop exits via return inside doneSentinel branch.
  tokenChan.close()
  joinThread(t)
  return accumulated

# ── Main orchestrator ──────────────────────────────────────────────────────────

proc runOrchestrator*(inbox:       AsyncQueue[AgentMessage];
                      globalOutbox: AsyncQueue[OutboundMessage];
                      memory:      MdFileAdapter;
                      completeFn:  CompleteFn;
                      streamFn:    StreamFn;
                      clients:     seq[McpClientAdapter];
                      tools:       seq[ToolDescription]): Future[void] {.async.} =
  ## Persistent actor. Loops: debounce → memory → LLM → reply → repeat.
  let memInbox  = newAsyncQueue[AgentMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let workerOut = newAsyncQueue[AgentMessage]()

  asyncSpawn(runMemoryAgent(memInbox, workerOut, memory))
  asyncSpawn(runToolAgent(toolInbox, workerOut, clients))

  var history: ConversationHistory = newHistory()
  let toolsSuffix = tools |> orchToolsSuffix
  let systemBase = """You are Donkey, a personal AI assistant.
Be concise, helpful, and remember what the user tells you.
Respond in the user's preferred language.""" & toolsSuffix
  const onboardingSystem = """You are Donkey, meeting this person for the very first time.
Greet them warmly in one sentence. Then ask their name and how they'd like to be called.
Keep it to 2–3 sentences maximum. No bullet points, no feature lists."""

  var turnSeq = 0

  while true:
    ## 1. Collect one debounced turn (blocks until message arrives).
    let msg = await collectWithDebounce(inbox, DebounceWindowMs)

    case msg.kind

    of amkCancel:
      await memInbox.put(newCancelMsg())
      await toolInbox.put(newCancelMsg())
      break

    of amkTask:
      ## Handle session-level control tasks before the LLM path.
      if msg.taskKind == tkReset:
        history = newHistory()
        await globalOutbox.put(OutboundMessage(
          userId:  UserId(msg.userId),
          channel: msg.channel,
          text:    "Conversa reiniciada.",
          replyTo: msg.replyTo,
        ))
        continue

      if msg.taskKind != tkUserMsg:
        await globalOutbox.put(OutboundMessage(
          userId:  UserId(msg.userId),
          channel: msg.channel,
          text:    "Orchestrator: unexpected task: " & $msg.taskKind,
        ))
        continue

      inc turnSeq
      let uid      = UserId(msg.userId)
      let streamId = msg.userId & "-" & $turnSeq

      template replyMsg(replyText: string) {.dirty.} =
        await globalOutbox.put(OutboundMessage(
          userId:  uid,
          channel: msg.channel,
          text:    replyText,
          replyTo: msg.replyTo,
        ))

      ## 2. Load memory context; detect first contact for onboarding.
      await memInbox.put(newTaskMsg(msg.id, tkLoadCtx, msg.userId, ""))
      let ctxReply  = await workerOut.get()
      let context   = if ctxReply.kind == amkResult: ctxReply.text else: ""
      let isNewUser = needsOnboarding(memory.hasProfile(uid))
      let system    = if isNewUser: onboardingSystem else: systemBase

      ## 3. Build history turn.
      ## Payload may be JSON {"text":…,"mediaUrl":…} when an attachment is present.
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

      var round     = 0
      var finalText = ""
      var done      = false

      while not done and round < MaxToolRoundsOrch:
        inc round

        let req = buildPrompt(system, history, context, tools)

        ## 4a. Streaming path.
        if streamFn != nil and round == 1:
          ## Only stream the first round (tool-call rounds are non-streaming).
          finalText = await streamToOutbox(
            streamFn, req, globalOutbox, uid, msg.channel, msg.replyTo, streamId)
          history.addAssistant(finalText)
          done = true
          continue

        ## 4b. Blocking completion path.
        let resp = safeComplete(completeFn, req)

        if resp.isErr:
          replyMsg("Desculpe, ocorreu um erro: " & resp.error)
          done = true
          continue

        let r = resp.value

        if r.toolCalls.len == 0:
          if r.text.len > 0:
            history.addAssistant(r.text)
            finalText = r.text
            done = true
          else:
            history.addUser("(Your response was empty. Please provide your answer.)")
          continue

        ## 5. Tool calls — execute via ToolAgent.
        for i, tc in r.toolCalls:
          let payload = $ %* {
            "name": tc.name, "id": tc.id, "inputJson": tc.inputJson
          }
          let taskId = msg.id & "-" & $round & "-" & $i
          await toolInbox.put(newTaskMsg(taskId, tkInvokeTool, "", payload))
          let toolReply = await workerOut.get()
          history.addToolResult(tc.id, tc.name, toolReply.text)

      ## 6. Send final reply (non-streaming path only; streaming already sent).
      if not done:
        replyMsg("Tool call loop exceeded " & $MaxToolRoundsOrch & " rounds")
      elif streamFn == nil:
        ## Streaming already routed partials + final; non-streaming sends here.
        replyMsg(finalText)

    else:
      discard
