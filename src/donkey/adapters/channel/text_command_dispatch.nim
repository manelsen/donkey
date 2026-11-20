## text_command_dispatch — one command tree for every non-Telegram runtime.
##
## Feishu, WeChat, WhatsApp, WeCom, QQ, Slack and Discord used to carry their
## own copy of the same `case command.route` tree (crLocal / crSessionTask /
## crUi / crPing / crStatus). They only differ in *presentation* — markdown,
## embeds, ephemeral replies — and in a few channel-only actions (menus,
## whoami, reasoning toggle, button callbacks).
##
## Split:
##   - dispatchTextCommand decides WHAT to answer and performs the session-task
##     side effect; it returns a CommandOutcome.
##   - the runtime intercepts its channel-only actions *before* calling it, and
##     maps CommandReply.topic to its own presentation *after*.
##
## Topics the runtime does not care about just send `reply.text` as is.

import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ./common_runtime

type
  ReplyTopic* = enum
    rtAbout
    rtStartIntro
    rtSkill
    rtLinkCode
    rtClearMemory
    rtDoctor
    rtHelp
    rtMemory
    rtContinue
    rtNoSession     ## session task requested but the user has no live session
    rtUi            ## text form of a UI command (/models, /think, …)
    rtUnsupported   ## no text form here; most channels stay silent
    rtPing
    rtStatus
    ## Topics produced only by channel-specific extensions, never by
    ## dispatchTextCommand itself:
    rtMenu
    rtWhoami
    rtReasoning

  CommandReply* = object
    topic*:     ReplyTopic
    text*:      string
    sensitive*: bool  ## identity/diagnostics: send ephemerally where possible
    failed*:    bool  ## the action did not succeed (e.g. invalid link code)

  CommandOutcomeKind* = enum
    cokFallback  ## not handled here: hand the message to the session
    cokReply     ## send `reply`
    cokSilent    ## handled, nothing to send (task enqueued)

  CommandOutcome* = object
    case kind*: CommandOutcomeKind
    of cokReply:
      reply*: CommandReply
    of cokFallback, cokSilent:
      discard

  CommandEnv* = object
    ## Read-only daemon state the command builders need.
    memory*:             MdFileAdapter
    completeBuilder*:    proc(preferencesMd: string): CompleteFn {.gcsafe.}
    modelCatalogLoader*: ModelCatalogLoader
    toolsCount*:         int
    toolClientsCount*:   int
    daemonStartMs*:      int64

const UnsupportedCommandText* = "Comando indisponível neste canal. Use /help."

func replied*(topic: ReplyTopic; text: string;
             sensitive = false; failed = false): CommandOutcome =
  CommandOutcome(kind: cokReply, reply: CommandReply(
    topic: topic, text: text, sensitive: sensitive, failed: failed))

func noSessionText*(command: CommandDecision): string =
  if command.kind == cmdDebug: "Nenhuma sessão ativa. Envie uma mensagem primeiro."
  else: "Nenhuma conversa ativa para reiniciar."

proc enqueueSessionTask*(sm: var SessionManager; msgSeq: var int;
                         userId: UserId; kind: TaskKind; value: string;
                         channel: ChannelKind; messageId: string): bool =
  ## Pushes a task into the user's live session inbox. False when there is
  ## no live session (the caller tells the user).
  if not sm.hasLiveSession(userId):
    return false
  let entry = sm.getOrCreate(userId)
  inc msgSeq
  entry.inbox.addLastNoWait(
    newTaskMsg($msgSeq, kind, $userId, value, channel, messageId))
  true

proc localReply(env: CommandEnv; sm: SessionManager; command: CommandDecision;
                userId: UserId; channel: ChannelKind;
                resolver: IdentityResolver; rawId: string): CommandOutcome =
  let m = env.memory
  case decideLocalCommandAction(command)
  of lcaShowAbout:
    replied(rtAbout, buildAboutText(m, userId, env.toolsCount,
                                    env.toolClientsCount, sm.sessionCount()))
  of lcaStartIntro:
    replied(rtStartIntro, buildStartIntroText())
  of lcaSkillCommand:
    let text = applySkillTextCommand(m, userId, command.value,
                                     homeDir = m.donkeyHomeDir()).valueOr: error
    replied(rtSkill, text)
  of lcaGenerateLinkCode:
    replied(rtLinkCode, buildLinkCodeText(resolver.generateLinkCode(userId)),
            sensitive = true)
  of lcaClearMemory:
    replied(rtClearMemory, clearMemoryReply(m, userId))
  of lcaDoctorReport:
    replied(rtDoctor, buildDoctorReport(m, env.completeBuilder, userId,
                                        env.toolsCount, env.toolClientsCount,
                                        sm.sessionCount()),
            sensitive = true)
  of lcaHelpText:
    replied(rtHelp, buildHelpText(false))
  of lcaShowMemory:
    replied(rtMemory, buildMemoryViewText(m, userId), sensitive = true)
  of lcaContinueLink:
    let linked = resolver.consumeLinkCode(command.value, channel, rawId)
    replied(rtContinue, buildContinueResultText(linked),
            sensitive = true, failed = not linked)
  of lcaNone, lcaShowMenu, lcaShowWhoami, lcaReasoningToggle:
    replied(rtUnsupported, UnsupportedCommandText)

proc uiReply(env: CommandEnv; command: CommandDecision;
             userId: UserId): CommandOutcome =
  let m = env.memory
  case command.kind
  of cmdModels:
    let text = m.applyModelsTextCommand(userId, command.value,
                                        env.modelCatalogLoader).valueOr: error
    replied(rtUi, text)
  of cmdThink:
    let text = m.applyThinkTextCommand(userId, command.value).valueOr: error
    replied(rtUi, text)
  of cmdBudget:
    let text = m.applyBudgetTextCommand(userId, command.value).valueOr: error
    replied(rtUi, text)
  of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    replied(rtUi, buildDeferredUiCommandText(command.kind))
  else:
    replied(rtUnsupported, UnsupportedCommandText)

proc dispatchTextCommand*(env: CommandEnv;
                          sm: var SessionManager;
                          msgSeq: var int;
                          command: CommandDecision;
                          userId: UserId;
                          channel: ChannelKind;
                          messageId: string;
                          resolver: IdentityResolver;
                          rawId: string): CommandOutcome =
  ## `rawId` is the channel-side identity used to consume /continue codes.
  case command.route
  of crLocal:
    localReply(env, sm, command, userId, channel, resolver, rawId)
  of crSessionTask:
    if enqueueSessionTask(sm, msgSeq, userId, commandTaskKind(command), "",
                          channel, messageId):
      CommandOutcome(kind: cokSilent)
    else:
      replied(rtNoSession, noSessionText(command))
  of crUi:
    uiReply(env, command, userId)
  of crPing:
    replied(rtPing, buildPingText(env.memory, userId, env.completeBuilder))
  of crStatus:
    replied(rtStatus, buildTextStatusText(env.memory, userId, env.toolsCount,
                                          sm.sessionCount(), env.daemonStartMs))
  of crCallback, crNone:
    CommandOutcome(kind: cokFallback)

func shouldSend*(reply: CommandReply): bool =
  ## Plain-text channels stay silent on commands they have no text form for.
  reply.topic != rtUnsupported and reply.text.len > 0
