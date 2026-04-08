## Pure command parsing and semantic routing helpers.

import std/strutils
import ../../domain/agent_message
import ../../domain/message

type
  CommandKind* = enum
    cmdNone
    cmdStart
    cmdMenu
    cmdWhoami
    cmdSkill
    cmdForget
    cmdDoctor
    cmdHelp
    cmdMemory
    cmdDebug
    cmdReset
    cmdMyCode
    cmdContinue
    cmdConfig
    cmdVerbose
    cmdReasoning
    cmdModels
    cmdThink
    cmdBudget
    cmdPing
    cmdStatus
    cmdCallback
    cmdCompact
    cmdNew
    cmdExec
    cmdAllowlist
    cmdQueue
    cmdUsage
    cmdTasks
    cmdAgents
    cmdPoll
    cmdStop
    cmdRestart
    cmdBind
    cmdTts
  CommandRoute* = enum
    crNone
    crLocal
    crSessionTask
    crUi
    crPing
    crStatus
    crCallback

  CommandRequest* = object
    channel*: ChannelKind
    text*:    string

  CommandDecision* = object
    kind*:  CommandKind
    route*: CommandRoute
    value*: string

  LocalCommandAction* = enum
    lcaNone
    lcaStartIntro
    lcaShowMenu
    lcaShowWhoami
    lcaSkillCommand
    lcaGenerateLinkCode
    lcaClearMemory
    lcaDoctorReport
    lcaHelpText
    lcaShowMemory
    lcaContinueLink
    lcaReasoningToggle

  CallbackKind* = enum
    cbkUnknown
    cbkModelsProvider
    cbkModelsSet
    cbkModelsPage
    cbkModelsBack
    cbkThinkSet
    cbkHelpPage
    cbkPersonality
    cbkName
    cbkModels
    cbkThink
    cbkBudget
    cbkHelp
    cbkStatus
    cbkDoctor
    cbkForget
    cbkReset
    cbkMyCode
    cbkReasoning
    cbkMenu
    cbkConfig

  CallbackRoute* = enum
    cbrNone
    cbrUi
    cbrSessionTask

  CallbackRequest* = object
    channel*: ChannelKind
    data*:    string

  CallbackDecision* = object
    kind*:     CallbackKind
    route*:    CallbackRoute
    provider*: string
    model*:    string
    value*:    string
    page*:     int

func primaryCommandName*(kind: CommandKind): string =
  case kind
  of cmdStart: "/start"
  of cmdMenu: "/menu"
  of cmdWhoami: "/whoami"
  of cmdSkill: "/skill"
  of cmdForget: "/forget"
  of cmdDoctor: "/doctor"
  of cmdHelp: "/help"
  of cmdMemory: "/memory"
  of cmdDebug: "/debug"
  of cmdReset: "/reset"
  of cmdMyCode: "/mycode"
  of cmdContinue: "/continue"
  of cmdConfig: "/config"
  of cmdVerbose: "/verbose"
  of cmdReasoning: "/reasoning"
  of cmdModels: "/models"
  of cmdThink: "/think"
  of cmdBudget: "/budget"
  of cmdPing: "/ping"
  of cmdStatus: "/status"
  of cmdCallback: "/callback"
  of cmdCompact: "/compact"
  of cmdNew: "/new"
  of cmdExec: "/exec"
  of cmdAllowlist: "/allowlist"
  of cmdQueue: "/queue"
  of cmdUsage: "/usage"
  of cmdTasks: "/tasks"
  of cmdAgents: "/agents"
  of cmdPoll: "/poll"
  of cmdStop: "/stop"
  of cmdRestart: "/restart"
  of cmdBind: "/bind"
  of cmdTts: "/tts"
  of cmdNone: ""

func commandAliases*(kind: CommandKind): seq[string] =
  case kind
  of cmdModels:
    @["/model"]
  else:
    @[]

func commandAcceptsValue*(kind: CommandKind): bool =
  kind in {cmdModels, cmdThink, cmdBudget, cmdSkill, cmdContinue, cmdCallback}

func commandAllowsBare*(kind: CommandKind): bool =
  kind != cmdNone and kind notin {cmdContinue, cmdCallback}

