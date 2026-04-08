## AgentRunner unit tests — pure logic only (no HTTP, no filesystem).

import std/[json, strutils, unittest]
import results
import donkey/app/agent_runner
import donkey/domain/message
import donkey/domain/personality
import donkey/ports/memory
import donkey/ports/tool
import donkey/core/log

proc fakeMemoryRuntime(): MemoryRuntimePort =
  MemoryRuntimePort(
    hasProfile: proc(userId: UserId): bool {.gcsafe.} = true,
    loadContext: proc(userId: UserId): UserContext {.gcsafe.} =
      UserContext(userId: userId, userMd: "# User", memoryMd: "", preferencesMd: ""),
    saveUserMd: proc(userId: UserId; content: string) {.gcsafe.} = discard,
    appendMemory: proc(userId: UserId; text: string) {.gcsafe.} = discard,
    savePreferences: proc(userId: UserId; content: string) {.gcsafe.} = discard,
    clearMemory: proc(userId: UserId) {.gcsafe.} = discard,
    resetBootstrap: proc(userId: UserId) {.gcsafe.} = discard,
    saveSession: proc(userId: UserId; sessionId: string; history: ConversationHistory) {.gcsafe.} = discard,
    saveIdentity: proc(userId: UserId; traits: PersonalityTraits; name: string) {.gcsafe.} = discard,
    loadIdentity: proc(userId: UserId): (string, PersonalityTraits) {.gcsafe.} = ("", PersonalityTraits()),
    paddockDir: proc(userId: UserId): string {.gcsafe.} = "",
    scheduleReminder: proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string {.gcsafe.} = "",
    loadDueReminders: proc(): seq[JsonNode] {.gcsafe.} = @[],
    deleteReminder: proc(userId: UserId; reminderId: string) {.gcsafe.} = discard,
  )

suite "parseOnboardingResponse":

  test "returns complete=false when marker absent":
    let r = parseOnboardingResponse("Hello! What's your name?")
    check not r.complete

  test "extracts all four fields when marker present":
    let text = """
Ótimo! Tenho tudo que preciso.
ONBOARDING_COMPLETE: name=Alice Wonderland|callMe=Alice|tz=UTC-3|lang=pt-BR
"""
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name   == "Alice Wonderland"
    check r.callMe == "Alice"
    check r.tz     == "UTC-3"
    check r.lang   == "pt-BR"

  test "handles marker at start of line":
    let text = "ONBOARDING_COMPLETE: name=Bob|callMe=Bob|tz=UTC+8|lang=zh-CN"
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name == "Bob"
    check r.lang == "zh-CN"

  test "handles extra whitespace around marker":
    let text = "  ONBOARDING_COMPLETE: name=X|callMe=X|tz=UTC|lang=en  "
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name == "X"

  test "returns complete=false for empty string":
    check not parseOnboardingResponse("").complete

  test "partial marker not matched":
    check not parseOnboardingResponse("ONBOARDING_INCOMPL: name=X").complete

suite "OnboardingSystem and DefaultSystem constants":

  test "OnboardingSystem mentions ONBOARDING_COMPLETE":
    check OnboardingSystem.contains("ONBOARDING_COMPLETE")

  test "DefaultSystem is non-empty":
    check DefaultSystem.len > 0

suite "AgentRunner tool history":

  test "runTurn records assistant tool call before tool result":
    var completions = 0
    let complete =
      proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
        inc completions
        if completions == 1:
          return ok(CompletionResponse(
            text: "",
            inputTokens: 1,
            outputTokens: 1,
            toolCalls: @[ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"x":1}""")],
          ))
        ok(CompletionResponse(text: "done", inputTokens: 1, outputTokens: 1))
    let toolPort = ToolRuntimePort(
      listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} =
        ok(@[ToolSchema(name: "calc", description: "calculator", inputSchema: %* {"type": "object"})]),
      invoke: proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.} =
        ok(ToolResult(callId: call.id, output: "2", isError: false)),
      close: proc() {.gcsafe.} = discard,
    )
    var runner = newAgentRunner(
      fakeMemoryRuntime(),
      complete,
      newLogger("test.agent_runner"),
      clients = @[toolPort],
      maxHistory = 20,
    )

    let result = runner.runTurn(UserId("u1"), "2+0")
    check result.isOk
    check result.get() == "done"
    check runner.history.len == 4
    check runner.history[0].role == roleUser
    check runner.history[1].role == roleAssistant
    check runner.history[1].toolCalls.len == 1
    check runner.history[1].toolCalls[0].id == "call_1"
    check runner.history[2].role == roleTool
    check runner.history[2].toolCallId == "call_1"
