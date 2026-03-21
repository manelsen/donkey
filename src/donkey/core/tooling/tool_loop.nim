## Pure tool-loop decisions.

import std/[options, strutils]
import ../../domain/message

type
  ToolLoopRunResult* = object
    history*:       ConversationHistory
    finalText*:     string
    done*:          bool
    toolCallCount*: int

  CompletionHandlingResult* = object
    history*:    ConversationHistory
    finalText*:  string
    done*:       bool
    debugText*:  string

  ToolBatchState* = object
    history*:       ConversationHistory
    toolCallCount*: int
    aborted*:       bool
    recentCalls*:   seq[(string, string)]

  ToolLoopStreamDecision* = object
    useStreaming*: bool

  ToolLoopRoundKind* = enum
    tlrkUseStreaming
    tlrkHandleCompletion
    tlrkHandleToolBatch

  ToolLoopRoundDecision* = object
    kind*: ToolLoopRoundKind

  CompletionDecisionKind* = enum
    cdkRetryEmpty
    cdkFinishText
    cdkContinueToolCalls

  CompletionDecision* = object
    kind*:      CompletionDecisionKind
    finalText*: string
    debugText*: string

  ToolCallDecisionKind* = enum
    tcdExecute
    tcdAbortRepeated

  ToolCallDecision* = object
    kind*:        ToolCallDecisionKind
    repeatCount*: int
    abortText*:   string

  ToolBatchItemPlan* = object
    shouldAbort*:   bool
    abortText*:     string
    progressText*:  string

  ToolLoopTerminationKind* = enum
    tltkContinue
    tltkExceededMaxRounds

  ToolLoopTerminationDecision* = object
    kind*:      ToolLoopTerminationKind
    replyText*: string

func newToolBatchState*(history: ConversationHistory;
                        toolCallCount: int;
                        recentCalls: seq[(string, string)]): ToolBatchState =
  ToolBatchState(
    history: history,
    toolCallCount: toolCallCount,
    aborted: false,
    recentCalls: recentCalls,
  )

func newToolLoopState*(history: ConversationHistory): ToolLoopRunResult =
  ToolLoopRunResult(history: history)

func recentRepeatCount*(recentCalls: seq[(string, string)];
                        tc: ToolCallRequest): int =
  let callKey = (tc.name, tc.inputJson)
  for rc in recentCalls:
    if rc == callKey:
      inc result

func withRegisteredToolCall*(recentCalls: seq[(string, string)];
                             tc: ToolCallRequest): seq[(string, string)] =
  result = recentCalls
  result.add((tc.name, tc.inputJson))
  if result.len > 30:
    result = result[result.len - 30 .. ^1]

func withRegisteredToolCall*(tc: ToolCallRequest;
                             state: ToolBatchState): ToolBatchState =
  result = state
  result.recentCalls = withRegisteredToolCall(result.recentCalls, tc)

func withAbortedBatch*(_: ToolBatchItemPlan;
                       state: ToolBatchState): ToolBatchState =
  result = state
  result.aborted = true

func withToolResult*(tc: ToolCallRequest;
                     toolResultText: string;
                     newHistory: Option[ConversationHistory];
                     state: ToolBatchState): ToolBatchState =
  result = state
  if newHistory.isSome:
    result.history = newHistory.get()
  result.history.addToolResult(tc.id, tc.name, toolResultText)
  inc result.toolCallCount

func buildRepeatAbortText*(toolName: string; repeatCount: int): string =
  "⚠️ Loop detectado: '" & toolName & "' chamado " &
  $(repeatCount + 1) & " vezes com os mesmos argumentos. Interrompendo."

func buildCompletionDebugText*(r: CompletionResponse): string =
  "🔍 <b>[debug]</b> tokens in=" & $r.inputTokens &
  " out=" & $r.outputTokens &
  " chars=" & $r.text.len

func decideCompletion*(r: CompletionResponse; debugMode: bool): CompletionDecision =
  if r.toolCalls.len > 0:
    return CompletionDecision(kind: cdkContinueToolCalls)
  if r.text.len > 0:
    return CompletionDecision(
      kind: cdkFinishText,
      finalText: r.text,
      debugText: if debugMode: buildCompletionDebugText(r) else: "",
    )
  CompletionDecision(kind: cdkRetryEmpty)

func applyCompletionDecision*(history: ConversationHistory;
                              decision: CompletionDecision): CompletionHandlingResult =
  result.history = history
  case decision.kind
  of cdkFinishText:
    result.history.addAssistant(decision.finalText)
    result.finalText = decision.finalText
    result.debugText = decision.debugText
    result.done = true
  of cdkRetryEmpty:
    result.history.addUser("(Your response was empty. Please provide your answer.)")
  of cdkContinueToolCalls:
    discard

