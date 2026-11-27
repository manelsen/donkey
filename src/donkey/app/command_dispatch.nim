## Command dispatch — one command policy for every channel.
##
## Decides WHAT a command answers, WHO may see the answer and which session
## side effect it has. Channels turn their events into a
## `CommandDispatchRequest` and present the `CommandOutcome`; they do not
## decide command policy themselves. This module depends only on `core`,
## `domain`, `ports` and the session manager, never on adapters.

import std/tables
import chronos/asyncsync
import ../core/pipeops
import ../core/commands/command_outcome
import ../core/commands/command_routing
import ../core/commands/command_text
import ../core/commands/preference_commands
import ../domain/agent_message
import ../domain/message
import ../ports/channel_capability
import ../ports/command_services
import ../ports/link_codes
import ./session_manager

export command_outcome

type
  SessionMode* = enum
    smRequireLive  ## a session task needs a live session; otherwise say so
    smCreate       ## start a session for the task when there is none

  EnsureSessionFn* = proc(kind: TaskKind; payload: string) {.gcsafe.}
    ## Starts (or reuses) the user's session and enqueues the task.

  CommandEnv* = object
    services*: CommandServicesPort

  CommandDispatchRequest* = object
    command*:       CommandDecision
    userId*:        UserId
    channel*:       ChannelKind
    messageId*:     string  ## reply target carried by an enqueued task
    rawId*:         string  ## channel-side identity of the speaker
    links*:         IdentityLinkPort
    sessionMode*:   SessionMode
    ensureSession*: EnsureSessionFn  ## smCreate only; nil → plain enqueue
    interactiveUi*: bool   ## help shows the interactive usage forms
    privateChat*:   bool   ## a one-to-one conversation (false when unknown: fail closed)

const NoLiveSessionText* = "Envie uma mensagem primeiro para iniciar o onboarding."
  ## The answer to a button pressed without a live session to take it.

proc enqueueSessionTask*(sm: var SessionManager; msgSeq: var int;
                         userId: UserId; kind: TaskKind; value: string;
                         channel: ChannelKind; messageId: string;
                         create = false): bool =
  ## Pushes a task into the user's session inbox. Without `create`, false when
  ## there is no live session (the caller tells the user).
  if not create and not sm.hasLiveSession(userId):
    return false
  let entry = sm.getOrCreate(userId)
  inc msgSeq
  entry.inbox.addLastNoWait(
    newTaskMsg($msgSeq, kind, $userId, value, channel, messageId))
  true

func helpTextFor*(channel: ChannelKind; interactiveUi: bool): string =
  buildHelpText(commandCaps(channel), interactiveUi)

func fromResult(topic: ReplyTopic; res: Result[string, string];
                errorPrefix = ""): CommandOutcome =
  if res.isOk: replied(topic, res.get)
  else: replied(topic, errorPrefix & res.error, failed = true)

proc reasoningReply(env: CommandEnv; userId: UserId): CommandOutcome =
  let prefs = env.services.channelPrefs(userId).valueOr:
    return replied(rtReasoning, preferencesUnreadableText(error), failed = true)
  let next = nextReasoning(prefs.reasoning)
  let saved = env.services.savePreference(userId, "reasoning", next)
  replied(rtReasoning, savedOrError(saved, reasoningToggleText(next)),
          failed = saved.isErr)

