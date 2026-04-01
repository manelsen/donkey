## Pure native tool dispatch semantics.

type
  NativeToolCategoryKind* = enum
    ntckLegacy
    ntckShell
    ntckWeb
    ntckUtility
    ntckSession
    ntckAgent

const
  LegacyNativeTools* = [
    "schedule_reminder",
    "current_time",
    "web_fetch",
  ]

  ShellNativeTools* = [
    "bash",
    "read_file",
    "edit_file",
    "find",
    "grep",
    "sed",
  ]

  WebNativeTools* = [
    "fetch",
    "web_search",
  ]

  UtilityNativeTools* = [
    "calc",
    "render_mermaid",
    "inspect_image",
  ]

  SessionNativeTools* = [
    "ask",
    "todo_write",
    "checkpoint",
    "rewind",
  ]

  AgentNativeTools* = [
    "task",
    "submit_result",
    "report_finding",
    "cancel_job",
    "await",
  ]

func categoryTools(kind: NativeToolCategoryKind): seq[string] =
  case kind
  of ntckLegacy: @LegacyNativeTools
  of ntckShell: @ShellNativeTools
  of ntckWeb: @WebNativeTools
  of ntckUtility: @UtilityNativeTools
  of ntckSession: @SessionNativeTools
  of ntckAgent: @AgentNativeTools

func nativeToolCategoryOrder*(): seq[NativeToolCategoryKind] =
  @[ntckLegacy, ntckShell, ntckWeb, ntckUtility, ntckSession, ntckAgent]

func classifyNativeTool*(name: string): seq[NativeToolCategoryKind] =
  for kind in nativeToolCategoryOrder():
    if name in kind.categoryTools:
      result.add(kind)

func isKnownNativeTool*(name: string): bool =
  classifyNativeTool(name).len > 0
