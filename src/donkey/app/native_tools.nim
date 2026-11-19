## native_tools.nim — facade for the native (non-MCP) tool layer.
##
## The layer is split in two:
##   native_tools_types — NativeToolResult, NativeCtx, parse contexts, builders
##   native_dispatch    — parsers, category handlers, executeNativeTool
##
## Tool implementations live under app/tools/:
##   fs_tools       — paddock resolution, bash
##   text_tools      — hashline anchors, HTML stripping, todo_write
##   search_tools    — find, grep (with log.warn on errors)
##   web_tools       — fetch, Brave web_search
##   utility_tools   — calc, render_mermaid, inspect_image
##   task_tools      — task/job spawning, skill management
##
## executeNativeTool returns NativeToolResult:
##   handled=false  -> not a native tool; orchestrator falls through to ToolAgent
##   handled=true   -> result.text is the tool output
##   newHistory.isSome -> orchestrator must replace history (rewind)
##   checkpointNow  -> orchestrator must push current history to state.checkpoints

# ── Re-export all extracted tool modules (public API stability) ───────────────

import ./tools/fs_tools
import ./tools/text_tools
import ./tools/search_tools
import ./tools/web_tools
import ./tools/archive_tools
import ./tools/data_tools
import ./tools/utility_tools
import ./tools/audio_tools
import ./tools/task_tools
import ./tools/code_tools

export fs_tools        # resolveInPaddock, inPaddock, performBash
export text_tools      # HashlineAnchor, EditFileOpKind, EditFileOp, hashline
                       # helpers, stripHtml, applyTodoOps
export search_tools    # performFind, performFindWasm, performGrep, performGrepWasm
export web_tools       # FetchHardMax, FetchDefaultMax, performFetch, performWebSearch
export archive_tools   # performArchiveCreate, performArchiveExtract
export data_tools      # runJsonQuery, runTableQuery
export utility_tools   # performCalc, performRenderMermaid, performInspectImage,
                       # MermaidTempPrefix
export audio_tools     # performTranscribe, performSpeech
export task_tools      # performTask, nextJobId, buildTaskStartedText,
                       # spawnTaskJob, performManageSkills
export code_tools      # parseCodeRequest, runCodeRequestAsync, codeConfigFromEnv

# ── Contract and dispatch (public API stability) ─────────────────────────────

import ./native_tools_types
import ./native_dispatch

export native_tools_types
export native_dispatch
