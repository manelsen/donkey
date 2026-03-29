## rag_context_hook — RAG context hook adapter using semantic memory search.
##
## This adapter implements the context injection hook using SemanticMemoryPort.search().
## It is an example adapter that demonstrates how to use the hook system.
##
## The hook queries semantic memory for relevant context and injects it
## into the message metadata for the LLM to use.

import std/[options, strtabs]
import ../../ports/hook
import ../../ports/memory
import ../../core/types
import ../../core/hooks/context_injection_hook

type
  RagContextConfig* = object
    topK*:     int
    minScore*: float
    enabled*:  bool

func newRagContextConfig*(
  topK: int = 5;
  minScore: float = 0.0;
  enabled: bool = true;
): RagContextConfig =
  RagContextConfig(
    topK: topK,
    minScore: minScore,
    enabled: enabled,
  )

func makeRagContextHook*(
  searchFn: SearchFn;
  config: RagContextConfig;
): HookFn =
  result = proc(ctx: HookContext): HookResult {.gcsafe.} =
    var modified = ctx
    
    if not config.enabled:
      modified.metadata["rag_status"] = "disabled"
      return newHookResultContinue(modified)
    
    if searchFn.isNil:
      modified.metadata["rag_status"] = "no_search_fn"
      return newHookResultContinue(modified)
    
    let hits = searchFn(ctx.userId, ctx.message, config.topK)
    
    var filteredHits: seq[MemoryHit] = @[]
    for hit in hits:
      if hit.score >= config.minScore:
        filteredHits.add(hit)
    
    if filteredHits.len > 0:
      let hint = formatContextHint(filteredHits, config.topK)
      modified.metadata[ContextHintKey] = hint
      modified.metadata[MemoryHitsKey] = $filteredHits.len & " relevant memories"
      modified.metadata["rag_status"] = "success"
    else:
      modified.metadata[ContextHintKey] = ""
      modified.metadata[MemoryHitsKey] = "0"
      modified.metadata["rag_status"] = "no_hits"
    
    newHookResultContinue(modified)

func createRagContextHookDefinition*(
  name: string;
  searchFn: SearchFn;
  config: RagContextConfig;
): HookDefinition =
  HookDefinition(
    name: name,
    phase: hpPreLlm,
    handler: makeRagContextHook(searchFn, config),
    config: some(newStringTable(modeCaseInsensitive)),
  )