func parseCommandKind*(token: string): CommandKind =
  if token.len == 0:
    return cmdNone
  for kind in low(CommandKind) .. high(CommandKind):
    if kind == cmdNone:
      continue
    if token == primaryCommandName(kind):
      return kind
    for alias in commandAliases(kind):
      if token == alias:
        return kind
  cmdNone

func decideCommandRoute*(kind: CommandKind): CommandRoute =
  case kind
  of cmdStart, cmdMenu, cmdWhoami, cmdSkill, cmdForget, cmdDoctor, cmdHelp, cmdMemory,
     cmdMyCode, cmdContinue, cmdReasoning:
    crLocal
  of cmdDebug, cmdReset, cmdCompact, cmdNew,
     cmdStop, cmdRestart, cmdBind:
    crSessionTask
  of cmdConfig, cmdTasks, cmdAgents, cmdPoll, cmdModels, cmdThink, cmdBudget,
     cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    crUi
  of cmdAllowlist:
    crStatus
  of cmdPing:
    crPing
  of cmdStatus:
    crStatus
  of cmdCallback:
    crCallback
  of cmdNone:
    crNone

func newCommandDecision*(kind: CommandKind; value = ""): CommandDecision =
  CommandDecision(kind: kind, route: decideCommandRoute(kind), value: value)

func stripBotMention*(text: string): string =
  ## Strips the @botname suffix Telegram appends in group chats.
  ## "/models@Ostervalt args" → "/models args"
  ## "/models@Ostervalt"     → "/models"
  ## "/models"               → "/models"  (unchanged)
  if text.len == 0 or text[0] != '/':
    return text
  let spaceIdx = text.find(' ')
  let token    = if spaceIdx >= 0: text[0 ..< spaceIdx] else: text
  let atIdx    = token.find('@')
  if atIdx > 0:
    let base = token[0 ..< atIdx]
    if spaceIdx >= 0: base & text[spaceIdx .. ^1] else: base
  else:
    text

func parseCommandText*(text: string): CommandDecision =
  let cmd = stripBotMention(text.strip)
  if cmd.len == 0 or cmd[0] != '/':
    return newCommandDecision(cmdNone)

  let spaceIdx = cmd.find(' ')
  let token = if spaceIdx >= 0: cmd[0 ..< spaceIdx] else: cmd
  let value = if spaceIdx >= 0: cmd[spaceIdx + 1 .. ^1].strip else: ""
  let kind = parseCommandKind(token)

  if kind == cmdNone:
    return newCommandDecision(cmdNone)
  if value.len == 0:
    return if commandAllowsBare(kind): newCommandDecision(kind)
           else: newCommandDecision(cmdNone)
  if commandAcceptsValue(kind):
    return newCommandDecision(kind, value)
  newCommandDecision(cmdNone)

func decideCommandRequest*(request: CommandRequest): CommandDecision =
  parseCommandText(request.text)

func decideLocalCommandAction*(decision: CommandDecision): LocalCommandAction =
  case decision.kind
  of cmdStart:
    lcaStartIntro
  of cmdMenu:
    lcaShowMenu
  of cmdWhoami:
    lcaShowWhoami
  of cmdSkill:
    lcaSkillCommand
  of cmdMyCode:
    lcaGenerateLinkCode
  of cmdForget:
    lcaClearMemory
  of cmdDoctor:
    lcaDoctorReport
  of cmdHelp:
    lcaHelpText
  of cmdMemory:
    lcaShowMemory
  of cmdContinue:
    lcaContinueLink
  of cmdReasoning:
    lcaReasoningToggle
  else:
    lcaNone
func decideCallbackRoute*(kind: CallbackKind): CallbackRoute =
  case kind
  of cbkModelsProvider, cbkModelsSet, cbkModelsPage, cbkModelsBack, cbkThinkSet, cbkHelpPage,
     cbkModels, cbkThink, cbkBudget, cbkHelp, cbkStatus, cbkDoctor, cbkForget, cbkReset, cbkMyCode, cbkReasoning, cbkMenu, cbkConfig:
    cbrUi
  of cbkPersonality, cbkName:
    cbrSessionTask
  of cbkUnknown:
    cbrNone

func newCallbackDecision(kind: CallbackKind;
                         value = "";
                         provider = "";
                         model = "";
                         page = 0): CallbackDecision =
  CallbackDecision(
    kind: kind,
    route: decideCallbackRoute(kind),
    provider: provider,
    model: model,
    value: value,
    page: page,
  )

