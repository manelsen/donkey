## Command outcome contract — what the application dispatcher hands a channel.
##
## The dispatcher decides WHAT to answer and WHO may see it; the channel only
## decides HOW to present it. Two obligations live in this contract so that no
## channel can get them wrong on its own:
##
##   - visibility: a requester-only reply (link codes, diagnostics, memory
##     dumps, identity) must never be posted where other people can read it;
##   - acknowledgement: an accepted session task is an outcome of its own, so
##     channels with an interaction protocol know they still owe a response.

import ./command_routing

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
    rtEditor        ## /editor (E10.2): the person's editors
    rtNoSession     ## session task requested but the user has no live session
    rtUi            ## text form of a UI command (/models, /think, …)
    rtUnsupported   ## no text form on this channel
    rtPing
    rtStatus
    rtMenu
    rtWhoami
    rtReasoning
    rtConfig

  ReplyVisibility* = enum
    rvPublic         ## may be posted where the command was sent
    rvRequesterOnly  ## only the person who sent the command may read it

  CommandReply* = object
    topic*:      ReplyTopic
    text*:       string
    visibility*: ReplyVisibility
    failed*:     bool  ## the action did not succeed (e.g. invalid link code)

  CommandOutcomeKind* = enum
    cokFallback  ## not a command: hand the message to the session
    cokReply     ## send `reply`
    cokAccepted  ## a session task was enqueued; interaction channels must ack

  CommandOutcome* = object
    case kind*: CommandOutcomeKind
    of cokReply:
      reply*: CommandReply
    of cokAccepted:
      task*: CommandKind
    of cokFallback:
      discard

  ReplyRoute* = enum
    rrConversation  ## answer where the command was sent
    rrPrivate       ## answer through the requester's private path
    rrNotice        ## no private path: post a fixed notice, never the content

const
  UnsupportedCommandText* = "Comando indisponível neste canal. Use /help."
  RequesterOnlyNotice* = "Envie este comando em mensagem direta."

func topicVisibility*(topic: ReplyTopic): ReplyVisibility =
  ## Link codes take over a session; doctor and memory expose private data;
  ## whoami leaks internal user and session ids.
  case topic
  of rtLinkCode, rtContinue, rtDoctor, rtMemory, rtWhoami, rtEditor: rvRequesterOnly
  else: rvPublic

func localActionTopic*(action: LocalCommandAction): ReplyTopic =
  case action
  of lcaShowAbout:        rtAbout
  of lcaStartIntro:       rtStartIntro
  of lcaShowMenu:         rtMenu
  of lcaShowWhoami:       rtWhoami
  of lcaSkillCommand:     rtSkill
  of lcaGenerateLinkCode: rtLinkCode
  of lcaClearMemory:      rtClearMemory
  of lcaDoctorReport:     rtDoctor
  of lcaHelpText:         rtHelp
  of lcaShowMemory:       rtMemory
  of lcaContinueLink:     rtContinue
  of lcaReasoningToggle:  rtReasoning
  of lcaEditor:           rtEditor
  of lcaNone:             rtUnsupported

func replied*(topic: ReplyTopic; text: string; failed = false): CommandOutcome =
  CommandOutcome(kind: cokReply, reply: CommandReply(
    topic: topic, text: text, visibility: topicVisibility(topic),
    failed: failed))

func accepted*(kind: CommandKind): CommandOutcome =
  CommandOutcome(kind: cokAccepted, task: kind)

func fallback*(): CommandOutcome =
  CommandOutcome(kind: cokFallback)

func requesterOnly*(reply: CommandReply): bool =
  reply.visibility == rvRequesterOnly

func shouldSend*(reply: CommandReply): bool =
  ## Plain-text channels stay silent on commands they have no text form for.
  reply.topic != rtUnsupported and reply.text.len > 0

func routeReply*(reply: CommandReply; inSharedSpace, hasPrivatePath: bool): ReplyRoute =
  ## Where a reply may go. A requester-only reply in a shared space goes
  ## through the private path; without one the channel posts a notice. There
  ## is no fallback from a failed private send to the shared space.
  if not reply.requesterOnly or not inSharedSpace: rrConversation
  elif hasPrivatePath: rrPrivate
  else: rrNotice

func acceptedText*(kind: CommandKind): string =
  ## Short confirmation for an accepted session task.
  case kind
  of cmdDebug:   "🐞 Alterando modo debug..."
  of cmdReset:   "🔄 Reiniciando bootstrap... vou avisar quando terminar."
  of cmdNew:     "🆕 Arquivando e iniciando nova sessão..."
  of cmdCompact: "🗜️ Compactando histórico..."
  of cmdStop:    "🛑 Parando execução..."
  of cmdRestart: "♻️ Reiniciando..."
  of cmdBind:    "🔗 Preparando vínculo..."
  else:          "✅ Comando recebido."

func noSessionText*(kind: CommandKind): string =
  ## What to say when a session command has no live session to act on.
  case kind
  of cmdDebug:   "Nenhuma sessão ativa. Envie uma mensagem primeiro."
  of cmdReset:   "Nenhuma conversa ativa para reiniciar."
  of cmdCompact: "Nenhuma conversa ativa para compactar."
  of cmdNew:     "Nenhuma conversa ativa para arquivar. Envie uma mensagem para começar uma."
  of cmdStop:    "Nada em execução para parar."
  of cmdRestart: "Nenhuma sessão ativa. Envie uma mensagem para começar uma."
  of cmdBind:    "Nenhuma sessão ativa para vincular. Envie uma mensagem primeiro."
  else:          ""

func replyDelivery*(reply: CommandReply; inSharedSpace, hasPrivatePath: bool):
                   tuple[route: ReplyRoute, text: string] =
  ## The route and the text to send on it: a notice replaces the content.
  let route = routeReply(reply, inSharedSpace, hasPrivatePath)
  (route, if route == rrNotice: RequesterOnlyNotice else: reply.text)

func requesterOnlyCommand*(command: CommandDecision): bool =
  ## True for commands whose answer is requester-only. A channel with no
  ## private path in a shared space refuses these before dispatching, so a
  ## link code is not minted (or consumed) where it cannot be answered.
  command.route == crLocal and
    topicVisibility(localActionTopic(decideLocalCommandAction(command))) ==
      rvRequesterOnly