proc localReply(env: CommandEnv; sm: SessionManager;
                req: CommandDispatchRequest): CommandOutcome =
  let s = env.services
  let userId = req.userId
  let action = decideLocalCommandAction(req.command)
  let topic = localActionTopic(action)
  case action
  of lcaShowAbout:
    fromResult(topic, s.about(userId, sm.sessionCount()))
  of lcaStartIntro:
    replied(topic, buildStartIntroText())
  of lcaSkillCommand:
    fromResult(topic, s.skill(userId, req.command.value))
  of lcaGenerateLinkCode:
    replied(topic, buildLinkCodeText(req.links.mint(userId)))
  of lcaClearMemory:
    let cleared = s.clearMemory(userId)
    if cleared.isOk: replied(topic, "Memórias apagadas.")
    else: replied(topic, "Não foi possível apagar as memórias: " & cleared.error,
                  failed = true)
  of lcaDoctorReport:
    fromResult(topic, s.doctor(userId, sm.sessionCount()),
               "Não foi possível gerar o diagnóstico: ")
  of lcaHelpText:
    replied(topic, helpTextFor(req.channel, req.interactiveUi))
  of lcaShowMemory:
    fromResult(topic, s.memoryView(userId),
               "Não foi possível ler a memória: ")
  of lcaContinueLink:
    let linked = req.links.link(req.command.value, req.channel, req.rawId)
    replied(topic, buildContinueResultText(linked), failed = not linked)
  of lcaShowMenu:
    if commandAvailable(cmdMenu, commandCaps(req.channel)):
      replied(topic, buildMenuText())
    else:
      replied(rtUnsupported, UnsupportedCommandText)
  of lcaShowWhoami:
    let sessionId =
      if sm.hasLiveSession(userId): sm.entries.getOrDefault($userId).sessionId
      else: ""
    replied(topic, buildWhoamiText(userId, sessionId, req.rawId))
  of lcaReasoningToggle:
    reasoningReply(env, userId)
  of lcaGithub:
    if s.github == nil:
      replied(topic, "O GitHub não está habilitado nesta instância.", failed = true)
    else:
      fromResult(topic, s.github(userId, req.command.value, req.privateChat))
  of lcaEditor:
    if s.editor == nil:
      replied(topic, "Editores não estão habilitados nesta instância.", failed = true)
    else:
      fromResult(topic, s.editor(userId, req.command.value))
  of lcaNone:
    replied(rtUnsupported, UnsupportedCommandText)

proc dispatchUiCommand*(env: CommandEnv; req: CommandDispatchRequest): CommandOutcome =
  ## The text form of a UI command (/models, /think, /budget, /tasks, …).
  ## Needs no session, so channels with pickers can call it directly.
  let s = env.services
  let userId = req.userId
  let value = req.command.value
  case req.command.kind
  of cmdModels: fromResult(rtUi, s.models(userId, value))
  of cmdThink:  fromResult(rtUi, s.think(userId, value))
  of cmdBudget: fromResult(rtUi, s.budget(userId, value))
  of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    replied(rtUi, buildDeferredUiCommandText(req.command.kind))
  of cmdTasks:
    if s.taskBoard != nil: fromResult(rtUi, s.taskBoard(userId))
    else: replied(rtUi, buildTasksText())
  of cmdAgents:
    let counts = if s.toolCounts != nil: s.toolCounts() else: ToolCounts()
    replied(rtUi, buildAgentsText(counts.tools, counts.clients))
  of cmdPoll:   replied(rtUi, buildPollText())
  of cmdConfig:
    ## Channels with a config view present it themselves; this is the
    ## honest text form for when they cannot.
    if not commandAvailable(cmdConfig, commandCaps(req.channel)):
      return replied(rtUnsupported, UnsupportedCommandText)
    let prefs = s.channelPrefs(userId).valueOr:
      return replied(rtConfig, preferencesUnreadableText(error), failed = true)
    replied(rtConfig, buildConfigText(prefs, withButtons = false))
  else:
    replied(rtUnsupported, UnsupportedCommandText)

proc sessionTask(sm: var SessionManager; msgSeq: var int;
                 req: CommandDispatchRequest): CommandOutcome =
  let kind = req.command.kind
  let create = req.sessionMode == smCreate
  if not create and not sm.hasLiveSession(req.userId):
    return replied(rtNoSession, noSessionText(kind))
  if interruptsTurn(kind):
    ## The task is queued behind the busy actor: the stop flag and the
    ## approval denial must take effect before it, on every channel.
    requestTurnInterrupt(sm, req.userId)
  let taskKind = commandTaskKind(req.command)
  if create and req.ensureSession != nil:
    req.ensureSession(taskKind, "")
  else:
    discard enqueueSessionTask(sm, msgSeq, req.userId, taskKind, "",
                               req.channel, req.messageId, create = create)
  accepted(kind)

proc dispatchCommand*(env: CommandEnv;
                      sm: var SessionManager;
                      msgSeq: var int;
                      req: CommandDispatchRequest): CommandOutcome =
  case req.command.route
  of crLocal:       localReply(env, sm, req)
  of crSessionTask: sessionTask(sm, msgSeq, req)
  of crUi:          dispatchUiCommand(env, req)
  of crPing:        fromResult(rtPing, env.services.ping(req.userId))
  of crStatus:
    ## /allowlist shares the status route but has no handler of its own yet:
    ## it stays with the session instead of answering with /status.
    if req.command.kind != cmdStatus: fallback()
    else: fromResult(rtStatus, env.services.status(req.userId, sm.sessionCount()))
  of crCallback, crNone: fallback()