func parseCallbackData*(data: string): CallbackDecision =
  case data
  of "models":    return newCallbackDecision(cbkModels)
  of "think":     return newCallbackDecision(cbkThink)
  of "budget":    return newCallbackDecision(cbkBudget)
  of "help":      return newCallbackDecision(cbkHelp)
  of "status":    return newCallbackDecision(cbkStatus)
  of "doctor":    return newCallbackDecision(cbkDoctor)
  of "forget":    return newCallbackDecision(cbkForget)
  of "reset":     return newCallbackDecision(cbkReset)
  of "mycode":    return newCallbackDecision(cbkMyCode)
  of "reasoning": return newCallbackDecision(cbkReasoning)
  of "menu":      return newCallbackDecision(cbkMenu)
  of "config":    return newCallbackDecision(cbkConfig)
  else: discard

  if data.startsWith("models:provider:"):
    return newCallbackDecision(cbkModelsProvider, provider = data[16 .. ^1])
  if data.startsWith("models:set:"):
    let parts = data[11 .. ^1].split(':', 1)
    if parts.len == 2:
      return newCallbackDecision(cbkModelsSet, provider = parts[0], model = parts[1])
  if data.startsWith("models:page:"):
    let parts = data[12 .. ^1].rsplit(':', 1)
    if parts.len == 2:
      try:
        return newCallbackDecision(cbkModelsPage, provider = parts[0], page = parseInt(parts[1]))
      except:
        return newCallbackDecision(cbkUnknown)
  if data == "models:back":
    return newCallbackDecision(cbkModelsBack)
  if data.startsWith("help:page:"):
    try:
      return newCallbackDecision(cbkHelpPage, page = parseInt(data[10 .. ^1]))
    except:
      return newCallbackDecision(cbkUnknown)
  if data.startsWith("think:set:"):
    return newCallbackDecision(cbkThinkSet, value = data[10 .. ^1])
  if data.startsWith("personality:"):
    return newCallbackDecision(cbkPersonality, value = data)
  if data.startsWith("name:"):
    return newCallbackDecision(cbkName, value = data)
  newCallbackDecision(cbkUnknown)

func decideCallbackRequest*(request: CallbackRequest): CallbackDecision =
  parseCallbackData(request.data)

func isCoreCallback*(kind: CallbackKind): bool =
  kind in {cbkPersonality, cbkName}

func isUiCallback*(kind: CallbackKind): bool =
  kind in {cbkModelsProvider, cbkModelsSet, cbkModelsPage, cbkModelsBack, cbkThinkSet, cbkHelpPage}

func callbackTaskKind*(callback: CallbackDecision): TaskKind =
  case callback.kind
  of cbkName:
    tkNameChoice
  of cbkPersonality:
    tkPersonalityChoice
  else:
    tkUserMsg

func commandTaskKind*(decision: CommandDecision): TaskKind =
  case decision.kind
  of cmdDebug:
    tkDebugToggle
  of cmdReasoning:
    tkReasoningToggle
  of cmdReset:
    tkReset
  of cmdCompact:
    tkCompact
  of cmdNew:
    tkNew
  of cmdStop:
    tkStop
  of cmdRestart:
    tkRestart
  of cmdBind:
    tkBind
  else:
    tkUserMsg

func isCoreCommand*(kind: CommandKind): bool =
  kind in {
    cmdStart, cmdMenu, cmdWhoami, cmdSkill, cmdForget, cmdDoctor, cmdHelp, cmdMemory,
    cmdDebug, cmdReset, cmdMyCode, cmdContinue
  }

func isLocalCommand*(kind: CommandKind): bool =
  decideCommandRoute(kind) == crLocal

func isSessionTaskCommand*(kind: CommandKind): bool =
  decideCommandRoute(kind) == crSessionTask

func isUiCommand*(kind: CommandKind): bool =
  kind in {cmdConfig, cmdTasks, cmdAgents, cmdPoll, cmdModels, cmdThink, cmdBudget,
           cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts, cmdReasoning}

func isStatusCommand*(kind: CommandKind): bool =
  kind == cmdStatus

func isPingCommand*(kind: CommandKind): bool =
  kind == cmdPing
