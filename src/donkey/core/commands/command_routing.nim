## Pure command parsing and semantic routing helpers.

import std/strutils
import ../../domain/agent_message
import ../../domain/message

type
  CommandKind* = enum
    cmdNone
    cmdStart
    cmdForget
    cmdDoctor
    cmdHelp
    cmdMemory
    cmdDebug
    cmdReset
    cmdMyCode
    cmdContinue
    cmdModels
    cmdThink
    cmdBudget
    cmdPing
    cmdStatus
    cmdCallback

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
    lcaGenerateLinkCode
    lcaClearMemory
    lcaDoctorReport
    lcaHelpText
    lcaShowMemory
    lcaContinueLink

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

func decideCommandRoute*(kind: CommandKind): CommandRoute =
  case kind
  of cmdStart, cmdForget, cmdDoctor, cmdHelp, cmdMemory,
     cmdMyCode, cmdContinue:
    crLocal
  of cmdDebug, cmdReset:
    crSessionTask
  of cmdModels, cmdThink, cmdBudget:
    crUi
  of cmdPing:
    crPing
  of cmdStatus:
    crStatus
  of cmdCallback:
    crCallback
  of cmdNone:
    crNone

func newCommandDecision(kind: CommandKind; value = ""): CommandDecision =
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
  case cmd
  of "/start": newCommandDecision(cmdStart)
  of "/forget": newCommandDecision(cmdForget)
  of "/doctor": newCommandDecision(cmdDoctor)
  of "/help": newCommandDecision(cmdHelp)
  of "/memory": newCommandDecision(cmdMemory)
  of "/debug": newCommandDecision(cmdDebug)
  of "/reset": newCommandDecision(cmdReset)
  of "/mycode": newCommandDecision(cmdMyCode)
  of "/ping": newCommandDecision(cmdPing)
  of "/status": newCommandDecision(cmdStatus)
  else:
    if cmd.startsWith("/models "):
      newCommandDecision(cmdModels, cmd[8 .. ^1].strip)
    elif cmd.startsWith("/think "):
      newCommandDecision(cmdThink, cmd[7 .. ^1].strip)
    elif cmd.startsWith("/budget "):
      newCommandDecision(cmdBudget, cmd[8 .. ^1].strip)
    elif cmd == "/models":
      newCommandDecision(cmdModels)
    elif cmd == "/think":
      newCommandDecision(cmdThink)
    elif cmd == "/budget":
      newCommandDecision(cmdBudget)
    elif cmd.startsWith("/continue "):
      newCommandDecision(cmdContinue, cmd[10 .. ^1].strip)
    elif cmd.startsWith("/callback "):
      newCommandDecision(cmdCallback, cmd[10 .. ^1].strip)
    else:
      newCommandDecision(cmdNone)

func decideCommandRequest*(request: CommandRequest): CommandDecision =
  parseCommandText(request.text)

func decideLocalCommandAction*(decision: CommandDecision): LocalCommandAction =
  case decision.kind
  of cmdStart:
    lcaStartIntro
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
  else:
    lcaNone

func decideCallbackRoute*(kind: CallbackKind): CallbackRoute =
  case kind
  of cbkModelsProvider, cbkModelsSet, cbkModelsPage, cbkModelsBack, cbkThinkSet, cbkHelpPage:
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
  of cmdReset:
    tkReset
  else:
    tkUserMsg

func isCoreCommand*(kind: CommandKind): bool =
  kind in {
    cmdStart, cmdForget, cmdDoctor, cmdHelp, cmdMemory,
    cmdDebug, cmdReset, cmdMyCode, cmdContinue
  }

func isLocalCommand*(kind: CommandKind): bool =
  decideCommandRoute(kind) == crLocal

func isSessionTaskCommand*(kind: CommandKind): bool =
  decideCommandRoute(kind) == crSessionTask

func isUiCommand*(kind: CommandKind): bool =
  kind in {cmdModels, cmdThink, cmdBudget}

func isStatusCommand*(kind: CommandKind): bool =
  kind == cmdStatus

func isPingCommand*(kind: CommandKind): bool =
  kind == cmdPing
