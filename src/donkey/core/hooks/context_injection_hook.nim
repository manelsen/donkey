## context_injection_hook — Abstract context injection hook.

import std/[options, strtabs]
import ../../ports/hook
import ../../ports/memory
import ../../core/types

const
  DefaultTopK* = 5
  ContextHintKey* = "hook_context_hint"
  MemoryHitsKey* = "hook_memory_hits"

func formatContextHint*(hits: seq[MemoryHit]; topK: int = DefaultTopK): string =
  if hits.len == 0:
    return ""
  
  result = "Contexto relevante:\n"
  var count = 0
  for hit in hits:
    if count >= topK:
      break
    inc count
    if hit.content.len > 200:
      result &= "- " & hit.content[0..<200] & "...\n"
    else:
      result &= "- " & hit.content & "\n"

func makeContextInjectionHookFn*(
  name: string;
  searchFn: SearchFn;
  topK: int = DefaultTopK;
): HookFn =
  result = proc(ctx: HookContext): HookResult {.gcsafe.} =
    var modified = ctx
    
    if searchFn.isNil:
      modified.metadata[ContextHintKey] = "No memory search available"
      modified.metadata[MemoryHitsKey] = "0"
      return newHookResultContinue(modified)
    
    let hits = searchFn(ctx.userId, ctx.message, topK)
    
    if hits.len > 0:
      let hint = formatContextHint(hits, topK)
      if hint.len > 0:
        modified.metadata[ContextHintKey] = hint
        modified.metadata[MemoryHitsKey] = $hits.len & " relevant memories found"
    else:
      modified.metadata[ContextHintKey] = ""
      modified.metadata[MemoryHitsKey] = "0"
    
    newHookResultContinue(modified)

func createContextInjectionHook*(
  name: string;
  searchFn: SearchFn;
  topK: int = DefaultTopK;
): HookDefinition =
  HookDefinition(
    name: name,
    phase: hpPreLlm,
    handler: makeContextInjectionHookFn(name, searchFn, topK),
    config: some(newStringTable(modeCaseInsensitive)),
  )