func decideToolCall*(recentCalls: seq[(string, string)];
                     tc: ToolCallRequest;
                     repeatAbortThreshold: int): ToolCallDecision =
  let repeatCount = recentRepeatCount(recentCalls, tc)
  if repeatCount >= repeatAbortThreshold:
    return ToolCallDecision(
      kind: tcdAbortRepeated,
      repeatCount: repeatCount,
      abortText: buildRepeatAbortText(tc.name, repeatCount),
    )
  ToolCallDecision(kind: tcdExecute, repeatCount: repeatCount)

func buildToolDebugCallText*(tc: ToolCallRequest): string =
  "🔧 <b>[debug tool]</b> " & tc.name & "\n<code>" & tc.inputJson & "</code>"

func buildToolDebugResultText*(toolName, toolResult: string): string =
  "📤 <b>[debug result]</b> " & toolName & "\n<code>" &
  toolResult[0 ..< min(200, toolResult.len)] & "</code>"

func buildToolProgressText*(toolName: string;
                            toolCallCount: int;
                            toolResult: string): string =
  let resultLines = toolResult.splitLines()
  let tail = resultLines[max(0, resultLines.len - 5) .. ^1].join("\n")
  let tailTrunc = if tail.len > 400: tail[0 ..< 400] & "…" else: tail
  "🔧 <code>" & toolName & "</code> [" & $toolCallCount & "]\n<code>" &
    tailTrunc & "</code>"

func planToolBatchItem*(recentCalls: seq[(string, string)];
                        tc: ToolCallRequest;
                        repeatAbortThreshold: int;
                        nextToolCallCount: int;
                        toolResultText: string): ToolBatchItemPlan =
  let callDecision = decideToolCall(recentCalls, tc, repeatAbortThreshold)
  case callDecision.kind
  of tcdAbortRepeated:
    ToolBatchItemPlan(
      shouldAbort: true,
      abortText: callDecision.abortText,
    )
  of tcdExecute:
    ToolBatchItemPlan(
      shouldAbort: false,
      progressText: buildToolProgressText(tc.name, nextToolCallCount, toolResultText),
    )

func withStreamFinalText*(finalText: string;
                          state: ToolLoopRunResult): ToolLoopRunResult =
  result = state
  result.finalText = finalText
  result.history.addAssistant(finalText)
  result.done = true

func withCompletionResult*(completion: CompletionHandlingResult;
                           state: ToolLoopRunResult): ToolLoopRunResult =
  result = state
  result.history = completion.history
  result.finalText = completion.finalText
  result.done = completion.done

func withToolBatchState*(batch: ToolBatchState;
                         state: ToolLoopRunResult): ToolLoopRunResult =
  result = state
  result.history = batch.history
  result.toolCallCount = batch.toolCallCount
  result.done = batch.aborted

func decideToolLoopStreaming*(round: int;
                              toolsCount: int;
                              streamingAvailable: bool): ToolLoopStreamDecision =
  ToolLoopStreamDecision(
    useStreaming: streamingAvailable and round == 1 and toolsCount == 0
  )

func decideToolLoopRound*(round: int;
                          toolsCount: int;
                          streamingAvailable: bool;
                          completion: CompletionResponse): ToolLoopRoundDecision =
  if decideToolLoopStreaming(round, toolsCount, streamingAvailable).useStreaming:
    return ToolLoopRoundDecision(kind: tlrkUseStreaming)
  let completionDecision = decideCompletion(completion, debugMode = false)
  case completionDecision.kind
  of cdkContinueToolCalls:
    ToolLoopRoundDecision(kind: tlrkHandleToolBatch)
  of cdkFinishText, cdkRetryEmpty:
    ToolLoopRoundDecision(kind: tlrkHandleCompletion)

func buildProviderErrorText*(errMsg: string): string =
  "Desculpe, ocorreu um erro: " & errMsg

func buildToolLoopExceededText*(maxRounds: int): string =
  "Tool call loop exceeded " & $maxRounds & " rounds"

func decideToolLoopTermination*(done: bool;
                                round: int;
                                maxRounds: int): ToolLoopTerminationDecision =
  if not done and round >= maxRounds:
    return ToolLoopTerminationDecision(
      kind: tltkExceededMaxRounds,
      replyText: buildToolLoopExceededText(maxRounds),
    )
  ToolLoopTerminationDecision(kind: tltkContinue)
