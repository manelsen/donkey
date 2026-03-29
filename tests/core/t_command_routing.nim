import donkey/domain/message
import donkey/domain/agent_message
import std/unittest
import donkey/core/commands/command_routing

suite "core command routing":

  test "parseCommandText parses continue and callback payloads":
    let cont = parseCommandText("/continue abc123")
    let cb = parseCommandText("/callback models:back")
    check cont.kind == cmdContinue
    check cont.route == crLocal
    check cont.value == "abc123"
    check cb.kind == cmdCallback
    check cb.route == crCallback
    check cb.value == "models:back"

  test "parseCallbackData parses ui and core callbacks":
    let modelSet = parseCallbackData("models:set:openrouter:openai/gpt-4o")
    let modelPage = parseCallbackData("models:page:openrouter:2")
    let thinkSet = parseCallbackData("think:set:medium")
    let personality = parseCallbackData("personality:tone:warm")
    let name = parseCallbackData("name:Ada")
    check modelSet.kind == cbkModelsSet
    check modelSet.route == cbrUi
    check modelSet.provider == "openrouter"
    check modelSet.model == "openai/gpt-4o"
    check modelPage.kind == cbkModelsPage
    check modelPage.provider == "openrouter"
    check modelPage.page == 2
    check thinkSet.kind == cbkThinkSet
    check thinkSet.route == cbrUi
    check thinkSet.value == "medium"
    check personality.kind == cbkPersonality
    check personality.route == cbrSessionTask
    check name.kind == cbkName
    check name.route == cbrSessionTask

  test "callback helpers classify routes and task kinds":
    check isUiCallback(cbkModelsProvider)
    check isUiCallback(cbkThinkSet)
    check isCoreCallback(cbkPersonality)
    check isCoreCallback(cbkName)
    check decideCallbackRoute(cbkModelsBack) == cbrUi
    check decideCallbackRoute(cbkName) == cbrSessionTask
    check decideCallbackRoute(cbkUnknown) == cbrNone
    check callbackTaskKind(CallbackDecision(kind: cbkPersonality)) == tkPersonalityChoice
    check callbackTaskKind(CallbackDecision(kind: cbkName)) == tkNameChoice

  test "decideCallbackRequest wraps parser semantics":
    let decision = decideCallbackRequest(CallbackRequest(channel: ckTelegram, data: "name:Ada"))
    check decision.kind == cbkName
    check decision.route == cbrSessionTask

  test "parseCommandText parses ui and status commands":
    check parseCommandText("/models").kind == cmdModels
    check parseCommandText("/models").route == crUi
    check parseCommandText("/models gemini gemini-2.5-pro").value == "gemini gemini-2.5-pro"
    check parseCommandText("/think").kind == cmdThink
    check parseCommandText("/think medium").value == "medium"
    check parseCommandText("/budget").kind == cmdBudget
    check parseCommandText("/budget").route == crUi
    check parseCommandText("/budget cheap-first").value == "cheap-first"
    check parseCommandText("/ping").kind == cmdPing
    check parseCommandText("/ping").route == crPing
    check parseCommandText("/status").kind == cmdStatus
    check parseCommandText("/status").route == crStatus

  test "command kind helpers classify semantic groups":
    check isCoreCommand(cmdHelp)
    check isCoreCommand(cmdMyCode)
    check isLocalCommand(cmdHelp)
    check isSessionTaskCommand(cmdDebug)
    check isSessionTaskCommand(cmdReset)
    check isUiCommand(cmdModels)
    check isUiCommand(cmdThink)
    check isUiCommand(cmdBudget)
    check isPingCommand(cmdPing)
    check isStatusCommand(cmdStatus)
    check not isCoreCommand(cmdNone)

  test "decideCommandRequest wraps parser semantics":
    let decision = decideCommandRequest(CommandRequest(channel: ckTelegram, text: "/help"))
    check decision.kind == cmdHelp
    check decision.route == crLocal

  test "decideCommandRoute classifies key command families":
    check decideCommandRoute(cmdHelp) == crLocal
    check decideCommandRoute(cmdDebug) == crSessionTask
    check decideCommandRoute(cmdModels) == crUi
    check decideCommandRoute(cmdPing) == crPing
    check decideCommandRoute(cmdStatus) == crStatus
    check decideCommandRoute(cmdCallback) == crCallback
    check decideCommandRoute(cmdNone) == crNone

  test "commandTaskKind maps session task commands":
    check commandTaskKind(CommandDecision(kind: cmdDebug)) == tkDebugToggle
    check commandTaskKind(CommandDecision(kind: cmdReset)) == tkReset

  test "decideLocalCommandAction maps local command semantics":
    check decideLocalCommandAction(CommandDecision(kind: cmdStart)) == lcaStartIntro
    check decideLocalCommandAction(CommandDecision(kind: cmdMyCode)) == lcaGenerateLinkCode
    check decideLocalCommandAction(CommandDecision(kind: cmdForget)) == lcaClearMemory
    check decideLocalCommandAction(CommandDecision(kind: cmdDoctor)) == lcaDoctorReport
    check decideLocalCommandAction(CommandDecision(kind: cmdHelp)) == lcaHelpText
    check decideLocalCommandAction(CommandDecision(kind: cmdMemory)) == lcaShowMemory
    check decideLocalCommandAction(CommandDecision(kind: cmdContinue)) == lcaContinueLink
    check decideLocalCommandAction(CommandDecision(kind: cmdModels)) == lcaNone

  test "stripBotMention removes @botname suffix from command token":
    check stripBotMention("/models@Ostervalt")   == "/models"
    check stripBotMention("/models@Ostervalt ")  == "/models "
    check stripBotMention("/models@Bot arg")     == "/models arg"
    check stripBotMention("/models")             == "/models"
    check stripBotMention("/models args")        == "/models args"
    check stripBotMention("/start@MyBot")        == "/start"
    check stripBotMention("/think@Bot medium")   == "/think medium"
    check stripBotMention("hello@world")         == "hello@world"  ## non-command unchanged
    check stripBotMention("")                    == ""

  test "parseCommandText handles @botname suffix (group chat regression)":
    check parseCommandText("/models@Ostervalt").kind  == cmdModels
    check parseCommandText("/models@Ostervalt").route == crUi
    check parseCommandText("/think@Ostervalt").kind   == cmdThink
    check parseCommandText("/budget@Ostervalt").kind  == cmdBudget
    check parseCommandText("/start@MyBot").kind       == cmdStart
    check parseCommandText("/help@MyBot").kind        == cmdHelp
    check parseCommandText("/ping@MyBot").kind        == cmdPing
    ## With arguments after @botname — rare but possible
    check parseCommandText("/models@Bot gemini gemini-2.5-pro").kind  == cmdModels
    check parseCommandText("/models@Bot gemini gemini-2.5-pro").value == "gemini gemini-2.5-pro"

  test "parseCommandText parses /menu command":
    let result = parseCommandText("/menu")
    check result.kind == cmdMenu
    check result.route == crLocal

  test "parseCommandText parses /whoami command":
    let result = parseCommandText("/whoami")
    check result.kind == cmdWhoami
    check result.route == crLocal

  test "decideLocalCommandAction maps menu to show menu":
    let decision = CommandDecision(kind: cmdMenu)
    let action = decideLocalCommandAction(decision)
    check action == lcaShowMenu

  test "decideLocalCommandAction maps whoami to show whoami":
    let decision = CommandDecision(kind: cmdWhoami)
    let action = decideLocalCommandAction(decision)
    check action == lcaShowWhoami

  test "isCoreCommand includes menu and whoami":
    check isCoreCommand(cmdMenu) == true
    check isCoreCommand(cmdWhoami) == true
