## memory_capture_hook — Hook for capturing relevant info to memory.

import std/[options, strtabs, times]
import ../../ports/hook
import ../../core/types

type
  AppendMemoryFn* = proc(userId: UserId; text: string) {.gcsafe, raises: [].}

  MemoryCaptureConfig* = object
    captureFacts*:        bool
    captureDecisions*:   bool
    capturePreferences*: bool
    enabled*:            bool

func newMemoryCaptureConfig*(
  captureFacts: bool = true;
  captureDecisions: bool = true;
  capturePreferences: bool = true;
  enabled: bool = true;
): MemoryCaptureConfig =
  MemoryCaptureConfig(
    captureFacts: captureFacts,
    captureDecisions: captureDecisions,
    capturePreferences: capturePreferences,
    enabled: enabled,
  )

proc formatMemoryEntry*(content: string; kind: string): string {.gcsafe.} =
  let ts = now().utc().format("yyyy-MM-dd HH:mm")
  result = "## " & kind & " [" & ts & "]\n" & content & "\n"

func makeMemoryCaptureHook*(
  appendMemoryFn: AppendMemoryFn;
  config: MemoryCaptureConfig;
): HookFn =
  result = proc(ctx: HookContext): HookResult {.gcsafe.} =
    var modified = ctx
    
    if not config.enabled:
      modified.metadata["capture_status"] = "disabled"
      return newHookResultContinue(modified)
    
    if appendMemoryFn.isNil:
      modified.metadata["capture_status"] = "no_append_fn"
      return newHookResultContinue(modified)
    
    var entries: seq[string] = @[]
    
    if config.captureFacts:
      let factEntry = formatMemoryEntry(ctx.message, "Fact")
      entries.add(factEntry)
    
    if config.captureDecisions:
      let decisionEntry = formatMemoryEntry(ctx.message, "Decision")
      entries.add(decisionEntry)
    
    if config.capturePreferences:
      let prefEntry = formatMemoryEntry(ctx.message, "Preference")
      entries.add(prefEntry)
    
    if entries.len > 0:
      for entry in entries:
        appendMemoryFn(ctx.userId, entry)
      modified.metadata["capture_status"] = "captured"
      modified.metadata["capture_entries"] = $entries.len
    else:
      modified.metadata["capture_status"] = "no_entries"
    
    result = newHookResultContinue(modified)

func createMemoryCaptureHookDefinition*(
  name: string;
  appendMemoryFn: AppendMemoryFn;
  config: MemoryCaptureConfig;
): HookDefinition =
  HookDefinition(
    name: name,
    phase: hpPostLlm,
    handler: makeMemoryCaptureHook(appendMemoryFn, config),
    config: some(newStringTable(modeCaseInsensitive)),
  )
