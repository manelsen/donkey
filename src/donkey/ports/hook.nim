## hook — Hook Port for message flow interception and context injection.
##
## Hooks are middleware-style interceptors that can modify message flow,
## inject context, and capture information at various phases of processing.
##
## Architecture: This is a Port (interface), not an Adapter.
## Implementations are in src/donkey/adapters/hooks/
##
## Hook Phases:
##   hpPreLlm      - Before LLM call, can modify/filter message
##   hpPostLlm     - After LLM response, can modify response
##   hpPreTool     - Before tool call, can validate/modify args
##   hpPostTool    - After tool execution, can capture results
##   hpPostResponse - After final response, can log/notify

import std/[options, strtabs]
import ../core/types
import ../domain/message

type
  HookPhase* = enum
    hpPreLlm
    hpPostLlm
    hpPreTool
    hpPostTool
    hpPostResponse

  HookContext* = object
    userId*:     UserId
    sessionId*:  string
    message*:    string
    history*:    Option[ConversationHistory]
    metadata*:   StringTableRef

  HookResultKind* = enum
    hrkContinue
    hrkModified
    hrkRejected

  HookResult* = object
    case kind*: HookResultKind
    of hrkContinue, hrkModified:
      context*: HookContext
    of hrkRejected:
      errorMessage*: string

  HookFn* = proc(ctx: HookContext): HookResult {.gcsafe, raises: [].}

  HookDefinition* = object
    name*:    string
    phase*:   HookPhase
    handler*: HookFn
    config*:  Option[StringTableRef]

  HookRegistry* = object
    hooks*: seq[HookDefinition]

  HookPort* = concept h
    h.name is string
    h.phase is HookPhase
    h.invoke(HookContext) is HookResult

func newHookContext*(
  userId: UserId;
  sessionId: string;
  message: string;
  history: Option[ConversationHistory] = none(ConversationHistory);
  metadata: StringTableRef = nil
): HookContext =
  HookContext(
    userId: userId,
    sessionId: sessionId,
    message: message,
    history: history,
    metadata: if metadata.isNil: newStringTable(modeCaseInsensitive) else: metadata,
  )

func newHookResultContinue*(ctx: HookContext): HookResult =
  HookResult(kind: hrkContinue, context: ctx)

func newHookResultModified*(ctx: HookContext; modifiedContent: string): HookResult =
  var modifiedCtx = ctx
  modifiedCtx.message = modifiedContent
  HookResult(kind: hrkModified, context: modifiedCtx)

func newHookResultRejected*(ctx: HookContext; error: string): HookResult =
  HookResult(kind: hrkRejected, errorMessage: error)

func newHookRegistry*(): HookRegistry =
  HookRegistry(hooks: @[])

func registerHook*(reg: var HookRegistry; hook: HookDefinition) =
  reg.hooks.add(hook)

func getHooksForPhase*(reg: HookRegistry; phase: HookPhase): seq[HookDefinition] =
  result = @[]
  for h in reg.hooks:
    if h.phase == phase:
      result.add(h)

proc executeHooks*(
  reg: HookRegistry;
  phase: HookPhase;
  ctx: HookContext
): HookResult {.gcsafe.} =
  var currentCtx = ctx
  let hooks = getHooksForPhase(reg, phase)
  for hook in hooks:
    if hook.handler.isNil:
      continue
    let hookResult = hook.handler(currentCtx)
    case hookResult.kind
    of hrkContinue:
      discard
    of hrkModified:
      currentCtx = hookResult.context
    of hrkRejected:
      return hookResult
  result = newHookResultContinue(currentCtx)
