## hook_executor — Hook execution engine for orchestrator integration.

import std/[options, strtabs]
import ../../ports/hook
import ../../core/types
import ../../domain/message

type
  HookExecutor* = object
    registry*: HookRegistry
    enabled*: bool

func newHookExecutor*(enabled: bool = true): HookExecutor =
  HookExecutor(
    registry: newHookRegistry(),
    enabled: enabled,
  )

func registerHook*(exec: var HookExecutor; hook: HookDefinition) =
  exec.registry.registerHook(hook)

proc executePhase*(
  exec: HookExecutor;
  phase: HookPhase;
  ctx: HookContext
): HookResult {.gcsafe.} =
  if not exec.enabled:
    return newHookResultContinue(ctx)
  
  let hooks = getHooksForPhase(exec.registry, phase)
  if hooks.len == 0:
    return newHookResultContinue(ctx)
  
  var currentCtx = ctx
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

func makeContextInjectionHook*(
  exec: var HookExecutor;
  name: string;
  phase: HookPhase;
  handler: HookFn
): HookDefinition =
  HookDefinition(
    name: name,
    phase: phase,
    handler: handler,
    config: none(StringTableRef),
  )
